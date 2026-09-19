# `lazy` — migrate on first touch (pattern D)

The only pattern here where the stored *shape* changes. `v1` declares a new
record type and converts each record from `v0` the first time somebody touches
it, paid for by whoever touched it. No migration transaction, no pause, no
bounded-loop gas problem.

```
lazy/v0   Record{Name string; Score int}
lazy/v1   Record{Name string; Score int64; Active bool}, converted on first Get
```

**On gno 0.9 this costs more than it used to.** Migrating writes, and writing
means crossing, so the read path is `Get(cur realm, key string)`: it is a
transaction, it costs gas, and it cannot be reached from `vm/qeval` or from
`Render`. `v1` therefore ships two halves:

- `Get(cur, key)` — migrates and stores. The real read path.
- `Peek(key)` — converts on the fly and stores nothing. Free, queryable, and it
  answers *as if* migrated for records nobody has touched yet.

They agree on value and disagree on state, and that window lasts as long as any
record stays untouched, which is to say possibly forever. A paged
owner-driven drain that closes it is the obvious next step and is not here yet.

**Migration copies, it does not move.** `lazy/v0.Size()` never shrinks: the old
realm keeps every record and keeps paying its storage deposit, on top of the new
one. Two copies of every migrated record, permanently.

Run it: `gno test ./r/moul/x/upgrade/lazy/...` — `TestLazyMigration` walks a
record across and checks both halves on either side of the move.
