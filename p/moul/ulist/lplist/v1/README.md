# `gno.land/p/moul/ulist/lplist/v1`

`LayeredProxyList` — a layered proxy over [`ulist`](../../v1) enabling **lazy,
append-only schema migration**: it wraps a source list with a target list and
transforms source entries only when accessed (source stays immutable), and layers
can be chained for multi-step migrations. Nested under `ulist` in the monorepo; it
was missed on the original `ulist` import.
