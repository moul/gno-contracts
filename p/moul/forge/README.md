# forge

The domain engine of an on-chain software forge: repos, roles, an append-only
reference log, issues, change requests and reviews. Pure gno, no chain imports,
no realm globals. The realm that wires it to gno.land is
[`gno.land/r/moul/forge/v0`](../../../../r/moul/forge/v0).

## What it stores, and what it refuses to store

It does not store code. Git objects stay in git, behind whatever mirror a repo
declares (an https remote, an IPFS CID, a peer). On gno.land a realm write locks
a storage deposit of 100ugnot per byte, so a 1 MB repository would cost about
100 GNOT to park on chain and more on every push. Anchoring is the only shape
that survives contact with real repositories.

What it does store is the part a forge is actually trusted for, and that git
alone does not authenticate:

1. **Which object a ref points at**, in what order it got there, and who said
   so: an append-only, hash-chained reference log.
2. **Who may move which ref**, and under what review policy.
3. **The social layer**: issues, change requests and reviews bound to addresses
   rather than to platform accounts.
4. **The merge decision**, recorded as one more entry in the same log.

## The reference log

Every ref move appends a `LogEntry`: ref name, old object, new object, actor,
block height, kind (`create`, `update`, `force`, `delete`, `merge`), an optional
note, and a `Digest` committing to the previous entry's digest. Publish
`LogHead()` anywhere off chain and the entire history of every ref becomes
falsifiable. `VerifyLog()` recomputes the chain; a client should run the same
computation over the values it read back, since a transparency log nobody
verifies is just a log.

Moves are compare-and-swap:

```go
r.SetRef(actor, height, "refs/heads/main", expectedOID, newOID, "ship it")
```

`expectedOID` is the tip the caller last saw, empty to create the ref. A stale
expectation returns `ErrStaleRef` instead of overwriting. That is git's
`--force-with-lease`, except the lease is held by consensus rather than by the
server you are pushing to. `ForceSetRef` skips the expectation, needs
`RoleMaintainer`, and is permanently recorded as `KindForce`: a force-push is
not forbidden here, it is made impossible to hide.

The chain has no objects, so it cannot check that a new tip descends from the
old one, and this package does not pretend otherwise. Ordering, attribution and
policy are on chain; ancestry is verified by a client that holds the repo. This
is the same split as gittuf's reference state log, with the log moved out of the
repository and into a place no maintainer can rewrite.

## Roles

`RoleNone < RoleReader < RoleWriter < RoleMaintainer < RoleAdmin < RoleOwner`,
totally ordered so every check is one comparison. Writers move refs, maintainers
force and merge, admins manage members and policy. The last owner cannot be
demoted. Anyone can open an issue or a change request without a role: the spam
gate is that the author pays gas and locks the deposit for their own bytes.

## Reviews that cannot go stale unnoticed

A `Review` names the object id it reviewed, not the change. Push a new head and
every earlier approval stops counting, because it approved something that is no
longer what would be merged. Nothing has to remember to dismiss it, and no
setting can turn the behaviour off. Only a writer's approval counts toward
`RequiredApprovals`; anyone else's review is signal, not authority. A
`request-changes` verdict from a writer blocks the merge while it stands.

`MergeChange` is a compare-and-swap on the target ref plus a policy check, and
it writes a `KindMerge` entry naming the change it came from.

## API shape

Errors, never panics: this package is pure, so a realm turns an error into an
abort (the only way to revert state in gno) and a test asserts on the value.
Every collection is an `avl.Tree`, so every listing is ordered and paginatable,
and no iteration walks unbounded state. The caller supplies the actor address
and the block height, which is what makes the whole engine unit-testable with no
chain at all.

```go
f := forge.New()
r, _ := f.CreateRepo(alice, height, "moul/forge", "an on-chain forge", "")
r.SetMember(alice, bob, forge.RoleMaintainer)
r.SetRef(alice, height, "refs/heads/main", "", oid, "initial import")
c, _ := r.OpenChange(carol, height, "title", "body", "", "refs/heads/feat", head, "refs/heads/main")
r.ReviewChange(bob, height, c.ID, forge.VerdictApprove, "lgtm")
r.MergeChange(bob, height, c.ID, oid, merged, "merge change 0")
```

## Limits

Every stored string is bounded (see the `Max*` constants) because an unbounded
field is an unbounded deposit. Ref names are a `refs/`-rooted subset of
git-check-ref-format; object ids are 40 or 64 lowercase hex characters; repo ids
are `<namespace>/<name>`, where the name is a lowercase slug and the namespace is
either a slug (a claimed user name) or a bech32 address. The two shapes cannot
collide: an address is 40 characters and a slug caps at 39.

This package validates the **shape** of a namespace and nothing else. Whether a
caller may claim one is an ownership question that needs a chain, so it lives in
the realm: a name must be held in `r/sys/users`, an address must be the caller's
own.

One economic rule shows up in the API: deleting is privileged. On gno.land the
storage-deposit refund goes to whoever frees the bytes, not to whoever paid for
them, so an open delete path pays for vandalism. `DeleteRef` needs
`RoleMaintainer`, and issues, comments and reviews have no delete at all.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/p/moul/forge/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/p/moul/forge/v0/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
