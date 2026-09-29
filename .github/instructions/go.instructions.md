---
applyTo: "tools/**/*.go"
---

# Reviewing the repository tooling

`tools/` is the only Go module here. The repository root holds `vendor/gno.land`, and Go
treats a `vendor/` in a module root as Go vendoring, so a root module would refuse to build
and `go mod vendor` would delete the gno dependencies. **There is no Go module at the root
and there cannot be one.** Anything placed outside `tools/` is built and tested by nothing.

- **Standard library only.** No third module, no cgo. Chain reads go over plain JSON-RPC.
- **Print transactions, never sign them.** A tool here holds no key and broadcasts nothing.
- **A Makefile target is one line**, so a flag belongs on the tool and not in a recipe.
- **`tools/auditpattern/run.go` is a byte-for-byte MIRROR** of `gnolang/gno`'s
  `misc/audit-pattern-harness/internal/auditpattern/run.go`. **Never hand-edit it.** Re-mirror
  and update the three constants at its top; `audit-patterns -drift <gnoroot>` re-hashes the
  original and is what keeps the copy honest.
- **Anything duplicated from a contract carries a comment naming the `.gno` file it mirrors**,
  and a test pinning the two to the same behaviour.
- **Table-driven tests, no network.** The chain-facing code is one function returning a
  string; test the parsing, not the transport.
- **A guard with a baseline ratchets in both directions.** A count that goes down must fail
  too, until the baseline is re-recorded, or a fix can be quietly undone.
