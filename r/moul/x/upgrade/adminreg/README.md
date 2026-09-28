# `adminreg` — propose and accept (pattern F)

[`selfreg`](../selfreg) lets a deploy take the realm over on the spot. This
splits that into two steps that different people can hold: an implementation
**nominates itself** from its own `init`, and the owner **accepts a path** in a
separate transaction. Nothing serves until both have happened.

```
adminreg/facade/v0   permanent; candidates tree + one accepted Impl
adminreg/impl/v0     proposes itself on init
adminreg/impl/v1     proposes itself on init
```

**The split is mechanical, not just governance.** The original 2024 shape had an
admin call `SetImpl(impl)`, handing the facade an interface value. A wallet
cannot put one in a `maketx call`: only strings and numbers travel, so that
shape is reachable only from `maketx run` or from another realm. Proposing from
`init` and accepting **by path string** makes both halves ordinary transactions.

This is the same two-phase shape gno.land itself uses when the chain parks a
`MsgAddPackage` until an approver enables it, and it is what
[`clockworkgr/gno-upgradeable`](https://github.com/clockworkgr/gno-upgradeable)
builds on. Accepting an unproposed path aborts; proposing from outside the
prefix aborts; a non-owner accepting a legitimate candidate aborts. All three
are asserted.

Upgrade and rollback are the same single call with a different path, since every
candidate stays in the tree once nominated. What rollback does not do is undo
anything a bad version wrote.

Run it: `gno test ./r/moul/x/upgrade/adminreg/...`
