// Package amm is a minimal constant-product automated market maker for GRC20
// token pairs, in a single file.
//
// It holds many pools in one realm. A pool is created implicitly by its first
// liquidity deposit and is addressed by the two tokens' grc20reg keys, in
// either order. Swaps follow x*y=k with a 30 bps fee that stays in the pool
// and therefore accrues to the liquidity providers.
//
// # What it is not
//
// Not an oracle: the reserve ratio is a spot price that any trader can move
// within a single transaction. Nothing should price off this realm.
// Not audited. Not a router: one hop, one pool, no path finding. Not a
// place to park value.
//
// # Design notes worth knowing before calling it
//
// Reserves are stored fields and are NEVER derived from BalanceOf. That is
// the single decision that removes Uniswap V2's MINIMUM_LIQUIDITY burn, its
// skim/sync pair, and the first-depositor share-inflation attack in one go:
// sending tokens straight to this realm's address changes no reserve, no
// price and no share value. The price of that is blunt and worth stating:
// tokens sent directly to the realm address are PERMANENTLY STUCK.
//
// The first deposit mints shares equal to the token-A amount rather than
// sqrt(A*B). The geometric mean is cosmetic, every later operation uses only
// ratios, and dropping it removes an integer square root over a 128-bit
// product. Later deposits mint min(A-side, B-side) with floor division on
// both, so an off-ratio deposit always rounds against the depositor.
//
// # v1 vs v0: LP shares are a real GRC20 token
//
// v0 tracks LP positions in a private avl ledger: smallest possible, but a
// position can only be held by the address that opened it and is invisible to
// every other contract. v1 mints one GRC20 token per pool instead, holds its
// PrivateLedger, and registers it with grc20reg. A position is then an
// ordinary fungible token: transferable, approvable, usable as collateral,
// and readable by any realm that knows the registry key.
//
// The cost is honest and measurable. Pool creation now also mints a token and
// writes a registry entry. Positions gain an allowance surface, and with it
// the classic GRC20 approve race. And because MsgCall cannot pass a realm
// argument, this realm has to re-export Transfer/Approve/TransferFrom/
// Allowance wrappers over the LP token for signing users, four functions that
// v0 does not need at all. Another REALM can skip them and move its own LP
// balance through grc20reg directly.
//
// All amounts are int64, as GRC20 mandates, and there is no 256-bit type in
// reach. Pricing therefore runs through a 128-bit mulDiv (math/bits), and
// every reserve is capped at maxReserve so that the plain int64 parts of the
// formula cannot overflow. See the comment on maxReserve for the arithmetic,
// and note the consequence: this AMM is unusable with 18-decimal tokens.
// Six to nine decimals is the practical band.
//
// Design study and full analysis: https://github.com/moul/gno-contracts/issues/135
package amm

import (
	"chain"
	"math"
	"math/bits"
	"strconv"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/r/nt/grc20reg/v0"
)

const (
	// feeNum/feeDen is the swap fee kept by the pool: 997/1000, i.e. 30 bps.
	feeNum = 997
	feeDen = 1000

	// maxReserve is the largest reserve a pool will hold, in base units.
	//
	// Pricing computes den = reserveIn*feeDen + amountIn*feeNum in plain
	// int64 before handing off to the 128-bit mulDiv. Capping every reserve,
	// and every post-swap reserve, at MaxInt64/feeDen makes that sum provably
	// safe:
	//
	//	den < (reserveIn + amountIn) * feeDen <= maxReserve * feeDen
	//	    = 9223372036854775000 <= MaxInt64 = 9223372036854775807
	//
	// AddLiquidity enforces the cap on the reserves themselves and Swap
	// enforces it on reserveIn+amountIn, so a pool can never even enter the
	// region where the formula would be unsafe.
	maxReserve = math.MaxInt64 / feeDen // 9223372036854775
)

// pool is one token pair. keyA < keyB always holds: the pair is canonicalised
// on the way in, so (X,Y) and (Y,X) address the same pool.
type pool struct {
	keyA, keyB string
	tokA, tokB *grc20.Token
	resA, resB int64

	// lp is this pool's LP token: total supply is the share supply and a
	// holder's balance is their position. lpLedger is the minting authority
	// and MUST NOT leak out of this file. lpKey is lp's grc20reg key.
	lp       *grc20.Token
	lpLedger *grc20.PrivateLedger
	lpKey    string
}

// pools maps the pool id "keyA~keyB" -> *pool. "~" cannot occur in a
// grc20reg key, and unlike "|" it does not break a markdown table cell.
var pools avl.Tree

// lpSeq numbers the LP tokens. It is never reset, so a symbol is never reused
// and grc20reg's one-token-per-realm-and-symbol rule is never tripped.
var lpSeq seqid.ID

//
// Writes.
//

// AddLiquidity deposits up to maxA of keyA and maxB of keyB and mints LP
// shares to the caller. It creates the pool if this is its first deposit, in
// which case the caller's amounts set the starting price and the whole of
// maxA and maxB is taken.
//
// On an existing pool the deposit is trimmed to the current reserve ratio:
// only one side is consumed in full and the remainder of the richer side is
// left untouched, so pass the amounts you are willing to spend, not the
// amounts you insist on spending.
//
// The caller must first Approve this realm's address on BOTH tokens for at
// least the amounts that will be taken. Returns the shares minted.
func AddLiquidity(cur realm, keyA, keyB string, maxA, maxB int64) int64 {
	a, b, flipped := canon(keyA, keyB)
	amtA, amtB := maxA, maxB
	if flipped {
		amtA, amtB = maxB, maxA
	}
	if amtA <= 0 || amtB <= 0 {
		panic("amm: both deposit amounts must be > 0")
	}

	p := getPool(a, b)
	if p == nil {
		p = newPool(0, cur, a, b)
		pools.Set(poolID(a, b), p)
	}

	var minted int64
	if p.lp.TotalSupply() == 0 {
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
			panic("amm: deposit too small for the current ratio")
		}
		supply := p.lp.TotalSupply()
		minted = min64(
			mulDiv(amtA, supply, p.resA),
			mulDiv(amtB, supply, p.resB),
		)
	}
	if minted <= 0 {
		panic("amm: deposit mints zero shares")
	}
	if p.resA+amtA > maxReserve || p.resB+amtB > maxReserve {
		panic("amm: reserve cap exceeded")
	}

	provider := cur.Previous().Address()
	self := cur.Address()
	pull(0, cur, p.tokA, provider, self, amtA)
	pull(0, cur, p.tokB, provider, self, amtB)

	p.resA += amtA
	p.resB += amtB
	if err := p.lpLedger.Mint(provider, minted); err != nil {
		panic("amm: cannot mint LP shares: " + err.Error())
	}

	chain.Emit("AddLiquidity",
		"pool", poolID(p.keyA, p.keyB),
		"provider", provider.String(),
		"amountA", itoa(amtA),
		"amountB", itoa(amtB),
		"shares", itoa(minted),
	)
	return minted
}

// RemoveLiquidity burns shares held by the caller and returns the proportional
// amounts of both tokens, in the caller's (keyA, keyB) argument order.
//
// Burning the pool's entire share supply pays out the whole reserve, so the
// last provider out leaves nothing unclaimable behind and the pool can be
// reseeded at a fresh price.
func RemoveLiquidity(cur realm, keyA, keyB string, shares int64) (int64, int64) {
	if shares <= 0 {
		panic("amm: shares must be > 0")
	}
	a, b, flipped := canon(keyA, keyB)
	p := mustPool(a, b)

	owner := cur.Previous().Address()
	if p.lp.BalanceOf(owner) < shares {
		panic("amm: insufficient shares")
	}

	supply := p.lp.TotalSupply()
	var amtA, amtB int64
	if shares == supply {
		amtA, amtB = p.resA, p.resB
	} else {
		amtA = mulDiv(shares, p.resA, supply)
		amtB = mulDiv(shares, p.resB, supply)
	}
	if amtA <= 0 || amtB <= 0 {
		panic("amm: burn would return nothing on one side")
	}

	p.resA -= amtA
	p.resB -= amtB
	if err := p.lpLedger.Burn(owner, shares); err != nil {
		panic("amm: cannot burn LP shares: " + err.Error())
	}

	push(0, cur, p.tokA, owner, amtA)
	push(0, cur, p.tokB, owner, amtB)

	chain.Emit("RemoveLiquidity",
		"pool", poolID(p.keyA, p.keyB),
		"provider", owner.String(),
		"amountA", itoa(amtA),
		"amountB", itoa(amtB),
		"shares", itoa(shares),
	)
	if flipped {
		return amtB, amtA
	}
	return amtA, amtB
}

// Swap sells amountIn of keyIn for keyOut and aborts unless at least minOut
// comes back. The caller must first Approve this realm's address on keyIn.
//
// minOut is the only protection against being sandwiched or against the pool
// moving between quoting and execution. Pass a real bound; passing 0 means
// accepting any price at all.
func Swap(cur realm, keyIn, keyOut string, amountIn, minOut int64) int64 {
	if amountIn <= 0 {
		panic("amm: amountIn must be > 0")
	}
	if minOut < 0 {
		panic("amm: minOut must be >= 0")
	}
	a, b, flipped := canon(keyIn, keyOut)
	p := mustPool(a, b)

	resIn, resOut := p.resA, p.resB
	tokIn, tokOut := p.tokA, p.tokB
	if flipped {
		resIn, resOut = p.resB, p.resA
		tokIn, tokOut = p.tokB, p.tokA
	}

	out := AmountOut(amountIn, resIn, resOut)
	if out <= 0 {
		panic("amm: output rounds to zero")
	}
	if out < minOut {
		panic("amm: slippage, output below minOut")
	}

	trader := cur.Previous().Address()
	pull(0, cur, tokIn, trader, cur.Address(), amountIn)

	newIn, newOut := resIn+amountIn, resOut-out
	// The invariant holds by construction (out is floored), so this can only
	// fire if the pricing above is ever edited into being wrong. It is exact:
	// both products are compared in 128 bits.
	if cmpProd(newIn, newOut, resIn, resOut) < 0 {
		panic("amm: constant product regression")
	}
	if flipped {
		p.resB, p.resA = newIn, newOut
	} else {
		p.resA, p.resB = newIn, newOut
	}

	push(0, cur, tokOut, trader, out)

	chain.Emit("Swap",
		"pool", poolID(p.keyA, p.keyB),
		"trader", trader.String(),
		"tokenIn", tokIn.GetSymbol(),
		"amountIn", itoa(amountIn),
		"amountOut", itoa(out),
	)
	return out
}

// TransferLP moves amount of the caller's LP position to `to`.
//
// The LP token lives in this realm, so a signing user cannot reach it through
// the token's own entry points the way they would for any other GRC20: there
// are none. These four wrappers are that entry point. A REALM holding LP does
// not need them and can go through grc20reg instead:
//
//	grc20reg.Transfer(0, cur, amm.LPToken(keyA, keyB), to, n)
func TransferLP(cur realm, keyA, keyB string, to address, amount int64) {
	a, b, _ := canon(keyA, keyB)
	lpCheck(mustPool(a, b).lpLedger.CallerTeller().Transfer(0, cur, to, amount))
}

// ApproveLP lets spender move up to amount of the caller's LP position.
//
// Same approve race as any GRC20: an allowance changed from a non-zero value
// can be spent at both the old and the new one if the holder is unlucky with
// ordering. Set it to 0 first when lowering it.
func ApproveLP(cur realm, keyA, keyB string, spender address, amount int64) {
	a, b, _ := canon(keyA, keyB)
	lpCheck(mustPool(a, b).lpLedger.CallerTeller().Approve(0, cur, spender, amount))
}

// TransferFromLP spends an allowance the owner granted to the caller.
func TransferFromLP(cur realm, keyA, keyB string, from, to address, amount int64) {
	a, b, _ := canon(keyA, keyB)
	lpCheck(mustPool(a, b).lpLedger.CallerTeller().TransferFrom(0, cur, from, to, amount))
}

func lpCheck(err error) {
	if err != nil {
		panic("amm: LP token: " + err.Error())
	}
}

//
// Reads.
//

// AmountOut is the pricing function, fee included, as a pure function of the
// two reserves. Exported so a caller can quote off-chain against reserves it
// already holds, and so the arithmetic is testable on its own.
func AmountOut(amountIn, reserveIn, reserveOut int64) int64 {
	if amountIn <= 0 {
		panic("amm: amountIn must be > 0")
	}
	if reserveIn <= 0 || reserveOut <= 0 {
		panic("amm: pool has an empty reserve")
	}
	if reserveIn > maxReserve || reserveOut > maxReserve {
		panic("amm: reserve above cap")
	}
	if amountIn > maxReserve-reserveIn {
		panic("amm: reserve cap exceeded")
	}
	inFee := amountIn * feeNum
	den := reserveIn*feeDen + inFee
	return mulDiv(inFee, reserveOut, den)
}

// Quote prices amountIn of keyIn against the pool's live reserves. It is the
// number Swap would return right now, which is not a promise about the next
// block.
func Quote(keyIn, keyOut string, amountIn int64) int64 {
	a, b, flipped := canon(keyIn, keyOut)
	p := mustPool(a, b)
	if flipped {
		return AmountOut(amountIn, p.resB, p.resA)
	}
	return AmountOut(amountIn, p.resA, p.resB)
}

// Reserves returns the two reserves in the caller's argument order.
func Reserves(keyA, keyB string) (int64, int64) {
	a, b, flipped := canon(keyA, keyB)
	p := mustPool(a, b)
	if flipped {
		return p.resB, p.resA
	}
	return p.resA, p.resB
}

// SharesOf returns owner's LP shares, i.e. their LP token balance.
func SharesOf(keyA, keyB string, owner address) int64 {
	a, b, _ := canon(keyA, keyB)
	return mustPool(a, b).lp.BalanceOf(owner)
}

// TotalShares returns the pool's LP token total supply.
func TotalShares(keyA, keyB string) int64 {
	a, b, _ := canon(keyA, keyB)
	return mustPool(a, b).lp.TotalSupply()
}

// LPToken returns the grc20reg key of the pool's LP token. Hand it to any
// realm that should read or move these positions without importing this one.
func LPToken(keyA, keyB string) string {
	a, b, _ := canon(keyA, keyB)
	return mustPool(a, b).lpKey
}

// AllowanceLP reports how much of owner's LP position spender may move.
func AllowanceLP(keyA, keyB string, owner, spender address) int64 {
	a, b, _ := canon(keyA, keyB)
	return mustPool(a, b).lp.Allowance(owner, spender)
}

// PoolCount returns how many pools exist.
func PoolCount() int { return pools.Size() }

// Render lists every pool, or one pool's detail when path is a "keyA~keyB"
// pool id.
func Render(path string) string {
	if path != "" {
		v := pools.Get(path)
		if v == nil {
			return "# 404\n\nNo pool `" + path + "`.\n"
		}
		p := v.(*pool)
		out := "# " + p.tokA.GetSymbol() + " / " + p.tokB.GetSymbol() + "\n\n"
		out += "- **" + p.tokA.GetSymbol() + "** reserve: " + itoa(p.resA) + " (`" + p.keyA + "`)\n"
		out += "- **" + p.tokB.GetSymbol() + "** reserve: " + itoa(p.resB) + " (`" + p.keyB + "`)\n"
		out += "- **LP token**: `" + p.lpKey + "` (" + p.lp.GetSymbol() + ")\n"
		out += "- **LP shares**: " + itoa(p.lp.TotalSupply()) + " across " + strconv.Itoa(p.lp.KnownAccounts()) + " holder(s)\n"
		return out
	}

	out := "# Minimal AMM\n\n"
	out += "Constant product (`x*y=k`) with a 30 bps fee kept by the pool. Every position is a transferable GRC20 LP token. Reserves are stored, never read from balances, so sending tokens here directly does nothing and they cannot be recovered.\n\n"
	if pools.Size() == 0 {
		out += "_No pools yet. Call `AddLiquidity` with two `grc20reg` keys to open one._\n"
		return out
	}
	out += "| pool | reserves | LP token | supply | holders |\n"
	out += "|---|---|---|---|---|\n"
	pools.Iterate("", "", func(key string, value any) bool {
		p := value.(*pool)
		out += ufmt.Sprintf("| [%s/%s](/r/moul/x/amm/v0:%s) | %d %s / %d %s | %s | %d | %d |\n",
			p.tokA.GetSymbol(), p.tokB.GetSymbol(), key,
			p.resA, p.tokA.GetSymbol(), p.resB, p.tokB.GetSymbol(),
			p.lp.GetSymbol(), p.lp.TotalSupply(), p.lp.KnownAccounts())
		return false
	})
	return out
}

//
// Internals.
//

// canon sorts a caller's token pair into the pool's canonical order and
// reports whether the caller's order was reversed.
func canon(first, second string) (a, b string, flipped bool) {
	if first == "" || second == "" {
		panic("amm: empty token key")
	}
	if first == second {
		panic("amm: a pool needs two different tokens")
	}
	if first > second {
		return second, first, true
	}
	return first, second, false
}

// newPool resolves both tokens, mints this pool's LP token and registers it.
//
// Non-crossing (`_ int, rlm realm`): grc20.NewToken binds the token's
// origRealm to rlm.PkgPath() under an IsCurrent assertion, and grc20reg
// keys off the registering caller, so rlm has to stay AddLiquidity's own
// live frame rather than a fresh one.
//
// The LP unit is token A at seed time, so the LP token mirrors token A's
// decimals. The symbol is LP<n> because grc20 caps a symbol at 11 chars,
// which "LP-" plus two 11-char symbols would blow past; the human-readable
// pair lives in the name instead.
func newPool(_ int, rlm realm, a, b string) *pool {
	tokA, tokB := grc20reg.MustGet(a), grc20reg.MustGet(b)
	id := lpSeq.Next()
	lp, ledger := grc20.NewToken(
		"AMM LP "+tokA.GetSymbol()+"/"+tokB.GetSymbol(),
		"LP"+strconv.FormatUint(uint64(id), 10),
		tokA.GetDecimals(),
		id,
		rlm,
	)
	p := &pool{keyA: a, keyB: b, tokA: tokA, tokB: tokB, lp: lp, lpLedger: ledger}
	p.lpKey = grc20reg.Register(cross(rlm), lp, "")
	return p
}

// poolID is the storage and render key for a canonicalised pair.
func poolID(a, b string) string { return a + "~" + b }

func getPool(a, b string) *pool {
	v := pools.Get(poolID(a, b))
	if v == nil {
		return nil
	}
	return v.(*pool)
}

func mustPool(a, b string) *pool {
	p := getPool(a, b)
	if p == nil {
		panic("amm: no such pool: " + poolID(a, b))
	}
	return p
}

// pull moves amount of tok from `from` into this realm, spending the
// allowance `from` granted to this realm's address.
//
// Non-crossing on purpose: `_ int, rlm realm` is the only shape that keeps
// rlm the caller's own live frame. RealmTeller binds the spender eagerly to
// rlm.Address(), which is this realm.
func pull(_ int, rlm realm, tok *grc20.Token, from, to address, amount int64) {
	err := tok.RealmTeller(0, rlm).TransferFrom(0, rlm, from, to, amount)
	if err != nil {
		panic("amm: cannot take " + tok.GetSymbol() + ": " + err.Error())
	}
}

// push sends amount of tok from this realm to `to`.
func push(_ int, rlm realm, tok *grc20.Token, to address, amount int64) {
	err := tok.RealmTeller(0, rlm).Transfer(0, rlm, to, amount)
	if err != nil {
		panic("amm: cannot send " + tok.GetSymbol() + ": " + err.Error())
	}
}

// mulDiv returns floor(a*b/c) through a 128-bit intermediate, which plain
// int64 arithmetic cannot do: a*b is routinely wider than 63 bits here even
// when the quotient is small.
func mulDiv(a, b, c int64) int64 {
	if a < 0 || b < 0 {
		panic("amm: negative operand")
	}
	if c <= 0 {
		panic("amm: division by a non-positive value")
	}
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	// bits.Div64 panics for y <= hi; refusing here turns that into a named
	// abort and also covers every quotient that would not fit in 64 bits.
	if hi >= uint64(c) {
		panic("amm: quotient overflows int64")
	}
	q, _ := bits.Div64(hi, lo, uint64(c))
	if q > uint64(math.MaxInt64) {
		panic("amm: quotient overflows int64")
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
