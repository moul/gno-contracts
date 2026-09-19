# `gno.land/r/moul/x/upgrade/lazy/v1`

Version 1 of the **lazy migration** pattern (pattern D). Declares a new record
shape and converts each [`v0`](../v0) record on first touch.

Migrating writes, and writing means crossing, so `Get(cur, key)` is a
transaction and is invisible to `vm/qeval` and to `Render`. `Peek(key)` is the
free read-only half: same value, no migration.

See [the pattern](../README.md) and [the exploration](../../README.md).
