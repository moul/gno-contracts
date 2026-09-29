# Reviewing moul/gno-contracts

This repository is [gno.land](https://gno.land) contracts: pure packages under `p/moul/*`
and realms under `r/moul/*`, written in **gno**, which is Go-like and is not Go.

**329 of the 331 contracts here are live on mainnet, and a public package path is
immutable.** `AddPackage` refuses a path already occupied unless the live package is
private, so a defect that ships renders forever and the only fix is a new version at a new
path that every importer has to move to. That single fact is why review here is worth more
than review almost anywhere else, and it is the lens for everything below.

## The two files that decide what is right

| file | what it settles |
|---|---|
| [`EFFECTIVE_GNO.md`](../EFFECTIVE_GNO.md) | **what to write**: which container to store something in and what it costs, which package renders a table, who the caller is, money, and a "do not hand-roll this" index |
| [`AGENTS.md`](../AGENTS.md) | **how to ship it**: versioning, `private = true`, the CI guards, and every way gno differs from Go that has cost this repo a red build |

**A finding that contradicts one of those two is a finding about the document.** Say so,
and name the section, rather than quietly applying a different standard.

## What a review here is for

1. **Authority**, **value**, **permanence**, **determinism**, **cost**, in that order. The
   `**/*.gno` instructions spell each one out.
2. **Not style.** CI owns formatting, naming, README content, import order and the guards.
   A comment about any of those is noise on top of six checks that already ran.
3. **Not a summary of the change.** The author wrote the description.

## What a finding must contain

- the **file and line**
- **what happens**: a concrete sequence of calls with inputs, not a possibility
- **why it matters here**: the consequence on this chain, not in general
- **the fix**: the smallest change, or the package in `EFFECTIVE_GNO.md` that already does it

"This could be unsafe" is not a finding. **At most five findings**, most severe first; a
review that always finds something is a review nobody reads. If nothing is wrong, say so in
one line.

## What is already checked for free, so do not repeat it

`make guards` and `make audit-patterns` run on every pull request:

| check | what it already catches |
|---|---|
| `audit-patterns` | ten lexical audit-pattern rules from `gnolang/gno`'s own harness, ratcheted against a baseline |
| `guard-untrusted-render` | a realm that renders a caller's string and escapes nothing |
| `guard-tables` | a markdown table built by concatenating pipes |
| `guard-render`, `guard-examples` | a `Render` no test calls, an `Example` with no `// Output:` block |
| `guard-private`, `guard-readmes`, `guard-generated` | the `private` decision, empty READMEs, generated files in a PR |

Those are lexical and they miss what needs judgement. **That is your half**: deciding which
mechanical hit is real, and finding the defects with no lexical shape at all.
