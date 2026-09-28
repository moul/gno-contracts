# `gno.land/r/moul/x/upgrade/lock/v0`

Version 0 of the **retire the predecessor** upgrade pattern (pattern B).
Writable until the owner calls `Retire(successor)`, which is one-way: from then
on it is a read-only archive that names where callers should go.

See [the pattern](../README.md) and [the exploration](../../README.md).
