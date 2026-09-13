#!/usr/bin/env python3
"""Print the GENERATED regions of a README.md, for the no-generated-files guard.

README.md is part generated, part hand-written prose. The guard used to reject
any PR touching the file at all, which also blocked fixing stale prose — the
regenerator never rewrites those paragraphs, so editing them is safe.

This extracts only what `gnocontracts readme` actually rewrites:

  * the contracts table, between its BEGIN/END markers
  * the body of the "## Dependency graph" section

The guard compares these between base and head: identical means the PR only
touched prose, and is allowed.

Usage: readme_regions.py <path-to-README.md>   (missing file => empty output)
"""
import sys

TABLE_BEGIN = "<!-- BEGIN CONTRACTS TABLE"
TABLE_END = "<!-- END CONTRACTS TABLE -->"
GRAPH_HEADING = "## Dependency graph"


def regions(content: str) -> str:
    out = []

    i = content.find(TABLE_BEGIN)
    j = content.find(TABLE_END)
    if i >= 0 and j > i:
        out.append(content[i:j + len(TABLE_END)])

    g = content.find(GRAPH_HEADING)
    if g >= 0:
        rest = content[g + len(GRAPH_HEADING):]
        k = rest.find("\n## ")
        end = len(content) if k < 0 else g + len(GRAPH_HEADING) + k + 1
        out.append(content[g:end])

    return "\n<<<REGION>>>\n".join(out)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: readme_regions.py <README.md>", file=sys.stderr)
        return 2
    try:
        with open(sys.argv[1], encoding="utf-8") as fh:
            content = fh.read()
    except FileNotFoundError:
        return 0  # no file on that side of the diff: nothing generated to compare
    sys.stdout.write(regions(content))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
