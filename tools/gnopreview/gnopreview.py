#!/usr/bin/env python3
"""gnopreview — extract a static gnoweb preview of this repo's realms.

POC for gno-contracts#43. It boots `gnodev` on the selected realm directories,
crawls each realm's gnoweb page plus every `/public/` asset it references
(recursively through CSS), rewrites the absolute `/public/`, `/r/`, `/p/` URLs to
*relative* paths, and writes a self-contained static tree — so it can be dropped
straight into a GitHub Pages subfolder (e.g. `pr-<N>/`) and browsed offline.

Usage:
  gnopreview.py --out _preview [--port 8899] [--gnodev gnodev] [SELECTOR ...]

SELECTORs are repo-relative like the rest of the tooling: `./...` (default),
`./r/moul/hello`, `./r/moul/...`. Only realms (r/*) that aren't draft/ignored are
previewed (pure packages have no Render).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import urllib.error

PUBLIC_RE = re.compile(r'(?:href|src)="(/public/[^"?]*)')
CSSURL_RE = re.compile(r'url\((/public/[^)"\']*)')


def load_realms(root, selectors):
    """Discover realms by scanning the filesystem (NOT contracts.json) — so realms
    added in a source-only PR, which aren't in the catalog yet, are still found.
    Only realms (r/*) that aren't `ignore = true` are previewed."""
    out = []
    rroot = os.path.join(root, "r")
    if not os.path.isdir(rroot):
        return out
    for dirpath, _dirs, files in os.walk(rroot):
        if "gnomod.toml" not in files:
            continue
        gm = os.path.join(dirpath, "gnomod.toml")
        module = ignore = None
        with open(gm) as f:
            for line in f:
                t = line.strip()
                if t.startswith("module") and '"' in t:
                    module = t.split('"')[1]
                elif t.replace(" ", "").startswith("ignore=true"):
                    ignore = True
        if not module or ignore or "/r/" not in module:
            continue
        reldir = os.path.relpath(dirpath, root)
        if matches(reldir, selectors):
            out.append({"pkgpath": module, "dir": reldir})
    return sorted(out, key=lambda c: c["pkgpath"])


def matches(dir, selectors):
    for sel in selectors:
        s = sel.lstrip("./").rstrip("/")
        if s in ("", "..."):
            return True
        if s.endswith("/..."):
            base = s[:-4]
            if dir == base or dir.startswith(base + "/"):
                return True
        elif dir == s or dir.startswith(s + "/"):
            return True
    return False


def url_of(pkgpath):  # gno.land/r/moul/hello/v1 -> /r/moul/hello/v1
    return "/" + pkgpath.split("/", 1)[1]


def wait_ready(base, probe, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(base + probe, timeout=3) as r:
                if r.status == 200:
                    return True
        except Exception:
            pass
        time.sleep(2)
    return False


def fetch(base, path):
    with urllib.request.urlopen(base + path, timeout=15) as r:
        return r.read()


def rel_prefix(url_path):
    # depth of the page dir: /r/moul/hello/v1 -> 4 segments -> ../../../../
    depth = len([p for p in url_path.strip("/").split("/") if p])
    return "../" * depth


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="_preview")
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--gnodev", default=os.environ.get("GNODEV", "gnodev"))
    ap.add_argument("selectors", nargs="*", default=["./..."])
    args = ap.parse_args()
    selectors = args.selectors or ["./..."]

    root = os.getcwd()
    while not os.path.exists(os.path.join(root, "gnowork.toml")):
        parent = os.path.dirname(root)
        if parent == root:
            sys.exit("gnowork.toml not found in any parent")
        root = parent

    realms = load_realms(root, selectors)
    if not realms:
        print("no previewable realms match", selectors)
        return
    print(f"previewing {len(realms)} realm(s)")

    base = f"http://127.0.0.1:{args.port}"
    dirs = [os.path.join(root, c["dir"]) for c in realms]
    proc = subprocess.Popen(
        [args.gnodev, "local", "-no-watch", "-web-listener", f"127.0.0.1:{args.port}", "-C", root, *dirs],
        stdout=open("/tmp/gnopreview-gnodev.log", "w"), stderr=subprocess.STDOUT,
    )
    try:
        if not wait_ready(base, url_of(realms[0]["pkgpath"])):
            sys.exit("gnodev did not become ready (see /tmp/gnopreview-gnodev.log)")

        os.makedirs(args.out, exist_ok=True)
        assets = set()
        rendered = []

        # 1. realm pages
        for c in realms:
            up = url_of(c["pkgpath"])
            try:
                html = fetch(base, up).decode("utf-8", "replace")
            except Exception as e:
                print(f"  ! {up}: {e}")
                continue
            for a in PUBLIC_RE.findall(html):
                assets.add(a)
            rel = rel_prefix(up)
            html = rewrite_page(html, rel)
            dst = os.path.join(args.out, up.strip("/"), "index.html")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w") as f:
                f.write(html)
            rendered.append((c, up))
            print(f"  ✓ {up}")

        # 2. assets (recurse through CSS for @font-face url()s)
        seen = set()
        queue = list(assets)
        while queue:
            a = queue.pop()
            key = a.split("?", 1)[0]
            if key in seen:
                continue
            seen.add(key)
            try:
                body = fetch(base, a)
            except Exception as e:
                print(f"  ! asset {a}: {e}")
                continue
            if key.endswith(".css"):
                text = body.decode("utf-8", "replace")
                for u in CSSURL_RE.findall(text):
                    if u.split("?", 1)[0] not in seen:
                        queue.append(u)
                # inside public/, /public/x -> x (relative to the css file's dir)
                text = re.sub(r'/public/', css_rel(key), text)
                body = text.encode()
            dst = os.path.join(args.out, key.strip("/"))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "wb") as f:
                f.write(body)
        print(f"  {len(seen)} asset(s)")

        # 3. index
        write_index(args.out, rendered)
        print(f"done -> {args.out}/index.html")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()


def rewrite_page(html, rel):
    # absolute app paths -> relative to this page's directory
    html = html.replace('="/public/', '="' + rel + 'public/')
    html = re.sub(r'="/(r|p)/', '="' + rel + r'\1/', html)
    html = html.replace('="/favicon', '="' + rel + 'favicon')
    return html


def css_rel(css_key):
    # css at /public/main.css -> its dir is /public/ ; /public/x -> ../x relative
    depth = len([p for p in css_key.strip("/").split("/")[:-1] if p])  # dirs above the file, minus leading public
    return "../" * (depth - 1) if depth > 1 else ""


def write_index(out, rendered):
    rows = "\n".join(
        f'    <li><a href="{up.strip("/")}/index.html"><code>{c["pkgpath"]}</code></a></li>'
        for c, up in sorted(rendered, key=lambda x: x[0]["pkgpath"])
    )
    html = f"""<!doctype html>
<meta charset="utf-8">
<title>gno-contracts — realm preview</title>
<style>body{{font-family:system-ui,sans-serif;max-width:48rem;margin:3rem auto;padding:0 1rem}}
code{{background:#f3f3f3;padding:.1em .3em;border-radius:3px}}li{{margin:.3em 0}}</style>
<h1>Realm preview</h1>
<p>{len(rendered)} realm(s), rendered with gnodev/gnoweb. This is a static snapshot;
interactive actions and cross-realm nav that leave these pages won't work.</p>
<ul>
{rows}
</ul>
"""
    with open(os.path.join(out, "index.html"), "w") as f:
        f.write(html)


if __name__ == "__main__":
    main()
