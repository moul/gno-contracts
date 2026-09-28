# `gno.land/r/moul/x/moultest/v0`

**A native coin called `moultest`, and a faucet with four ceilings on it.**
Not a GRC20: the chain's own bank holds it, exactly as it holds GNOT.

```
/gno.land/r/moul/x/moultest/v0:moultest
```

That string is the whole coin. There is no name, no symbol, no decimals field, no
ledger in this realm and no entry in any registry, because a native denom has
none of those things. 1000 moultest is a thousand moultest.

## Help yourself

```
gnokey maketx call -pkgpath gno.land/r/moul/x/moultest/v0 -func Claim ...
```

10,000 per claim, to the caller and never to an address the caller names, once
every 100 blocks, 100,000 per address for life, 1,000,000 ever. Burning gives
none of it back: issuance is counted monotonically, or claim-burn-claim would be
an unlimited faucet. The supply ceiling is there so the experiment ends, not so
the faucet scales.

## What the coin can do that a GRC20 cannot

Moving it needs nothing from this realm. It is a bank message, so any wallet
sends it with no realm call, no `Approve`, no allowance outliving the transfer:

```
gnokey maketx send -to <address> -send 2500/gno.land/r/moul/x/moultest/v0:moultest ...
```

It can also ride a call. The `-send` envelope of a transaction carries coins into
the realm being called, before a line of its code runs, which is what `Tip` uses:

```
gnokey maketx call -pkgpath gno.land/r/moul/x/moultest/v0 -func Tip \
  -args <address> -args "nice work" \
  -send 1000/gno.land/r/moul/x/moultest/v0:moultest ...
```

`Tip` forwards that envelope to the recipient and writes the note on a public
board. It spends through a `BankerTypeOriginSend` banker, whose entire authority
*is* the envelope: it cannot touch the realm's own balance, and a test pins
that by leaving 5,000 moultest at the realm address and checking that exactly
the 250 that arrived leaves again.

That banker type is only available to a call whose entry frame is the realm
named by the message, so `Tip` needs `maketx call` and does not work under
`maketx run`.

## What it costs, which is the more interesting half

A GRC20's mint and burn sit behind a ledger this realm chooses to guard. A
native coin's sit behind a banker, and `banker.RemoveCoin` takes an **arbitrary
address**. Nothing on the chain stops an issuing realm from deleting anybody's
balance at any time.

This realm does not expose that. `Burn` reads the caller from the call frame and
takes no address parameter, so it can only destroy the caller's own coins. But
"does not expose it" is the entire protection, and it lasts exactly as long as
the code deployed at this path. Worth knowing before treating any realm-issued
native coin as something you own.

## Redeploys

`private = true`, so this path can be redeployed with corrected code instead of
being abandoned for a `/v1`. The coins survive that (they are bank state, held at
their owners' addresses, and the denom embeds the package path, which does not
move) and everything on the render page does not: claim history, caps consumed
and the tip board all return to their init values, handing every account a fresh
lifetime allowance. Acceptable for a coin that is worthless by construction, and
not acceptable for one that is not.
