# `gno.land/r/moul/demo/importdemo/v3`

A minimal realm that imports and composes packages from **another namespace** —
that is the whole point of the demo. It builds a small thread of posts and
renders it as Markdown.

```
/r/moul/demo/importdemo/v3   → the demo thread
```

Uses [`p/nt/avl/v0`](https://gno.land/p/nt/avl/v0) for ordered storage and
[`p/nt/ufmt/v0`](https://gno.land/p/nt/ufmt/v0) for formatting. Both are
published on the testnets we target, which is the difference from v2.

Stateless: `Render` rebuilds the thread on every call, so its output depends
only on the code.

### Why v3 exists

[`v2`](../v2) imported `gno.land/p/archive/dom`, which is published on **no**
chain we target (absent on both sapphire and pearl). It type-checked locally and
passed CI, but could never be deployed — `addpkg` failed with:

```
could not import gno.land/p/archive/dom (unknown import path "gno.land/p/archive/dom")
```

v2 is archived (`ignore = true`) rather than fixed in place or deleted, per the
repository's versioning policy. This version keeps the same idea on dependencies
that actually exist on chain.
