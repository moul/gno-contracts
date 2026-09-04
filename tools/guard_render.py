#!/usr/bin/env python3
"""Fail if a realm declares `func Render` but no test ever calls it.

A realm's `Render` is its whole public surface, and in gno a `Render` whose
output varies is a consensus bug — so it must be pinned by a test. Nothing
enforced that: five realms shipped with `Render` never once invoked from a test.

Coverage counts from EITHER a normal `*_test.gno` or a `*_filetest.gno`, and the
call may be bare (`Render(`) or qualified (`home.Render(`). Archived packages
(`ignore = true` in gnomod.toml) are skipped, since the toolchain skips them too.
"""
import re
import sys
import pathlib

IGNORE_RE = re.compile(r"(?m)^\s*ignore\s*=\s*true")
DECL_RE = re.compile(r"(?m)^func\s+Render\s*\(")
# \b keeps `printRender(` from counting as a call to Render.
CALL_RE = re.compile(r"\bRender\s*\(")


def strip_comments(src: str) -> str:
    """Blank out comments without touching string/rune literals.

    A naive `//`-to-EOL strip corrupts URLs inside string literals ("https://…"),
    which can hide a real call later on the same line. Track the lexical state.
    """
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            while i < n and src[i] != "\n":
                i += 1
        elif c == "/" and nxt == "*":
            i += 2
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                i += 1
            i += 2
        elif c in ('"', "'", "`"):
            quote = c
            out.append(c)
            i += 1
            while i < n:
                if quote != "`" and src[i] == "\\":
                    out.append(src[i : i + 2])
                    i += 2
                    continue
                out.append(src[i])
                if src[i] == quote:
                    i += 1
                    break
                if quote != "`" and src[i] == "\n":
                    break  # unterminated; bail rather than eat the file
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def is_test(p: pathlib.Path) -> bool:
    return p.name.endswith("_test.gno") or p.name.endswith("filetest.gno")


bad = []
for mod in sorted(pathlib.Path("r/moul").glob("**/gnomod.toml")):
    pkg = mod.parent
    if IGNORE_RE.search(mod.read_text()):
        continue

    prod = [p for p in sorted(pkg.glob("*.gno")) if not is_test(p)]
    if not any(DECL_RE.search(strip_comments(p.read_text())) for p in prod):
        continue

    tests = [p for p in sorted(pkg.glob("*.gno")) if is_test(p)]
    if not any(CALL_RE.search(strip_comments(p.read_text())) for p in tests):
        bad.append(str(pkg))

if bad:
    print("guard-render FAIL — realms declaring Render that no test ever calls:")
    for b in bad:
        print("  -", b)
    print("\nAdd an ExampleRender with a pinned `// Output:` block (preferred), or")
    print("assert with uassert.Equal when the output has consecutive blank lines.")
    sys.exit(1)
print("guard-render: every realm's Render is exercised by a test")
