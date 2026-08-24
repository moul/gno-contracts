#!/usr/bin/env python3
"""Fail if any gno Example* test lacks an `// Output:` block.

gno SILENTLY SKIPS an example function that has no `// Output:` (or
`// Unordered output:`) directive — so such an "ExampleRender" is a false-green
test that asserts nothing. This guard makes that impossible: every Example* must
pin its output.
"""
import re
import sys
import pathlib

bad = []
for base in ("p/moul", "r/moul"):
    for f in pathlib.Path(base).glob("**/*_test.gno"):
        src = f.read_text()
        # Only top-level func decls (column 0) — avoids matches inside comments
        # (e.g. "// switch to func Example() {}") or strings.
        for m in re.finditer(r"(?m)^func\s+(Example\w*)\s*\(\s*\)\s*\{", src):
            name = m.group(1)
            # walk to the matching closing brace
            depth, j = 1, m.end()
            while j < len(src) and depth:
                depth += (src[j] == "{") - (src[j] == "}")
                j += 1
            body = src[m.end():j]
            if not re.search(r"//\s*(Unordered output|Output)\s*:", body):
                bad.append(f"{f}:{name}")

if bad:
    print("guard-examples FAIL — Example* tests with NO `// Output:` (gno skips them silently → false green):")
    for b in bad:
        print("  -", b)
    sys.exit(1)
print("guard-examples: every Example* test pins an // Output: block")
