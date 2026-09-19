# `gno.land/r/moul/x/upgrade/adminreg/facade/v0`

The **permanent facade** of pattern F. Implementations nominate themselves from
`init` (`Propose`); the owner promotes one by path string (`Accept`). Nothing
serves until both have happened.

Accepting takes a string on purpose: an interface value cannot travel in a
`maketx call` argument, so the original "admin hands the facade an object" shape
was not reachable from a wallet at all.

See [the pattern](../../README.md) and [the exploration](../../../README.md).
