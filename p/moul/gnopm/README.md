# `gno.land/p/moul/gnopm/v0`

The domain model of a **source registry** for gno packages: a map from a
deployed package path back to the repository, commit and directory that produced
it.

The realm half is
[`gno.land/r/moul/gnopm/registry/v0`](../../../r/moul/gnopm/registry). This
package is pure: no chain imports, no realm state, and the one piece of chain
knowledge it needs (who holds a namespace) arrives as a function parameter.

## Why this has to exist at all

A Go import path *is* a repository URL, so pkg.go.dev needs no registry. A gno
import path is a chain address, so nothing anywhere says which source produced
the bytes running at `gno.land/p/nt/tinyavl/v0`. gno gave up that link
deliberately, and this is the part that has to be rebuilt by hand.

## What it can and cannot promise

It cannot promise anything, and the whole design is built around saying so
rather than around hiding it. Two claims look alike and are not the same:

| claim | provable |
|---|---|
| this package came from that repository | **no.** Not here and not anywhere: anyone may deploy any bytes and claim any repository |
| the deployed bytes equal the `addpkg` payload of that directory at that commit | **yes**, by hashing both sides. Off chain, by anything that can clone |
| the claimant owns the path's namespace | **yes**, from chain data, recomputed on every read |

So a `Claim` is testimony under a signature, and it is stored in exactly the
shape the second row needs: path, repository, commit and directory are the four
inputs to "hash the payload of that directory and compare it with what the chain
hands back". This package does not answer the question. It makes the question
answerable by something that can clone, which
[gnopm](https://github.com/moul/gnopm) already does against a local tree
(`gnopm verify -deployed`).

A mismatch, when a verifier does find one, is **not** evidence of malice. The
likeliest cause by far is a repository that moved on after a deploy, which is
the normal state of most repositories most of the time.

## Open, and tagged

Anyone may claim any path, including one they had nothing to do with.
`Claim.OwnedBy` reports whether a claim comes from the party that controls the
path, so the two can be told apart at render time.

Gating registration on namespace ownership was the alternative and it cannot
bootstrap: on day one almost nothing has been registered by its own deployer, so
the gated registry is empty and teaches nobody anything. Open-and-labelled keeps
the map fillable and moves the defence to the renderer, which is why
`OwnedBy` exists and why the realm ranks on it rather than hiding anything.

`OwnedBy` takes the name resolver as a parameter and the answer is never stored:
a name can be transferred, and a stored answer would rot into exactly the kind of
stale claim this package exists to distinguish from a live one.

## API

```go
r := gnopm.New()

// A claimant states where a package came from. Calling it again replaces that
// claimant's own claim and nobody else's.
c, err := r.Register(claimant, height, pkgPath, repo, commit, dir, ref)
err = r.Withdraw(claimant, pkgPath)          // your own claim, never anyone else's

p := r.Package(pkgPath)                      // every claim about one path, or nil
p.Claim(claimant)                            // one of them
p.IterateClaims(func(c *gnopm.Claim) bool { ... })

c.OwnedBy(resolve)                           // does this come from the namespace holder
c.SourceURL()                                // a browsable link to the claimed source
```

`Height` dates the claim and `UpdatedAt` dates the last edit. They are separate
so a reader can tell a claim that has been kept current from one made once at
deploy time and abandoned.

## Validation is an allowlist, on purpose

Every stored field is charset-validated at write time: `ValidPkgPath`,
`ValidRepo`, `ValidCommit`, `ValidDir`, `ValidRef`. Each is an allowlist, so a
stored field cannot hold a backtick, a pipe, a bracket, an ASCII control
character or a bidi override.

That is not belt-and-braces, it is the escaping strategy. One claim is rendered
in several places (a listing row, a table cell, an inline-code span, a link
title) and a consumer that forgets to escape at any one of them has a hole.
A field that can only hold safe bytes needs no escaping anywhere.

Two consequences worth knowing before they surprise you:

- **`ValidRepo` accepts `https://` and nothing else.** Not a taste judgement
  about git transports: the set of URL schemes that are safe to hand a browser
  is exactly one, and `javascript:` and `data:` are the attack. A host with a
  port is also refused, because the userinfo check (`https://github.com@evil.example/x`
  fetches from `evil.example` while reading as GitHub) needs the host to contain
  no `@` or `:`.
- **`ValidRef` is narrower than git's own rule.** git rejects a handful of
  metacharacters and permits the rest, which would leave a ref free to carry a
  pipe or a backtick and undo the allowlist for every other field. What stays
  expressible is every ref anyone actually has.

## What is deliberately not here

- **No verification.** A realm cannot clone a repository. See the realm README
  for where that half is meant to live.
- **No network of trust, no voting, no curation.** Whose claim to believe is a
  judgement, and the place to make it is a renderer that can see who deployed
  the package, not a data structure.
- **No version resolution.** `Version` reads a trailing `vN` and that is all.
  An unversioned path is legal and is not an error: gnoweb serves
  `gno.land/u/<name>` by calling the realm at exactly `/r/<name>/home`, so that
  one path can never carry a version.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/p/moul/gnopm/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/p/moul/gnopm/v0/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
