# Small grants

A public desk for small GNOT grants. Anyone files a request, for themselves or
for someone else, and the controllers vote on it in the open. The vote that
makes a majority pays the request in the same transaction, out of the realm's
own balance. Every request, ballot and payout stays on the page.

## Rules

- **Small only.** One request asks for at most 100 GNOT (`MaxGrant`). It is a
  constant: no call can raise it. Bigger grants belong in another system.
- **Funding is a plain send** to the realm address. Coins leave only as a
  voted grant; to return money, file a request paying it back.
- **A decision needs a majority of all current controllers**: 2 of 3, 3 of 4.
  The filer and payee of a request, and the subject of a removal, never vote
  on it, and their seat still counts. So on a small set no controller can
  remove another alone and then pay alone, and a set of two cannot remove one
  of its own.
- **Controllers change by the same majority** (`Propose`, then `Second`), so
  the set grows without a redeploy.
- **Pause stops new requests only**, except from the allowlist, which is a
  separate list from the controllers. Votes, withdrawals and payouts keep
  working. Any one controller may `Pause`, `Resume`, `Allow` and `Disallow`.

## Calls

```sh
# ask (anyone; the payee can be someone else)
gnokey maketx call -pkgpath <path> -func Request \
  -args g1payee... -args 25000000 -args 'Port a lib' -args 'what it is for' ...
# decide (controllers)
gnokey maketx call -pkgpath <path> -func Vote -args 1 -args true -args 'note' ...
# change the controllers (controllers)
gnokey maketx call -pkgpath <path> -func Propose -args g1... -args true -args 'why' ...
gnokey maketx call -pkgpath <path> -func Second -args 1 -args true -args '' ...
```

## The path

The published path is the `module` line of `gnomod.toml` and nowhere else: the
code reads its own path and address at init. The directory name here is not
the path.
