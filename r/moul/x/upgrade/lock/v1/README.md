# `gno.land/r/moul/x/upgrade/lock/v1`

Version 1 of the **retire the predecessor** upgrade pattern (pattern B).
Refuses every write until [`v0`](../v0) has been retired onto it, then folds
v0's frozen total into its own. At most one version is writable at any height,
so there is a single authoritative answer.

See [the pattern](../README.md) and [the exploration](../../README.md).
