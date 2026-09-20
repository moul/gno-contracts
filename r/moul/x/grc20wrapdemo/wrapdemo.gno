// Package grc20wrapdemo is a permissionless wrapper factory for GRC20 tokens.
//
// Point it at any token registered in gno.land/r/nt/grc20reg/v0 and it issues a
// new one backed by it, with a personality you pick from a list. Point it at two
// and it issues a meta-token backed by both. Nothing is whitelisted, nothing is
// owned, and the realm never gains authority over anybody's balance: every
// deposit is pulled with an allowance the holder granted to this realm's address.
//
// The five wrapper modes, all from gno.land/p/moul/x/grc20wrap/v0:
//
//	plain      1:1 custody. A receipt. The boring one that proves the rest works.
//	kilo       1 underlying unit becomes 1000 wrapped ones, +3 decimals.
//	soulbound  wrap and unwrap freely, but the wrapped token never changes hands.
//	pool       shares in the escrow: Donate raises what every share redeems for.
//	sticky     pool, plus a 1% exit fee that stays behind for whoever holds on.
//
// And one fusion mode: NewFusion bundles two registered tokens at a fixed
// proportion into a single meta-token, redeemable back into both.
//
// # Wrapping a wrapper
//
// Every token this realm issues is itself registered in grc20reg, so its key can
// be fed straight back into NewWrapper or NewFusion. A pool over a kilo over a
// plain wrap of RED is legal, works, and is a good way to see how thin the
// abstraction really is.
//
// # The one thing a caller must do first
//
// Approve this realm's address on the underlying token, through THAT token's own
// realm. Home() prints the address. Without it every Deposit fails with
// "insufficient allowance", which is the system working.
//
// Play money to try it on: gno.land/r/moul/x/grc20faucet/v0.
package grc20wrapdemo

import (
	"chain/runtime"

	"gno.land/p/moul/x/grc20wrap/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// entry is one issued token: either a wrapper over a single underlying, or a
// fusion over several. Exactly one of vault/basket is set.
type entry struct {
	symbol  string
	mode    string
	key     string // grc20reg key of the issued token
	vault   *grc20wrap.Vault
	basket  *grc20wrap.Basket
	creator address
	height  int64
}

var (
	ids     seqid.ID
	byName  = avl.NewTree() // symbol -> *entry
	created []string        // symbols, in creation order, for a stable Render
	home    address         // this realm's address: the escrow account
)

func init(cur realm) {
	home = cur.Address()
}

// Home is the address to approve on an underlying token before depositing. It
// is where every escrow this realm holds actually sits.
func Home() address { return home }

// NewWrapper issues a token wrapping `tokenKey`, a key in grc20reg, under the
// given mode, and registers it. It returns the new token's own registry key.
//
// `symbol` is yours to choose, must be unique in this realm, and follows the
// GRC20 rules: 1 to 11 characters of [A-Za-z0-9_-].
func NewWrapper(cur realm, tokenKey, mode, symbol string) string {
	who := caller(cur)
	under := grc20reg.MustGet(tokenKey)
	requireFree(symbol)

	pol, extraDecimals := modePolicy(mode)
	decimals := under.GetDecimals() + extraDecimals
	if decimals > 18 {
		panic(ufmt.Sprintf("%s already has %d decimals; mode %q would need %d, over the GRC20 limit of 18",
			under.GetSymbol(), under.GetDecimals(), mode, decimals))
	}
	name := ufmt.Sprintf("%s (%s wrap of %s)", symbol, mode, under.GetSymbol())

	v := grc20wrap.NewVault(under, pol, name, symbol, decimals, ids.Next(), cur)
	key := grc20reg.Register(cross(cur), v.Token(), "")
	record(&entry{
		symbol:  symbol,
		mode:    mode,
		key:     key,
		vault:   v,
		creator: who,
		height:  runtime.ChainHeight(),
	})
	return key
}

// NewFusion issues a meta-token backed by two registered tokens at a fixed
// proportion: one smallest unit of the meta-token is always worth `perA`
// smallest units of A plus `perB` of B. It returns the new token's registry key.
//
// The proportion never changes, and the meta-token is minted and burned only
// against the real thing, so it cannot drift from its backing or be arbitraged.
// What it can do is make the pair one transferable object.
func NewFusion(cur realm, keyA string, perA int64, keyB string, perB int64, symbol string) string {
	who := caller(cur)
	a := grc20reg.MustGet(keyA)
	b := grc20reg.MustGet(keyB)
	requireFree(symbol)

	decimals := a.GetDecimals()
	if b.GetDecimals() > decimals {
		decimals = b.GetDecimals()
	}
	name := ufmt.Sprintf("%s (%s+%s fusion)", symbol, a.GetSymbol(), b.GetSymbol())

	bk := grc20wrap.NewBasket(
		[]*grc20.Token{a, b},
		[]int64{perA, perB},
		name, symbol, decimals, ids.Next(), cur,
	)
	key := grc20reg.Register(cross(cur), bk.Token(), "")
	record(&entry{
		symbol:  symbol,
		mode:    "fusion",
		key:     key,
		basket:  bk,
		creator: who,
		height:  runtime.ChainHeight(),
	})
	return key
}

// Deposit escrows `amount` of the underlying and mints `symbol` to the caller.
// It returns how much was minted, which is not `amount` unless the mode is
// plain. Approve Home() on the underlying first.
func Deposit(cur realm, symbol string, amount int64) int64 {
	who := caller(cur)
	out, err := mustVault(symbol).Wrap(0, cur, who, amount)
	checkErr(err)
	return out
}

// Withdraw burns `amount` of `symbol` and returns the underlying to the caller.
// It returns how much came back.
func Withdraw(cur realm, symbol string, amount int64) int64 {
	who := caller(cur)
	out, err := mustVault(symbol).Unwrap(0, cur, who, amount)
	checkErr(err)
	return out
}

// Donate escrows `amount` of the underlying for `symbol` and mints nothing.
//
// Under a pool or sticky mode this is a gift to every current holder at once,
// and it is irreversible: there is no share to redeem it with. Under any other
// mode it is a gift to nobody, since the rate ignores the escrow.
func Donate(cur realm, symbol string, amount int64) {
	who := caller(cur)
	checkErr(mustVault(symbol).Donate(0, cur, who, amount))
}

// Fuse escrows every leg of `symbol` and mints `units` of it to the caller.
// Approve Home() on BOTH legs first.
func Fuse(cur realm, symbol string, units int64) {
	who := caller(cur)
	checkErr(mustBasket(symbol).Fuse(0, cur, who, units))
}

// Defuse burns `units` of `symbol` and returns every leg to the caller.
func Defuse(cur realm, symbol string, units int64) {
	who := caller(cur)
	checkErr(mustBasket(symbol).Defuse(0, cur, who, units))
}

// Transfer moves the caller's own units of `symbol`. A soulbound wrapper
// refuses here, and nowhere else.
func Transfer(cur realm, symbol string, to address, amount int64) {
	who := caller(cur)
	e := must(symbol)
	if e.vault != nil {
		checkErr(e.vault.Move(who, to, amount))
		return
	}
	checkErr(e.basket.Move(who, to, amount))
}

// Approve lets `spender` draw `amount` of `symbol` from the caller's balance.
func Approve(cur realm, symbol string, spender address, amount int64) {
	who := caller(cur)
	e := must(symbol)
	if e.vault != nil {
		checkErr(e.vault.Allow(who, spender, amount))
		return
	}
	checkErr(e.basket.Allow(who, spender, amount))
}

// TransferFrom spends an allowance the caller was granted on `symbol`.
func TransferFrom(cur realm, symbol string, from, to address, amount int64) {
	who := caller(cur)
	e := must(symbol)
	if e.vault != nil {
		checkErr(e.vault.MoveFrom(who, from, to, amount))
		return
	}
	checkErr(e.basket.MoveFrom(who, from, to, amount))
}

// Key returns the grc20reg key of the token this realm issued as `symbol`.
func Key(symbol string) string { return must(symbol).key }

// TotalSupply returns how much of `symbol` is outstanding.
func TotalSupply(symbol string) int64 { return must(symbol).token().TotalSupply() }

// BalanceOf returns `owner`'s balance of `symbol`.
func BalanceOf(symbol string, owner address) int64 {
	return must(symbol).token().BalanceOf(owner)
}

// Allowance returns what `owner` let `spender` draw of `symbol`.
func Allowance(symbol string, owner, spender address) int64 {
	return must(symbol).token().Allowance(owner, spender)
}

// Escrow returns the underlying escrowed behind a wrapper.
func Escrow(symbol string) int64 { return mustVault(symbol).Held() }

// Legs returns how many components a fusion has.
func Legs(symbol string) int { return mustBasket(symbol).Legs() }

// Leg describes the i-th component of a fusion: its symbol, the units escrowed
// per meta unit, and the units escrowed so far.
func Leg(symbol string, i int) (string, int64, int64) {
	tok, per, held := mustBasket(symbol).Leg(i)
	return tok.GetSymbol(), per, held
}

// Count is how many tokens this realm has issued.
func Count() int { return len(created) }

// internals
//

// modePolicy maps a mode name to its policy and to the extra decimals the
// wrapped token needs to represent the same value.
func modePolicy(mode string) (grc20wrap.Policy, int) {
	switch mode {
	case "plain":
		return grc20wrap.OneToOne{}, 0
	case "kilo":
		return grc20wrap.Ratio{Num: 1_000, Den: 1}, 3
	case "soulbound":
		return grc20wrap.Soulbound{}, 0
	case "pool":
		return grc20wrap.Pool{}, 0
	case "sticky":
		return grc20wrap.Fee{Base: grc20wrap.Pool{}, UnwrapBPS: 100}, 0
	}
	panic("unknown mode " + mode + " (plain, kilo, soulbound, pool, sticky)")
}

func (e *entry) token() *grc20.Token {
	if e.vault != nil {
		return e.vault.Token()
	}
	return e.basket.Token()
}

func record(e *entry) {
	byName.Set(e.symbol, e)
	created = append(created, e.symbol)
}

func requireFree(symbol string) {
	if byName.Has(symbol) {
		panic("symbol " + symbol + " is already issued by this realm")
	}
}

func must(symbol string) *entry {
	e := byName.Get(symbol)
	if e == nil {
		panic("this realm has not issued " + symbol)
	}
	return e.(*entry)
}

func mustVault(symbol string) *grc20wrap.Vault {
	e := must(symbol)
	if e.vault == nil {
		panic(symbol + " is a fusion; use Fuse and Defuse")
	}
	return e.vault
}

func mustBasket(symbol string) *grc20wrap.Basket {
	e := must(symbol)
	if e.basket == nil {
		panic(symbol + " is a wrapper; use Deposit and Withdraw")
	}
	return e.basket
}

// caller is the account or realm that crossed into this one. Every deposit is
// escrowed from, and every mint credited to, exactly this address.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("grc20wrapdemo: stale realm token")
	}
	return cur.Previous().Address()
}

func checkErr(err error) {
	if err != nil {
		panic(err)
	}
}
