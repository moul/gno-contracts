# `gno.land/r/moul/x/upgrade/wrap/v1`

Version 1 of the **wrapping versions** upgrade pattern (pattern A). Keeps its
own counter and adds [`v0`](../v0)'s on read. Both versions stay writable, so the
two paths report different totals and neither is authoritative.

`z_wrap_filetest.gno` walks that divergence step by step.

See [the pattern](../README.md) and [the exploration](../../README.md).
