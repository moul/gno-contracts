# `gno.land/r/moul/pilot/v0`

moul's realm-driven account. It holds the funds and the identity; moul's key pilots it; its
powers arrive afterwards as separate realms this one never imports.

All behaviour is in [`p/moul/pilot`](../../../p/moul/pilot), which explains the two grants
and why `Revoke` takes back a purse but never an identity. This realm is the instance: a
`*pilot.Pilot`, one-line crossing re-exports forwarding `cur`, and `Render`.

A power to try it with: [`r/moul/x/pilotdemo`](../x/pilotdemo).

**`Claim` is pinned to `g1manfred47kzduec920z88wfr64ylksmdcedlf5` in the source.** A deploy
lands in one block and the claim is a second transaction, so taking the owner from whoever
calls first is a race anyone on chain can win, and this path can never be redeployed to undo
it.

```sh
# once, and only this address can
gnokey maketx call -pkgpath gno.land/r/moul/pilot/v0 -func Claim ... moul

# authorise a path that does not have to exist yet
gnokey maketx call -pkgpath gno.land/r/moul/pilot/v0 -func Approve \
  -args gno.land/r/moul/x/pilotdemo/v0 -args payout -args false -args 1000 ... moul
```

**Public on purpose.** A module realm imports this one and persists objects it owns, both of
which a private realm refuses, and a redeploy would wipe the owner, the roster and every
budget while leaving the coins at the treasury address.
