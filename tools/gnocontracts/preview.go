package main

import (
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// Static preview of this repo's realms.
//
// Boots gnodev on the selected realm directories, fetches each realm's gnoweb
// page plus every /public/ asset it references (recursively through CSS),
// rewrites the absolute /public/, /r/ and /p/ URLs to relative ones, and writes
// a self-contained static tree — so it can be dropped into a GitHub Pages
// subfolder (pr-<N>/) and browsed offline.
//
//	go tool gnocontracts preview -out _preview ./r/moul/hello/v0
//
// Selectors are repo-relative like the rest of the tooling: `./...` (the
// default), `./r/moul/hello/v0`, `./r/moul/...`.

var (
	assetRe   = regexp.MustCompile(`(?:href|src)="(/public/[^"?]*)`)
	cssURLRe  = regexp.MustCompile(`url\((/public/[^)"']*)`)
	appPathRe = regexp.MustCompile(`="/(r|p)/`)
	moduleRe  = regexp.MustCompile(`(?m)^[[:space:]]*module[[:space:]]*=[[:space:]]*"([^"]+)"`)
)

type previewRealm struct {
	pkgPath string // gno.land/r/moul/hello/v0
	dir     string // r/moul/hello/v0
}

// urlPath is the realm's path on gnoweb: gno.land/r/moul/hello/v0 → /r/moul/hello/v0.
func (r previewRealm) urlPath() string {
	_, rest, _ := strings.Cut(r.pkgPath, "/")
	return "/" + rest
}

func cmdPreview(root string, args []string) error {
	fs := flag.NewFlagSet("preview", flag.ContinueOnError)
	out := fs.String("out", "_preview", "output directory")
	port := fs.Int("port", 8899, "port to run gnodev on")
	gnodev := fs.String("gnodev", envOr("GNODEV", "gnodev"), "gnodev binary")
	timeout := fs.Duration("timeout", 2*time.Minute, "how long to wait for gnodev to serve the first realm")
	if err := fs.Parse(args); err != nil {
		return err
	}
	selectors := fs.Args()
	if len(selectors) == 0 {
		selectors = []string{"./..."}
	}

	realms, err := previewRealms(root, selectors)
	if err != nil {
		return err
	}
	if len(realms) == 0 {
		fmt.Printf("no previewable realms match %v\n", selectors)
		return nil
	}
	fmt.Printf("previewing %d realm(s)\n", len(realms))

	dirs := make([]string, 0, len(realms))
	for _, r := range realms {
		dirs = append(dirs, filepath.Join(root, filepath.FromSlash(r.dir)))
	}
	base := fmt.Sprintf("http://127.0.0.1:%d", *port)
	log, err := os.Create(filepath.Join(os.TempDir(), "gnocontracts-preview-gnodev.log"))
	if err != nil {
		return err
	}
	defer log.Close()

	cmd := exec.Command(*gnodev, append([]string{
		"local", "-no-watch", "-web-listener", fmt.Sprintf("127.0.0.1:%d", *port), "-C", root,
	}, dirs...)...)
	cmd.Stdout, cmd.Stderr = log, log
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start gnodev: %w", err)
	}
	defer func() {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	}()

	if !waitReady(base+realms[0].urlPath(), *timeout) {
		return fmt.Errorf("gnodev did not become ready within %s (see %s)", *timeout, log.Name())
	}
	return renderPreview(base, *out, realms)
}

// renderPreview fetches every realm page and asset and writes the static tree.
func renderPreview(base, out string, realms []previewRealm) error {
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}
	var rendered []previewRealm
	queue := map[string]bool{}

	for _, r := range realms {
		up := r.urlPath()
		body, err := fetch(base + up)
		if err != nil {
			fmt.Printf("  ! %s: %v\n", up, err)
			continue
		}
		html := string(body)
		for _, m := range assetRe.FindAllStringSubmatch(html, -1) {
			queue[m[1]] = true
		}
		if err := writeFileUnder(out, path.Join(strings.Trim(up, "/"), "index.html"),
			[]byte(rewritePage(html, relPrefix(up)))); err != nil {
			return err
		}
		rendered = append(rendered, r)
		fmt.Printf("  ✓ %s\n", up)
	}

	// Assets, recursing through CSS for @font-face url()s.
	seen := map[string]bool{}
	for len(queue) > 0 {
		var asset string
		for a := range queue {
			asset = a
			break
		}
		delete(queue, asset)
		key, _, _ := strings.Cut(asset, "?")
		if seen[key] {
			continue
		}
		seen[key] = true

		body, err := fetch(base + asset)
		if err != nil {
			fmt.Printf("  ! asset %s: %v\n", asset, err)
			continue
		}
		if strings.HasSuffix(key, ".css") {
			text := string(body)
			for _, m := range cssURLRe.FindAllStringSubmatch(text, -1) {
				if k, _, _ := strings.Cut(m[1], "?"); !seen[k] {
					queue[m[1]] = true
				}
			}
			body = []byte(strings.ReplaceAll(text, "/public/", cssRel(key)))
		}
		if err := writeFileUnder(out, strings.Trim(key, "/"), body); err != nil {
			return err
		}
	}
	fmt.Printf("  %d asset(s)\n", len(seen))

	if err := os.WriteFile(filepath.Join(out, "index.html"), []byte(previewIndex(rendered)), 0o644); err != nil {
		return err
	}
	fmt.Printf("done -> %s/index.html\n", out)
	return nil
}

// previewRealms finds the realms to render by scanning the filesystem, NOT
// contracts.json: a realm added by a source-only pull request is not in the
// catalog yet (the catalog is regenerated on main after merge) and would
// otherwise never be previewed. Archived realms are skipped.
func previewRealms(root string, selectors []string) ([]previewRealm, error) {
	var out []previewRealm
	rroot := filepath.Join(root, "r")
	if !fileExists(rroot) {
		return nil, nil
	}
	err := filepath.WalkDir(rroot, func(p string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || d.Name() != "gnomod.toml" {
			return err
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		m := moduleRe.FindSubmatch(b)
		if m == nil || ignoreRe.Match(b) || !strings.Contains(string(m[1]), "/r/") {
			return nil
		}
		rel, _ := filepath.Rel(root, filepath.Dir(p))
		rel = filepath.ToSlash(rel)
		if matchesSelector(rel, selectors) {
			out = append(out, previewRealm{pkgPath: string(m[1]), dir: rel})
		}
		return nil
	})
	sort.Slice(out, func(i, j int) bool { return out[i].pkgPath < out[j].pkgPath })
	return out, err
}

// matchesSelector applies the `./...`, `./dir/...`, `./dir` forms.
func matchesSelector(dir string, selectors []string) bool {
	for _, sel := range selectors {
		s := strings.TrimSuffix(strings.TrimPrefix(strings.TrimPrefix(sel, "./"), "/"), "/")
		switch {
		case s == "" || s == "...":
			return true
		case strings.HasSuffix(s, "/..."):
			base := strings.TrimSuffix(s, "/...")
			if dir == base || strings.HasPrefix(dir, base+"/") {
				return true
			}
		case dir == s || strings.HasPrefix(dir, s+"/"):
			return true
		}
	}
	return false
}

// rewritePage turns gnoweb's absolute app paths into paths relative to the page
// being written, so the tree browses from a file:// URL or a Pages subfolder.
func rewritePage(html, rel string) string {
	html = strings.ReplaceAll(html, `="/public/`, `="`+rel+`public/`)
	html = appPathRe.ReplaceAllString(html, `="`+rel+`$1/`)
	return strings.ReplaceAll(html, `="/favicon`, `="`+rel+`favicon`)
}

// relPrefix is the ../ chain back to the tree root from a page's directory:
// /r/moul/hello/v0 is four segments deep, so ../../../../.
func relPrefix(urlPath string) string {
	return strings.Repeat("../", len(strings.Split(strings.Trim(urlPath, "/"), "/")))
}

// cssRel rewrites /public/… references inside a stylesheet to be relative to
// that stylesheet's own directory.
func cssRel(cssKey string) string {
	parts := strings.Split(strings.Trim(cssKey, "/"), "/")
	depth := len(parts) - 1 // directories above the file, `public` included
	if depth > 1 {
		return strings.Repeat("../", depth-1)
	}
	return ""
}

func previewIndex(realms []previewRealm) string {
	var rows strings.Builder
	for _, r := range realms {
		rows.WriteString(fmt.Sprintf("    <li><a href=%q><code>%s</code></a></li>\n",
			strings.Trim(r.urlPath(), "/")+"/index.html", r.pkgPath))
	}
	return fmt.Sprintf(`<!doctype html>
<meta charset="utf-8">
<title>gno-contracts — realm preview</title>
<style>body{font-family:system-ui,sans-serif;max-width:48rem;margin:3rem auto;padding:0 1rem}
code{background:#f3f3f3;padding:.1em .3em;border-radius:3px}li{margin:.3em 0}</style>
<h1>Realm preview</h1>
<p>%d realm(s), rendered with gnodev/gnoweb. This is a static snapshot;
interactive actions and cross-realm nav that leave these pages won't work.</p>
<ul>
%s</ul>
`, len(realms), rows.String())
}

func writeFileUnder(out, rel string, body []byte) error {
	dst := filepath.Join(out, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	return os.WriteFile(dst, body, 0o644)
}

func fetch(url string) ([]byte, error) {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s", resp.Status)
	}
	return io.ReadAll(resp.Body)
}

func waitReady(url string, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if _, err := fetch(url); err == nil {
			return true
		}
		time.Sleep(2 * time.Second)
	}
	return false
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
