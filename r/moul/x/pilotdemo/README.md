# `gno.land/r/moul/x/pilotdemo/v0`

A power for a realm-driven account: a payout module installed into
[`r/moul/pilot`](../../pilot) after that account was already deployed. Demo of
[`p/moul/pilot`](../../../p/moul/pilot).

It shows both delegation modes in one realm, which is the point of the pair:

- `Pay` goes through the account's revocable purse. `Revoke` stops it on the next call even
  though this realm still holds the purse object.
- Under an identity grant it acts as `gno.land/r/moul/pilot/v0#payout` toward another realm,
  and spends the sub-treasury through a banker it mints and **keeps**. That is deliberate:
  it is what makes the test `TestIdentityGrantOutlivesRevoke` pass, and what an identity
  grant costs.

`InstallInto` takes the account handle as a value rather than importing one account, so a
module is not bound to a single instance. gno has no dynamic call, so a `gnokey maketx run`
script is what passes the handle; `MsgCall` cannot.
