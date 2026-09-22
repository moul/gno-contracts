# amm: a minimal constant-product AMM, in one file

A whole automated market maker for GRC20 pairs in a single `.gno` file: many
pools in one realm, `x*y=k` with a 30 bps fee that stays with the liquidity
providers, and nothing else.

It exists to be **read**. Uniswap V2 is the reference every on-chain AMM is
measured against, and most of its moving parts are consequences of one early
decision rather than of the market-making itself. This realm re-derives the
same product after making that decision differently, and the result is short
enough to audit in a sitting.

Design study, prior-art survey and the full security argument:
[moul/gno-contracts#135](https://github.com/moul/gno-contracts/issues/135).

## API

```go
// writes (crossing; the caller must Approve this realm first)
AddLiquidity(cur realm, keyA, keyB string, maxA, maxB int64) int64          // -> shares minted
RemoveLiquidity(cur realm, keyA, keyB string, shares int64) (int64, int64)  // -> amounts returned
Swap(cur realm, keyIn, keyOut string, amountIn, minOut int64) int64         // -> amount out

// reads
AmountOut(amountIn, reserveIn, reserveOut int64) int64   // pure pricing, quotable off-chain
Quote(keyIn, keyOut string, amountIn int64) int64        // against live reserves
Reserves(keyA, keyB string) (int64, int64)
SharesOf(keyA, keyB string, owner address) int64
TotalShares(keyA, keyB string) int64
PoolCount() int
Render(path string) string
```

Tokens are named by their [`r/nt/grc20reg`](https://gno.land/r/nt/grc20reg/v0)
key (`<realm path>.<SYMBOL>`), because `maketx call` cannot pass a
`*grc20.Token`. The pair order never matters: `(X,Y)` and `(Y,X)` are the same
pool, and returned amounts always follow the order you passed.

There is no `CreatePool`. A pool starts existing when someone deposits into it.

## Using it

Both tokens must be approved for this realm's address first, on the token's own
realm:

```sh
# 1. let the AMM take your tokens
gnokey maketx call -pkgpath gno.land/r/<ns>/<tokenA> -func Approve \
  -args g1<amm-realm-address> -args 1000000 ...

# 2. open (or top up) the pool
gnokey maketx call -pkgpath gno.land/r/moul/x/amm/v0 -func AddLiquidity \
  -args "gno.land/r/<ns>/<tokenA>.AAA" -args "gno.land/r/<ns>/<tokenB>.BBB" \
  -args 1000000 -args 4000000 ...

# 3. swap, with a real slippage bound
gnokey maketx call -pkgpath gno.land/r/moul/x/amm/v0 -func Swap \
  -args "gno.land/r/<ns>/<tokenA>.AAA" -args "gno.land/r/<ns>/<tokenB>.BBB" \
  -args 100000 -args 360000 ...

# 4. take your liquidity back
gnokey maketx call -pkgpath gno.land/r/moul/x/amm/v0 -func RemoveLiquidity \
  -args "gno.land/r/<ns>/<tokenA>.AAA" -args "gno.land/r/<ns>/<tokenB>.BBB" \
  -args 500000 ...
```

Worked example, the one the tests pin:

```
seed A=1 000 000 B=4 000 000        -> 1 000 000 shares
swap 100 000 A                      -> 362 644 B out
reserves A=1 100 000 B=3 637 356    k grows by the fee, 4.0000e12 -> 4.0011e12
burn 500 000 shares                 -> 550 000 A + 1 818 678 B
```

## Three decisions worth knowing about

**Reserves are stored, never read from `BalanceOf`.** This is the one that pays
for itself. Uniswap V2 infers the swap input from `balanceOf(this) - reserve`,
which is why it needs `MINIMUM_LIQUIDITY`, `skim` and `sync`, and why the
first-depositor share-inflation attack exists at all. Here a direct token
transfer to the realm address moves no reserve, no price and no share value, so
none of that machinery is needed. The price: **tokens sent directly to this
realm are permanently stuck.** There is no `skim`, deliberately, because a
`skim` would hand the lever back.

**The first deposit mints `shares = amountA`, with no `sqrt`.** The geometric
mean is cosmetic; every later operation uses only ratios of shares to reserves.
Dropping it removes an integer square root over a 128-bit product. Later
deposits mint `min(A-side, B-side)` with floor division on both, so an
off-ratio deposit is always rounded against the depositor and never dilutes the
existing providers.

**All arithmetic is `int64`, so pricing runs through a 128-bit `mulDiv`.** There
is no 256-bit type in reach, and `amountIn * 997 * reserveOut` leaves `int64`
almost immediately. `math/bits` supplies the wide multiply and divide; the
remaining plain-`int64` step, `reserveIn*1000 + amountIn*997`, is made safe by a
single rule enforced on both deposits and swaps:

> every reserve, and every post-swap reserve, stays at or below
> `maxReserve = MaxInt64/1000 = 9 223 372 036 854 775`

**Consequence: this AMM is unusable with 18-decimal tokens.** Max whole tokens
per reserve, by token decimals:

| decimals | 0 | 6 | 8 | 9 | 12 | 18 |
|---|---|---|---|---|---|---|
| max whole tokens per reserve | 9.2e15 | 9 223 372 036 | 92 233 720 | 9 223 372 | 9 223 | **0** |

Six to nine decimals is the practical band. That is `int64` GRC20 meeting a
1000x fee denominator, not a quirk of this contract.

## Warnings

- **Not an oracle.** The reserve ratio is a spot price any trader can move
  inside one transaction. Nothing should price off this realm.
- **`minOut` is your only slippage protection**, and it is mandatory for a
  reason. Passing `0` means accepting any price at all.
- **A pool is only as honest as its two tokens.** A token realm can mint to
  itself at will; that is a property of GRC20, not something an AMM can check.
  The blast radius of a bad token is exactly the pools that contain it.
- **Not audited.** This is a reference implementation, not a venue.

## Deliberately absent

TWAP or any oracle surface, flash swaps, multi-hop routing, LP shares as a
transferable GRC20, a native GNOT leg (it would need
`cur.Previous().IsUserCall()`, which makes the realm uncallable by other
contracts), protocol fees, governance, and `skim`/`sync`.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/x/amm/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/x/amm/v0/deps.png)

> 🧪 **Highly experimental — potentially vibe-coded.** Not audited; may break, change, or be removed at any time. Do not use with anything of value. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
