#!/usr/bin/env python3
"""Fail if any package ships a README that documents nothing.

A README whose whole content is `_TODO: describe this package._` plus the
generated footer is worse than no README: the package looks documented, so
nobody writes the real thing, and a reader pays a click to learn that the author
had nothing to say. 28 packages shipped in exactly that state because
`make readmes` used to seed a TODO stub for every package it could not describe.

The rule is therefore NOT "every package has a README". It is:

    a README that exists must say something true and useful about the package.

A missing README is legal and is only reported (`--list` prints them). If you
cannot write a good one, write a minimal accurate one (a single sentence that
says what the package does is enough, and several packages here are exactly
that), or delete the file. Do not leave a placeholder.

Checks, over the hand-authored region only (everything ABOVE the generated
GNOCONTRACTS footer marker):

  1. no placeholder text (TODO / TBD / FIXME / WIP / "coming soon" as the body);
  2. the region is more than just the `# pkgpath` title, i.e. the README is not
     pure boilerplate;
  3. what is left is at least MIN_BODY characters.

Archived packages (`ignore = true` in gnomod.toml) are skipped, as elsewhere.
"""
import re
import sys
import pathlib

FOOTER = "<!-- BEGIN GNOCONTRACTS FOOTER"
IGNORE_RE = re.compile(r"(?m)^\s*ignore\s*=\s*true")
TITLE_RE = re.compile(r"(?m)\A#\s+.*$")

# A body this short cannot carry a sentence. The shortest legitimate README in
# the repo is "Build Markdown tables." (22 characters), so 20 is the floor.
MIN_BODY = 20

PLACEHOLDER_RE = re.compile(
    r"(?im)^\s*[_*>\s-]*"                       # markdown emphasis / quote / bullet
    r"(todo|tbd|fixme|xxx|wip|coming soon|to be (written|documented)|"
    r"no description|describe this package)"
    r"\b.*$"
)


def body_of(text: str) -> str:
    """The hand-authored region: above the footer, title line removed."""
    i = text.find(FOOTER)
    region = text[:i] if i >= 0 else text
    return TITLE_RE.sub("", region.strip(), count=1).strip()


def main() -> int:
    list_missing = "--list" in sys.argv
    bad, missing = [], []

    for mod in sorted(pathlib.Path(".").glob("[pr]/moul/**/gnomod.toml")):
        pkg = mod.parent
        if IGNORE_RE.search(mod.read_text()):
            continue

        readme = pkg / "README.md"
        if not readme.exists():
            missing.append(str(pkg))
            continue

        body = body_of(readme.read_text())
        if not body:
            bad.append((str(pkg), "nothing above the generated footer but the title"))
            continue
        m = PLACEHOLDER_RE.search(body)
        if m:
            bad.append((str(pkg), f"placeholder text: {m.group(0).strip()!r}"))
            continue
        if len(body) < MIN_BODY:
            bad.append((str(pkg), f"body is {len(body)} characters, under the {MIN_BODY} minimum"))

    if list_missing and missing:
        print(f"guard-readmes: {len(missing)} package(s) with no README (allowed, not a failure):")
        for p in missing:
            print("  -", p)
        print()

    if bad:
        print("guard-readmes FAIL — README(s) that document nothing:")
        for p, why in bad:
            print(f"  - {p}/README.md: {why}")
        print()
        print("Write what the package actually does (one accurate sentence is enough),")
        print("or `git rm` the README. A placeholder is not an option: it makes the")
        print("package look documented and nobody ever comes back to it.")
        return 1

    total = len(list(pathlib.Path(".").glob("[pr]/moul/**/gnomod.toml")))
    print(
        f"guard-readmes: every README says something "
        f"({total - len(missing)} documented, {len(missing)} package(s) with none)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
