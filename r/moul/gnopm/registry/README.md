# `gno.land/r/moul/gnopm/registry/v0`

An open, on-chain map from a deployed gno package path back to the source that
produced it: repository, commit, directory.

The domain model lives in
[`gno.land/p/moul/gnopm/v0`](../../../../p/moul/gnopm), which is also where the
reasoning is written down. This realm is the wiring: the routes, the authority
rule and the events.

## It cannot promise, and does not pretend to

Nothing here is verified and nothing here **can** be. A realm cannot clone a
repository, so it cannot check that the bytes at the claimed commit are the
bytes deployed at the claimed path. What it stores is testimony under a
signature: *this address says this package came from that source.*

That is still worth storing, for two reasons.

**It is testimony in the shape a verifier needs.** Path, repository, commit and
directory are precisely the four inputs to "hash the `addpkg` payload of that
directory and compare it with what the chain hands back", which
[gnopm](https://github.com/moul/gnopm) already does against a local tree
(`gnopm verify -deployed`). The realm does not answer the question; it makes the
question answerable by anything that can clone.

**The chain knows who signed.** A claim from the address that owns the package
path's namespace comes from the party that controls the path. That is not proof
the source matches, it is proof of who is speaking, and it is the strongest
signal available without a chain-level feature.

## Open, and tagged

Anyone may claim any path, including one they had nothing to do with. A claim
from an address that does not own the namespace is **not hidden**: it renders
under its own heading, below the owner's, and says so.

Suppressing it was the alternative and it is worse. A registry that only accepts
self-registrations is empty on day one, when almost nothing has been registered
by its own deployer, and an empty registry teaches nobody anything.

A claimant may always withdraw their own claim, and may never touch anyone
else's.

## Routes

| path | page |
| --- | --- |
| `/` | every claimed package path, paginated with `?page=N` |
| `/<package path>` | the claims about one package, owner first |
| `/help` | what this realm is and how to write to it |

A package path contains slashes, so it arrives at `Render` already split; the
routing is the rejoin.

## Writing

```sh
gnokey maketx call -pkgpath gno.land/r/moul/gnopm/registry/v0 \
  -func Register \
  -args "gno.land/p/moul/md/v1" \
  -args "https://github.com/moul/gno-contracts" \
  -args "<40 or 64 char lowercase hex commit>" \
  -args "p/moul/md" \
  -args "refs/tags/v1.0.0" \
  -gas-fee 1000000ugnot -gas-wanted 5000000 \
  -broadcast -chainid <chain> -remote <rpc> moul
```

`dir` is empty for a package at the repository root. `ref` is optional and is
never the thing verified: a ref moves, a commit does not. It is recorded so a
reader can tell a claim pinned to a released tag from one pinned to a commit on
nobody's branch, and so a verifier can report a commit since orphaned by a
force-push.

Calling `Register` again for the same path replaces your own claim and nobody
else's, which is how a claim moves to a new commit after a redeploy.
`Withdraw` takes it back.

## Reading, from another realm or an indexer

```go
registry.HasClaims(pkgPath)                          // has anyone said anything
repo, commit, dir, ok := registry.OwnerClaim(pkgPath) // the namespace holder's claim
registry.PackageCount()
registry.ClaimCount()
```

`OwnerClaim` is the only read that filters, and it filters on the one thing the
chain can prove. Ownership is recomputed on every call rather than stored,
because a name can be transferred.

Two events carry the same information to an indexer, which is how an explorer
follows the registry without polling: `SourceClaimed` (`pkgpath`, `claimant`,
`repo`, `commit`) and `SourceWithdrawn` (`pkgpath`, `claimant`).

## Why `private = true`

Standard for a new realm here: it can be redeployed at this path by its creator
instead of burning a `/v1`. The cost is real and worth stating, because this
realm holds data other people wrote: **a redeploy wipes every package-level
variable**, so every claim in it goes with it. Claims are cheap to re-make and
each one is a signed statement its author can reissue, which is what makes the
trade acceptable here and would not make it acceptable for a realm holding
balances.

## What is deliberately not here

- **No verification**, per the top of this file. The check that actually proves
  something needs to clone a repository and hash a tree, which is a service, not
  a realm. gnopm already holds the whole of that logic (`hashPayload` hashes
  exactly what `addpkg` would upload; `gnomodnorm` handles the fact that the
  chain **rewrites** `gnomod.toml` on publish, appending an `[addpkg]` table, so
  a naive byte comparison reports every package as differing forever).
- **No curation, no voting.** Whose claim to believe is a judgement that wants
  the deployer identity from chain history, which an explorer has and a realm
  does not.
- **No compare-and-swap on update.** `r/moul/forge` takes the expected previous
  object id when moving a ref, because two maintainers racing on a branch is a
  real lost-update. Here a claimant only ever overwrites their own claim, so
  there is nobody to race.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/gnopm/registry/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/gnopm/registry/v0/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
