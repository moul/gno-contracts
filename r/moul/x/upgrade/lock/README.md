# `lock` — retire the predecessor (pattern B)

[`wrap`](../wrap) leaves two writable versions and no single total. This one
fixes that with the smallest possible amount of coordination: one transaction.

```
lock/v0   writable until Retire(successor) freezes it, one-way
lock/v1   refuses every write until v0 names it; Get() = v0.Get() + own
```

**At most one version is writable at any height.** `v0.Retire` is owner-gated
and cannot be undone, because re-opening a version whose total a successor has
already folded in would double-count it. `v1` enforces the other side itself: it
aborts on every write until `v0.Successor()` names it, so there is no window in
which both accept writes, even if the deploy and the retirement are hours apart.

The handover is visible to callers rather than silent. `v0.Render` names its
successor once retired, and `v0.Inc` aborts with the path to move to, so a
caller pinned to the old path gets an error that tells it what to do.

Costs: one owner transaction, and a flag day. Everything pointed at `v0` breaks
at retirement rather than drifting quietly, which is the point.

Run it: `gno test ./r/moul/x/upgrade/lock/...` — `TestHandover` walks the whole
sequence, both refusals included.
