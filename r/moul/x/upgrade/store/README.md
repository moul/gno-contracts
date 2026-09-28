# `store` — data realm, swappable logic (pattern C)

The separation the other patterns keep re-deriving: put the state in a realm
that has no business logic worth changing, and let exactly one logic realm write
to it at a time.

```
store/root/v0     holds the counter; grants write access to ONE path
store/logic/v0    no state at all; step = 1
store/logic/v1    no state at all; step = 1000
```

**Upgrading is one call**, `root.SetLive(newPath)`. The data does not move,
because it was never in the logic realm. There is nothing to migrate, no
downtime, and rolling back is the same call with the old path.

The write gate reads the caller's package path off the crossing frame
(`cur.Previous().PkgPath()`), never from an argument, so a logic realm cannot
claim a path it does not occupy. Reads stay open to everyone: a retired version
still reports the truth, it just cannot change it.

This is what `r/gov/dao` does with `memberstore`, and what
[`clockworkgr/gno-upgradeable`](https://github.com/clockworkgr/gno-upgradeable)
calls a dedicated state realm. The limit is that `root`'s own API is frozen
forever: if the *shape* of the data has to change, `root` cannot help you and
you are in [`lazy`](../lazy) territory.

Run it: `gno test ./r/moul/x/upgrade/store/...` — `TestSwapLogic` swaps the
live realm mid-test and checks both lockouts.
