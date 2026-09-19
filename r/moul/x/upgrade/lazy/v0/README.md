# `gno.land/r/moul/x/upgrade/lazy/v0`

Version 0 of the **lazy migration** pattern (pattern D). An ordinary record
store, written without any knowledge of a successor. `Size()` never shrinks:
migration copies forward, so this realm keeps paying for every record it ever
held.

See [the pattern](../README.md) and [the exploration](../../README.md).
