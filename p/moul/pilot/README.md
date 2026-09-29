# `gno.land/p/moul/pilot/v0`

A realm-driven account: **one realm holds the funds and the identity, a key pilots it, and
its powers arrive afterwards as separate realms it never imports.** The gno answer to a
Gnosis Safe with modules.

Live instance: [`r/moul/pilot`](../../../r/moul/pilot). A power:
[`r/moul/x/pilotdemo`](../../../r/moul/x/pilotdemo).

## Why it is not just a multisig

gno has **no dynamic call**: a realm cannot invoke an arbitrary package path with
runtime-built arguments. So an account can never execute arbitrary calldata the way a Safe
does. Every outbound action has to be Go code in some realm.

The inversion that makes it work: the account is deployed once and stores `Module` values
handed to it by realms that did not exist at the time. The power is the calldata, published
as readable source, and installing one costs no redeploy of the account.

## The two grants, and the only difference that matters

| | `GrantPurse` | `GrantIdentity` |
|---|---|---|
| spends | the main treasury, metered | its own sub-treasury `account#subpath` |
| can act as the account toward other realms | no | yes |
| `Revoke` takes it back | **yes, immediately** | **no, never** |

A `Purse` is a type this package declares, so every call on one re-enters this code and
re-reads the live roster and budget. A module that stashed a purse and calls it a year later
still goes through the check.

A sub-identity token is the opposite. The token itself cannot be persisted, but
`banker.NewBanker` authorizes at construction and re-checks nothing ever again, so a module
can mint one from the lent token and keep it. `Revoke` shuts the account's door and does not
reach that banker. The blast radius is exactly what the sub-address was funded with, and it
is permanent. Grant an identity only to code you have read, and note that you can read it:
module source is on chain before you approve it.

## Shape

```go
// once, from the account realm
acct := pilot.New(0, cur)

// the owner, through the account realm's crossing functions
acct.Approve(0, cur, "gno.land/r/you/somepower/v0", "power", pilot.GrantPurse, 1_000)
acct.Fund(0, cur, path, 500)
acct.SetBudget(0, cur, path, 2_000)
acct.Revoke(0, cur, path)
acct.Exec(0, cur, path, args)

// the module realm, with its own cur: the account reads the path from the
// runtime and never from an argument
h := account.Handle()
h.Register(0, cur, self)
purse := h.PurseFor(0, cur)
```

## Both realms in the pair must be public

A module's object is persisted in the account's roster, and a value of a type defined in a
private realm cannot be persisted by anyone else. A private account realm cannot be imported
at all, and a redeploy would wipe the owner, the roster and every budget while leaving the
coins at the address. `private = true` is wrong for both halves, and each `gnomod.toml` says
so.
