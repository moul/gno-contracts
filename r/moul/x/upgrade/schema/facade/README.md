# `gno.land/r/moul/x/upgrade/schema/facade/v0`

The **permanent entry point** of pattern G. Holds one `Call(cur, verb, payload)`
signature forever and moves the API into data each handler declares: it parses the
schema, checks arity before dispatch, enumerates verbs without a transaction, and
refuses an upgrade whose schema would break an existing caller.

See [the pattern](../README.md) and [the exploration](../../README.md).
