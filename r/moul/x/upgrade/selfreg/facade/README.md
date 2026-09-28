# `gno.land/r/moul/x/upgrade/selfreg/facade/v0`

The **permanent facade** of pattern E. Holds an `Impl` interface value and
forwards to it. Implementations register themselves from their own `init`, gated
on an explicit path prefix (`nestedpkg` does not fit version-last paths).

See [the pattern](../../README.md) and [the exploration](../../../README.md).
