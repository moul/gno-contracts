# `gno.land/p/moul/kit/num`

Numbers, formatted for a human to read: fixed-point amounts, percentages, zero
padding.

Third package of the `p/moul/kit/*` layer
([moul/gno-contracts#151](https://github.com/moul/gno-contracts/issues/151)),
after [`kit/ui`](../ui) and [`kit/store`](../store). `kit` composes the existing
packages, it does not replace them.

## Why it exists

Unlike the rest of `kit`, this one is not deduplication. **Nothing in `p/moul`
or `p/nt` turns 1234567 ugnot into `1.234567 GNOT`**, so every team that needed
it wrote it.

Measured 2026-09-28 across the 828 `.gno` files deployed on `gnoland-1` by
somebody other than moul (`gnolang/tx-exports`, mainnet, genesis excluded):

| who | what they wrote | copies |
|---|---|---:|
| the `bubblerumble` realms | `GNOT(ugnot int64)` | 5, byte-identical |
| `kourt` | `ccAmt(n int64)` | 2 |
| GnoSwap | `gnsDisplayScale` + `zeroPadUnsigned` + `p/gnoswap/utils.FormatUint` | 3 |
| `bubbletreasury` | `one = int64(1_000_000)` | 1 |

Five independent answers to "show money to a human". GnoSwap wrote a type
switch over `any` to turn an integer into a string, because there was nothing
to import.

## The two live implementations disagree on every input that is not positive

Both were run verbatim, 2026-09-28, not read:

| ugnot | `bubblerumble`'s `GNOT` | `kourt`'s `ccAmt` | correct |
|---:|---|---|---|
| 1234567 | `1.234567 GNOT` | `1.234567` | ✅ both |
| 100 | `0.0001 GNOT` | `0.0001` | ✅ both |
| **-100** | **`0.999 GNOT`** | `-0.0001` | sign dropped, digits wrong |
| **-1500000** | **`-1. GNOT`** | `-1.5` | not a number |
| **-1** | **`0.99999 GNOT`** | `-0.000001` | sign dropped, digits wrong |
| **int64 min** | `-9223372036854.24192` | **infinite recursion** | one wrong, one halts |

Two different failures from the same 8 lines:

- `GNOT` computes `frac := ugnot % 1_000_000`, which is **negative** for a
  negative amount, then feeds it to a trick (`FormatInt(1_000_000+frac)[1:]`)
  that only works on a positive remainder. Below one GNOT the sign vanishes
  entirely and the digits become the ten's complement.
- `ccAmt` handles the sign correctly and then recurses on `-n`. On
  `math.MinInt64`, `-n` is `math.MinInt64` again, still negative, so it calls
  itself forever. Measured: stack overflow.

Neither is reachable from a user-supplied negative today as far as I could
tell, and I did not try to prove reachability either way. The point is that
this is 8 lines everyone rewrites, half of them get it wrong, and nobody ever
tests the sign.

## This repo is not the exception, it is the sixth case

Six more copies live here, in five more implementations, and they disagree with
each other as well:

| where | shape | `gnot(-1500000)` |
|---|---|---|
| [`r/moul/vesting`](../../../../r/moul/vesting/vesting.gno) | `u = -u`, never trims | `-1.500000 GNOT` |
| [`r/moul/faucet`](../../../../r/moul/faucet/render.gno) | `u = -u`, trims | `-1.5` |
| [`p/moul/x/storagecost`](../../x/storagecost/storagecost.gno) | `amount = -amount`, trims | `-1.5` |
| [`r/moul/x/games/lastwords`](../../../../r/moul/x/games/lastwords/lastwords.gno) | no sign handling | **`-1.-5`** |
| [`p/moul/x/wiki`](../../x/wiki/render.gno) | no sign handling | **`-1.-5 GNOT`** |
| [`r/moul/x/daily/wrapped`](../../../../r/moul/x/daily/wrapped/wrapped.gno) | no decimals at all | n/a |

`vesting` also pads to six digits where the other four trim, so the same
amount reads `1.500000` in one realm and `1.5` in the next. All six are live on
mainnet, so porting them is a bump each and a separate decision, not part of
this package.

## What is here

| | |
|---|---|
| `Dec(v, decimals)` | fixed point, trailing zeros trimmed. `Dec(1234500, 6)` is `1.2345` |
| `DecFixed(v, decimals)` | same, padded to full width, for a column |
| `GNOT(ugnot)` / `GNOTf(ugnot)` | `Dec(v, 6)`, without and with the unit |
| `Pct(bps)` | basis points to a percentage. `Pct(1234)` is `12.34%` |
| `Pad(v, width)` | `Pad(7, 3)` is `007`, because `ufmt` has no width flags |

For a GRC20, pass the token's own decimals to `Dec`: six is GNOT's, not
everyone's.

## The contract

**Every function is total.** No input panics, including `math.MinInt64`, and no
input returns a string that is not a number. `Dec` panics on a `decimals`
outside `[0, 19]`, which is a programming error rather than a value.

That contract is the package. It is pinned by
`TestEveryDecimalStringParsesBack`, which parses every output back and checks
the sign survived: swap in either live implementation and it goes red on four
inputs, which is how it was verified rather than assumed.

## What is deliberately not here

- **Thousands separators.** `1,234,567` belongs to
  [`p/moul/x/daily/humanize`](../../x/daily/humanize), which already owns
  `Comma`, `Bytes`, `Ordinal`, `Plural` and `Blocks`. One owner per fact. (Its
  `Comma` returns `--9,223,372,036,854,775,808` at the int64 minimum, the same
  `n = -n` shape as everything else on this page, and that is a bump for it
  rather than a reason to write a second one here.)
- **Markdown.** `Dec` returns digits. Wrap it in [`kit/ui`](../ui) or
  [`p/moul/md`](../../md) if it needs to be bold or in a cell.
- **Compact notation** (`1.2k`, `3.4M`). Nobody on chain has written one, so
  building it here would be speculative generality on a public path.
- **avl keys.** `Pad` is for display. A key that must sort in insertion order
  belongs to [`kit/store`](../store), which has no ceiling to overflow.
- **Parsing.** One direction only until something needs the other.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
