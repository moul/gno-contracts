# `wrap` — wrapping versions (pattern A)

The cheapest thing that can be called an upgrade: deploy `v1`, have it read `v0`
and add its own state on top. No transaction, no coordination, no migration.

```
wrap/v0   counter, writable forever
wrap/v1   counter of its own; Get() = v0.Get() + own
```

**Both versions stay writable.** Writing `v0` moves what `v1` reports; writing
`v1` does not move what `v0` reports. So the two paths answer differently and
neither is authoritative. Anything already pointed at `v0` keeps working and
keeps drifting, forever.

That is the whole trade. You get an upgrade with zero operational surface, and
you give up having a single answer. Use it when versions are genuinely
independent (a new fee tier, a second market) and callers pick one on purpose.
When they must agree, go to [`lock`](../lock).

Reading across the version boundary is a plain non-crossing call, so
`v1.Get()`, and therefore `v1.Render`, stay queryable without a transaction.

Run it: `gno test ./r/moul/x/upgrade/wrap/...` — the filetest in `v1` walks the
divergence step by step.
