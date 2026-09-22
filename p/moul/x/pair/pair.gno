// Package pair is the whole behaviour of one constant-product AMM pair, as a
// pure package, so that a realm holding a single pair can be twenty lines of
// glue.
//
// It is the shared half of the instance-per-realm pattern: deploy this once,
// then deploy one tiny realm per token couple, each owning its own state, its
// own funds and its own storage deposit, all running this identical code. The
// Ethereum shape it copies (a factory spawning one UniswapV2Pair per couple)
// needs EIP-1167 clones to make the duplication affordable; an import makes it
// free.
//
// # How an instance uses it
//
//	var p *pair.Pair
//
//	func init(cur realm) {
//		p = pair.New(keyA, keyB, grc20reg.MustGet(keyA), grc20reg.MustGet(keyB))
//		pairreg.Register(cross(cur), p)
//	}
//
//	func Swap(cur realm, keyIn string, amountIn, minOut int64) int64 {
//		return p.Swap(0, cur, keyIn, amountIn, minOut)
//	}
//
// # Why the methods look like that
//
// Every state-changing method is shaped (_ int, rlm realm, ...). The leading
// dummy is mandatory: gno rejects a function whose FIRST parameter is realm
// when it is declared in a pure package ("crossing function declared in
// non-realm package"), and the parameter cannot be named cur either. Same
// reason grc20's tellers are Transfer(_ int, rlm realm, ...). The realm value
// arrives non-crossing, which is exactly what is wanted: the frame stays the
// instance realm, so funds move to and from the INSTANCE's address, and
// rlm.IsCurrent() still holds for grc20's spoof check.
//
// A pure package also cannot import a realm at all, so this package never
// resolves a token by path. The instance passes *grc20.Token handles in.
//
// # The economics, unchanged from the single-realm design
//
// Constant product x*y=k with a 30 bps fee kept by the pool, reserves stored
// and never derived from BalanceOf (so a direct transfer to the realm is
// inert, and permanently stuck), first deposit minting shares equal to the
// token-A amount with no sqrt and no MINIMUM_LIQUIDITY burn, and every reserve
// capped so the int64 arithmetic cannot overflow. The reasoning behind each of
// those is in https://github.com/moul/gno-contracts/issues/135 and is not
// repeated here; this package is that design with one pool per realm instead
// of many pools in one realm.
//
// Consequence worth repeating, because it bites: with a 1000x fee denominator
// on int64 amounts, this is unusable with 18-decimal tokens. Six to nine
// decimals is the practical band.
package pair

import (
	"chain"
	"math"
	"math/bits"
	"strconv"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/ufmt/v0"
)

const (
	// feeNum/feeDen is the swap fee kept by the pool: 997/1000, i.e. 30 bps.
	feeNum = 997
	feeDen = 1000

	// maxReserve is the largest reserve a pair will hold, in base units.
	//
	// Pricing computes den = reserveIn*feeDen + amountIn*feeNum in plain
	// int64 before handing off to the 128-bit mulDiv. Capping every reserve,
	// and every post-swap reserve, at MaxInt64/feeDen makes that sum provably
	// safe:
	//
	//	den < (reserveIn + amountIn) * feeDen <= maxReserve * feeDen
	//	    = 9223372036854775000 <= MaxInt64 = 9223372036854775807
	MaxReserve = math.MaxInt64 / feeDen // 9223372036854775
)

// Pair is one token couple and its liquidity. Fields are concrete by design:
// the registry realm holds a live pointer to this struct and reads it while
// rendering, so an interface or a func field here would let a hostile
// instance hand foreign code to the registry's frame.
//
// keyA < keyB always holds; New canonicalises.
type Pair struct {
	keyA, keyB  string
	tokA, tokB  *grc20.Token
	resA, resB  int64
	totalShares int64
	shares      *avl.Tree // address string -> int64
}

// New builds an empty pair from two grc20reg keys and the matching token
// handles, in canonical order. The caller (the instance realm) is responsible
// for resolving the handles, because a pure package cannot import the
// registry realm that holds them.
func New(keyA, keyB string, tokA, tokB *grc20.Token) *Pair {
	if keyA == "" || keyB == "" {
		panic("pair: empty token key")
	}
	if keyA == keyB {
		panic("pair: a pair needs two different tokens")
	}
	if tokA == nil || tokB == nil {
		panic("pair: nil token")
	}
	if keyA > keyB {
		keyA, keyB = keyB, keyA
		tokA, tokB = tokB, tokA
	}
	return &Pair{keyA: keyA, keyB: keyB, tokA: tokA, tokB: tokB, shares: avl.NewTree()}
}

//
// Writes. Each one takes the instance realm's own cur, forwarded.
//

// AddLiquidity deposits up to maxA of token A and maxB of token B and mints LP
// shares to the caller. On an existing pair the deposit is trimmed to the
// current reserve ratio, so pass the amounts you are willing to spend, not the
// amounts you insist on spending.
//
// The caller must first Approve the INSTANCE realm's address on both tokens.
// Returns the shares minted.
func (p *Pair) AddLiquidity(_ int, rlm realm, maxA, maxB int64) int64 {
	if maxA <= 0 || maxB <= 0 {
		panic("pair: both deposit amounts must be > 0")
	}
	amtA, amtB := maxA, maxB

	var minted int64
	if p.totalShares == 0 {
		// First position: the depositor sets the price and the share unit is
		// token A at seed time. No sqrt, no MINIMUM_LIQUIDITY burn.
		minted = amtA
	} else {
		// Trim to the current ratio, then mint from whichever side is scarcer.
		// Both divisions floor, and taking the minimum means an off-ratio
		// deposit is rounded against the depositor, never against the pool.
		if want := mulDiv(amtA, p.resB, p.resA); want <= amtB {
			amtB = want
		} else {
			amtA = mulDiv(amtB, p.resA, p.resB)
		}
		if amtA <= 0 || amtB <= 0 {
			panic("pair: deposit too small for the current ratio")
		}
		minted = min64(
			mulDiv(amtA, p.totalShares, p.resA),
			mulDiv(amtB, p.totalShares, p.resB),
		)
	}
	if minted <= 0 {
		panic("pair: deposit mints zero shares")
	}
	if p.resA+amtA > MaxReserve || p.resB+amtB > MaxReserve {
		panic("pair: reserve cap exceeded")
	}

	provider := rlm.Previous().Address()
	self := rlm.Address()
	pull(0, rlm, p.tokA, provider, self, amtA)
	pull(0, rlm, p.tokB, provider, self, amtB)

	p.resA += amtA
	p.resB += amtB
	p.totalShares += minted
	p.setShares(provider, p.SharesOf(provider)+minted)

	chain.Emit("AddLiquidity",
		"pair", p.ID(),
		"provider", provider.String(),
		"amountA", itoa(amtA),
		"amountB", itoa(amtB),
		"shares", itoa(minted),
	)
	return minted
}

// RemoveLiquidity burns shares held by the caller and returns the
// proportional amounts of both tokens, in (A, B) order.
//
// Burning the entire share supply pays out the whole reserve, so the last
// provider out leaves nothing unclaimable behind and the pair can be reseeded
// at a fresh price.
func (p *Pair) RemoveLiquidity(_ int, rlm realm, shares int64) (int64, int64) {
	if shares <= 0 {
		panic("pair: shares must be > 0")
	}
	owner := rlm.Previous().Address()
	held := p.SharesOf(owner)
	if held < shares {
		panic("pair: insufficient shares")
	}

	var amtA, amtB int64
	if shares == p.totalShares {
		amtA, amtB = p.resA, p.resB
	} else {
		amtA = mulDiv(shares, p.resA, p.totalShares)
		amtB = mulDiv(shares, p.resB, p.totalShares)
	}
	if amtA <= 0 || amtB <= 0 {
		panic("pair: burn would return nothing on one side")
	}

	p.resA -= amtA
	p.resB -= amtB
	p.totalShares -= shares
	p.setShares(owner, held-shares)

	push(0, rlm, p.tokA, owner, amtA)
	push(0, rlm, p.tokB, owner, amtB)

	chain.Emit("RemoveLiquidity",
		"pair", p.ID(),
		"provider", owner.String(),
		"amountA", itoa(amtA),
		"amountB", itoa(amtB),
		"shares", itoa(shares),
	)
	return amtA, amtB
}

// Swap sells amountIn of keyIn for the other token and aborts unless at least
// minOut comes back. The caller must first Approve the instance realm's
// address on keyIn.
//
// minOut is the only protection against being sandwiched or against the pair
// moving between quoting and execution. Pass a real bound; passing 0 means
// accepting any price at all.
func (p *Pair) Swap(_ int, rlm realm, keyIn string, amountIn, minOut int64) int64 {
	if amountIn <= 0 {
		panic("pair: amountIn must be > 0")
	}
	if minOut < 0 {
		panic("pair: minOut must be >= 0")
	}
	flipped := p.mustSide(keyIn)

	resIn, resOut := p.resA, p.resB
	tokIn, tokOut := p.tokA, p.tokB
	if flipped {
		resIn, resOut = p.resB, p.resA
		tokIn, tokOut = p.tokB, p.tokA
	}

	out := AmountOut(amountIn, resIn, resOut)
	if out <= 0 {
		panic("pair: output rounds to zero")
	}
	if out < minOut {
		panic("pair: slippage, output below minOut")
	}

	trader := rlm.Previous().Address()
	pull(0, rlm, tokIn, trader, rlm.Address(), amountIn)

	newIn, newOut := resIn+amountIn, resOut-out
	// The invariant holds by construction (out is floored), so this can only
	// fire if the pricing above is ever edited into being wrong. It is exact:
	// both products are compared in 128 bits.
	if cmpProd(newIn, newOut, resIn, resOut) < 0 {
		panic("pair: constant product regression")
	}
	if flipped {
		p.resB, p.resA = newIn, newOut
	} else {
		p.resA, p.resB = newIn, newOut
	}

	push(0, rlm, tokOut, trader, out)

	chain.Emit("Swap",
		"pair", p.ID(),
		"trader", trader.String(),
		"tokenIn", tokIn.GetSymbol(),
		"amountIn", itoa(amountIn),
		"amountOut", itoa(out),
	)
	return out
}

//
// Reads. Safe for the registry realm to call on another realm's Pair.
//

// AmountOut is the pricing function, fee included, as a pure function of the
// two reserves. Exported so a caller can quote off chain against reserves it
// already holds, and so the arithmetic is testable on its own.
func AmountOut(amountIn, reserveIn, reserveOut int64) int64 {
	if amountIn <= 0 {
		panic("pair: amountIn must be > 0")
	}
	if reserveIn <= 0 || reserveOut <= 0 {
		panic("pair: pair has an empty reserve")
	}
	if reserveIn > MaxReserve || reserveOut > MaxReserve {
		panic("pair: reserve above cap")
	}
	if amountIn > MaxReserve-reserveIn {
		panic("pair: reserve cap exceeded")
	}
	inFee := amountIn * feeNum
	den := reserveIn*feeDen + inFee
	return mulDiv(inFee, reserveOut, den)
}

// Quote prices amountIn of keyIn against the live reserves. It is the number
// Swap would return right now, which is not a promise about the next block.
func (p *Pair) Quote(keyIn string, amountIn int64) int64 {
	if p.totalShares == 0 {
		return 0
	}
	if p.mustSide(keyIn) {
		return AmountOut(amountIn, p.resB, p.resA)
	}
	return AmountOut(amountIn, p.resA, p.resB)
}

// Keys returns the two grc20reg keys in canonical order.
func (p *Pair) Keys() (string, string) { return p.keyA, p.keyB }

// Symbols returns the two token symbols in canonical order.
func (p *Pair) Symbols() (string, string) { return p.tokA.GetSymbol(), p.tokB.GetSymbol() }

// ID is the canonical identifier of the couple, "keyA~keyB". The separator is
// "~" and not "|": a "|" inside a markdown table cell breaks the row.
func (p *Pair) ID() string { return p.keyA + "~" + p.keyB }

// Reserves returns the two reserves in canonical order.
func (p *Pair) Reserves() (int64, int64) { return p.resA, p.resB }

// TotalShares returns the LP share supply.
func (p *Pair) TotalShares() int64 { return p.totalShares }

// Providers returns how many addresses hold shares.
func (p *Pair) Providers() int { return p.shares.Size() }

// SharesOf returns owner's LP shares.
func (p *Pair) SharesOf(owner address) int64 {
	v := p.shares.Get(owner.String())
	if v == nil {
		return 0
	}
	return v.(int64)
}

// Render is the instance realm's whole page: what the couple is, what it
// holds, and how to trade it.
func (p *Pair) Render(path string) string {
	symA, symB := p.Symbols()
	out := "# " + symA + " / " + symB + "\n\n"
	out += "One constant-product pair, `x*y=k`, 30 bps to the liquidity providers. "
	out += "Logic lives in [p/moul/x/pair/v0](/p/moul/x/pair/v0); this realm is the instance.\n\n"

	if p.totalShares == 0 {
		out += "_Empty. The first `AddLiquidity` sets the price._\n\n"
	} else {
		out += ufmt.Sprintf("| side | reserve | key |\n|---|---|---|\n| %s | %d | `%s` |\n| %s | %d | `%s` |\n\n",
			symA, p.resA, p.keyA, symB, p.resB, p.keyB)
		out += ufmt.Sprintf("- LP shares: **%d** across %d provider(s)\n",
			p.totalShares, p.shares.Size())
		out += ufmt.Sprintf("- Spot: 1 %s buys ~%d %s (before fee and slippage)\n\n",
			symA, p.spot(), symB)
	}
	out += "Approve this realm's address on the token you are selling, then call `Swap`.\n"
	return out
}

//
// Internals.
//

// spot is the display-only mid price, floor(resB/resA). Never price anything
// off it: it is a spot reserve ratio that any trader can move in one tx.
func (p *Pair) spot() int64 {
	if p.resA == 0 {
		return 0
	}
	return p.resB / p.resA
}

// mustSide reports whether key is the B side, and panics if it is neither.
func (p *Pair) mustSide(key string) bool {
	switch key {
	case p.keyA:
		return false
	case p.keyB:
		return true
	}
	panic("pair: " + key + " is not in this pair")
}

func (p *Pair) setShares(owner address, n int64) {
	if n == 0 {
		p.shares.Remove(owner.String())
		return
	}
	p.shares.Set(owner.String(), n)
}

// pull moves amount of tok from `from` into the instance realm, spending the
// allowance `from` granted to the instance realm's address.
//
// Non-crossing on purpose: `_ int, rlm realm` is the only shape a pure
// package can declare, and it keeps rlm the instance's own live frame.
// RealmTeller binds the spender eagerly to rlm.Address(), which is therefore
// the instance, not this package (a pure package has no address at all).
func pull(_ int, rlm realm, tok *grc20.Token, from, to address, amount int64) {
	err := tok.RealmTeller(0, rlm).TransferFrom(0, rlm, from, to, amount)
	if err != nil {
		panic("pair: cannot take " + tok.GetSymbol() + ": " + err.Error())
	}
}

// push sends amount of tok from the instance realm to `to`.
func push(_ int, rlm realm, tok *grc20.Token, to address, amount int64) {
	err := tok.RealmTeller(0, rlm).Transfer(0, rlm, to, amount)
	if err != nil {
		panic("pair: cannot send " + tok.GetSymbol() + ": " + err.Error())
	}
}

// mulDiv returns floor(a*b/c) through a 128-bit intermediate, which plain
// int64 arithmetic cannot do: a*b is routinely wider than 63 bits here even
// when the quotient is small.
func mulDiv(a, b, c int64) int64 {
	if a < 0 || b < 0 {
		panic("pair: negative operand")
	}
	if c <= 0 {
		panic("pair: division by a non-positive value")
	}
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	// bits.Div64 panics for y <= hi; refusing here turns that into a named
	// abort and also covers every quotient that would not fit in 64 bits.
	if hi >= uint64(c) {
		panic("pair: quotient overflows int64")
	}
	q, _ := bits.Div64(hi, lo, uint64(c))
	if q > uint64(math.MaxInt64) {
		panic("pair: quotient overflows int64")
	}
	return int64(q)
}

// cmpProd compares a*b with c*d exactly, in 128 bits, and returns -1, 0 or 1.
func cmpProd(a, b, c, d int64) int {
	h1, l1 := bits.Mul64(uint64(a), uint64(b))
	h2, l2 := bits.Mul64(uint64(c), uint64(d))
	if h1 != h2 {
		if h1 < h2 {
			return -1
		}
		return 1
	}
	if l1 != l2 {
		if l1 < l2 {
			return -1
		}
		return 1
	}
	return 0
}

func min64(a, b int64) int64 {
	if a < b {
		return a
	}
	return b
}

func itoa(v int64) string { return strconv.FormatInt(v, 10) }
