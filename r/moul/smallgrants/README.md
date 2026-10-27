# Small grants

> **This is a demo.** A working preview of the small-grants desk I plan to
> deploy under `gno.land/r/nt` or `gno.land/r/gnoland`, once approved.
> Requests, decisions and payouts here are real; only the address is temporary.

It lives under `gno.land/r/moul/smallgrants/v0` so that the decision to give it
a shared home is taken on something that runs. It has one role on purpose: who
decides grants and who administers the deciders is a choice for the real
deployment.

A public desk for small GNOT grants. Anyone files a request, for themselves or
for someone else, and the controllers decide on it in the open. The yes that
makes a majority pays the request in the same transaction, out of the realm's
own balance. Every request, ballot and payout stays on the page.

## Rules

- **Small only.** One request asks for at most 100 GNOT (`MaxGrant`), and one
  payee address receives at most that over any 30 days, counting what its open
  requests ask. A constant: no call can raise it. It bounds an address, not a
  person; the page is where a pattern across addresses shows. Bigger grants
  belong in another system.
- **Funding is a plain send** to the realm address. Coins leave only as a
  voted grant; to return money, file a request paying it back.
- **A decision needs a majority of all current controllers**: 2 of 3, 3 of 4.
  Only a yes pays or seats anyone; a refusal or a no can close a decision,
  never carry it.
- **One set decides each decision.** Seating or removing a controller voids
  every ballot on every pending request and motion, and the new set votes
  again. A removed key loses its say at once, everywhere. Voided ballots stay
  on the page, marked.
- **Parties do not vote, and their seat still counts.** For a removal that is
  a guarantee: a set of two cannot remove one of its own, a set of three needs
  both others. For a request it is a conflict-of-interest rule only: filer and
  payee are addresses the caller picks, so it does not stop a controller using
  another address. What holds a grant is the majority.
- **Three decisions, each with an optional public reason**: `Accept` pays in
  full, `AcceptPart` pays a part the controller names (never more than the
  request asked), `Refuse` pays nothing. A refusal without a reason shows as
  *no reason given*.
- **A part closes the request.** It pays the smallest amount a counted yes
  named, the one amount all of them agreed to; the payee files a new request
  for the rest, within its 30-day room.
- **Controllers change by the same majority** (`Propose`, then `Second`), and
  an added controller takes the seat only by calling `Join` from that address,
  which proves a key signs for it. Two to nine seats; the realm's own address
  can never sit.
- **Bounded queue.** At most 30 requests wait at once. The filer or the payee
  may `Withdraw`; anyone may `Close` a request or `CloseMotion` a motion that
  can no longer pass, or that has waited over 30 days.
- **Pause stops new requests only**, except from the allowlist, which is a
  separate list from the controllers. Decisions, withdrawals and payouts keep
  working. Any one controller may `Pause`, `Resume`, `Allow` and `Disallow`.

## Calls

```sh
# ask (anyone; the payee can be someone else)
gnokey maketx call -pkgpath <path> -func Request \
  -args g1payee... -args 25000000 -args 'Port a lib' -args 'what it is for' ...
# decide (controllers): in full, a part in ugnot, or refuse; the reason may be ''
gnokey maketx call -pkgpath <path> -func Accept -args 1 -args 'why' ...
gnokey maketx call -pkgpath <path> -func AcceptPart -args 1 -args 40000000 -args 'why' ...
gnokey maketx call -pkgpath <path> -func Refuse -args 1 -args '' ...
# change the controllers (controllers)
gnokey maketx call -pkgpath <path> -func Propose -args g1... -args true -args 'why' ...
gnokey maketx call -pkgpath <path> -func Second -args 1 -args true -args '' ...
# take a seat you were voted (the added address itself)
gnokey maketx call -pkgpath <path> -func Join -args 1 ...
# close what can no longer pass, or has waited 30 days (anyone)
gnokey maketx call -pkgpath <path> -func Close -args 1 ...
```

## The path

The published path is the `module` line of `gnomod.toml` and nowhere else: the
code reads its own path and address at init. The directory name here is not
the path.
