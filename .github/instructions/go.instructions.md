---
applyTo: "tools/**/*.go"
---

# Reviewing the repository tooling

`tools/` is the only Go module here. The repository root holds `vendor/gno.land`, and Go
treats a `vendor/` in a module root as Go vendoring, so a root module would refuse to build
and `go mod vendor` would delete the gno dependencies. **There is no Go module at the root
and there cannot be one.** Anything placed outside `tools/` is built and tested by nothing.

- **`tools/go.mod` has exactly one external dependency, `moul.io/gnopm`**, and that is
  deliberate: the `gnomod.lock` format has one owner, so `tools/gnocontracts` imports
  `gnopm/pkg/gnomodlock` rather than reimplementing it. A **contract companion**
  (`tools/gnohome`, `tools/gnoblog`) is standard library only, reading the chain over plain
  JSON-RPC `abci_query`. A new external dependency is the finding; the existing one is not.
- **A tool must never hold key material, and must always keep a print path.** Signing is
  allowed and two companions do it: `gnohome tx -run` and `gnoblog` shell out to `gnokey`
  with the terminal attached, so gnokey holds the key and prompts for a passphrase the
  process never sees, and both write the document and script first so a half-finished run is
  reproducible by hand. **The finding is a process that could sign without being asked, that
  reads a passphrase, or that removes the print path**, not the act of signing.
- **A Makefile target is one line**, so a flag belongs on the tool and not in a recipe.
- **`tools/auditpattern/run.go` is a byte-for-byte MIRROR** of `gnolang/gno`'s
  `misc/audit-pattern-harness/internal/auditpattern/run.go`. **Never hand-edit it.** Re-mirror
  and update the three constants at its top; `audit-patterns -drift <gnoroot>` re-hashes the
  original and is what keeps the copy honest.
- **Anything duplicated from a contract carries a comment naming the `.gno` file it mirrors**,
  and a test pinning the two to the same behaviour.
- **Table-driven tests, no network, transport separated from parsing.** The decoding lives in
  functions a test can call with a literal, so tests never dial anything. Do not expect one
  string-returning chain function: `gnohome` and `gnoblog` both have a `fetchManifest`
  returning a map and an error, plus separate `qeval` and `abciQuery` helpers.
- **A guard with a baseline ratchets in both directions.** A count that goes down must fail
  too, until the baseline is re-recorded, or a fix can be quietly undone.

## Defects review has already found here, none of which a test caught

Each was a real finding on a tooling pull request. Look for the shape, not the file.

- **`gh api --paginate` emits one JSON array per page**, so `jq '.[0]'` or `$x[0]` reads page
  one only. Past 100 items the rest is dropped and the output still looks complete (#296).
  Use `--slurp` or `jq -s 'add'`.
- **`git diff --numstat` prints a rename as `{old => new}` brace syntax**, so a path suffix
  check (`.go`, `.gno`) on that field silently skips every renamed file (#310). Use
  `--no-renames` or `-z`.
- **Text from a pull request, review or issue reposted as markdown** has to be neutralised:
  a `[x](url)` link, a bare `https://` autolink and an `@mention` each become live in the
  comment the tool posts (#296, #295).
- **An API error read as "nothing found".** A failed fetch that falls through to the empty
  case reposts what was already posted, or logs a review that never ran as clean (#295,
  #304: a quota refusal is a review body, not an empty review).
- **A regexp over free text not anchored to the line it means** (`Review effort:**`
  matched in prose, #313). Anchor to `^` and the exact metadata shape.
- **A constant declared and never read**, so the tool prints the old figure while the PR
  claims the new one (#310's `budgetUSD`).
