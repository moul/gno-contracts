// Package nativeify turns a GRC20 into a native coin, which is wugnot run
// backwards.
//
// wugnot takes GNOT, a coin the bank holds, and issues a GRC20 receipt for it,
// because a GRC20 can be pulled by a contract and a native coin cannot. This
// realm takes a GRC20, escrows it, and issues a native denom against it 1:1,
// because a native coin can do four things a GRC20 cannot:
//
//   - move with no realm call at all (`gnokey maketx send`, from any wallet)
//   - ride the `-send` envelope of a call, so it can PAY for something
//   - sit beside GNOT on an account page, with nothing registered anywhere
//   - be named as the gas denom by a chain whose genesis says so
//
// # What you give up, and it is not small
//
// A native coin cannot be pulled. `banker.SendCoins` refuses any `from` that is
// not the banker's own realm address, so there is no allowance, no
// `TransferFrom`, and no way for an AMM, an escrow or a subscription to take
// what you approved. Everything downstream of `Approve` stops working the moment
// a coin becomes native. That is not a gap in this realm; it is the property
// that makes the wrapping worth doing in the other direction.
//
// And the issuer of a native coin can always delete a balance: `RemoveCoin`
// takes an arbitrary address. This realm never calls it on an address other than
// its own, [Unwrap] explains why in detail, and the gnomod.toml explains why this
// path is public rather than redeployable. Those three together are the entire
// guarantee. There is no on-chain way to prove a negative about code.
//
// # The exchange rate is 1, always
//
// One smallest unit of the underlying is one unit of the coin. Not 10^decimals:
// the bank has no notion of divisibility, so a token with 6 decimals wrapped
// here produces a coin counted in the token's own smallest units, and the 6 is
// carried to `r/moul/x/nativereg` as a display hint and nowhere else.
//
// Solvency is therefore a plain equality that anybody can check without trusting
// this realm's bookkeeping: the GRC20 balance at this realm's address equals the
// total supply of the denom. [Solvency] computes it from both sides.
//
// Play money to try it on: `r/moul/x/grc20faucet/v0`.
package nativeify

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"strings"

	"gno.land/p/moul/x/envelope/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/r/nt/grc20reg/v0"
	"gno.land/r/moul/x/nativereg/v0"
)

// Path is this realm's package path, which every denom it issues embeds.
const Path = "gno.land/r/moul/x/nativeify/v0"

// MinBase and MaxBase bound a base denom name. The chain enforces exactly this
// (`isValidBaseDenom` in the banker stdlib): a lowercase letter, then 2 to 15
// more lowercase letters or digits. Validating here rather than letting the
// banker abort is the difference between a usable error and a stack trace.
const (
	MinBase = 3
	MaxBase = 16
)

type pair struct {
	base    string // base denom name, unique in this realm
	denom   string // the full chain denom
	key     string // grc20reg key of the underlying
	creator address
	height  int64
}

var (
	byBase = avl.NewTree() // base name -> *pair
	byKey  = avl.NewTree() // grc20reg key -> *pair
	bases  []string        // creation order, for a stable Render
	home   address         // this realm's address: where every escrow sits
)

func init(cur realm) {
	home = cur.Address()
}

// Home is the address to approve on the underlying token before wrapping. Every
// escrow this realm holds sits there.
func Home() address { return home }

// Nativeify creates the native counterpart of a GRC20 registered in
// `r/nt/grc20reg`, and returns its denom. It issues nothing: [Wrap] does that.
//
// `base` is the part of the denom after the colon, yours to choose, unique in
// this realm and in the chain's charset. One native denom per underlying token:
// a second one would double the chain's per-denom storage for no new capability,
// and realm-denom balances live under their own store keys, which are not
// gas-metered.
func Nativeify(cur realm, tokenKey, base string) string {
	under := grc20reg.MustGet(tokenKey)
	assertBase(base)
	if byBase.Get(base) != nil {
		panic("this realm already issues " + base)
	}
	if v := byKey.Get(tokenKey); v != nil {
		panic(ufmt.Sprintf("%s is already native here as %s", under.GetSymbol(), v.(*pair).denom))
	}

	p := &pair{
		base:    base,
		denom:   chain.CoinDenom(Path, base),
		key:     tokenKey,
		creator: cur.Previous().Address(),
		height:  runtime.ChainHeight(),
	}
	byBase.Set(base, p)
	byKey.Set(tokenKey, p)
	bases = append(bases, base)

	// This realm is the issuer named inside the denom, so it is the only thing
	// on the chain that can describe it. The decimals travel as a display hint;
	// the bank still counts whole units.
	nativereg.Register(cross(cur), p.denom,
		under.GetName()+" (native)", "n"+under.GetSymbol(), under.GetDecimals(),
		"1:1 native wrapper of "+tokenKey+", redeemable at "+Path)
	return p.denom
}

// Wrap escrows `amount` of the underlying and issues the same number of native
// coins to the caller.
//
// You must `Approve` this realm's address on the underlying token first, through
// that token's own realm. Until you do, this realm has no authority over your
// balance at all, and Wrap fails with "insufficient allowance", which is the
// system working.
func Wrap(cur realm, base string, amount int64) int64 {
	p := mustPair(base)
	if amount <= 0 {
		panic("wrap a positive amount")
	}
	who := cur.Previous().Address()

	// Last point at which nothing has moved.
	under := grc20reg.MustGet(p.key)
	if err := under.RealmTeller(0, cur).TransferFrom(0, cur, who, home, amount); err != nil {
		panic(err)
	}
	banker.NewBanker(banker.BankerTypeRealmIssue, cur).IssueCoin(who, p.denom, amount)
	return amount
}

// Unwrap destroys the native coins attached to this call and releases the same
// number of underlying GRC20 units to the caller.
//
// # Why you have to send the coins rather than let this realm take them
//
// This realm holds a `BankerTypeRealmIssue` banker, and `RemoveCoin` takes an
// arbitrary address, so it could delete the caller's coins directly and save
// them a flag. It does not, and the reason is worth stating where somebody
// copying this will read it: a realm whose normal operation is to remove coins
// from addresses that did not hand them over has no way left to demonstrate that
// it only ever does so consensually. Every `RemoveCoin` here names this realm's
// own address, which anybody can check by reading the source, and the coins get
// to that address the only way a native coin ever moves, by their holder pushing
// them.
//
// So: attach them.
//
//	-send <amount>/gno.land/r/moul/x/nativeify/v0:<base>
func Unwrap(cur realm, base string) int64 {
	p := mustPair(base)
	// Reading the envelope is also what makes this call payable at all: MsgCall
	// rejects a message whose coins no code looked at.
	amount := envelope.Require(p.denom)
	who := cur.Previous().Address()

	// Destroy the receipt before releasing the backing, so a failure between the
	// two can only ever leave the pair over-collateralized.
	banker.NewBanker(banker.BankerTypeRealmIssue, cur).RemoveCoin(home, p.denom, amount)
	under := grc20reg.MustGet(p.key)
	if err := under.RealmTeller(0, cur).Transfer(0, cur, who, amount); err != nil {
		panic(err)
	}
	return amount
}

// Denom returns the denom this realm issues for a base name.
func Denom(base string) string { return mustPair(base).denom }

// TokenKey returns the grc20reg key of the underlying behind a base name.
func TokenKey(base string) string { return mustPair(base).key }

// Bases returns every base name this realm issues, in creation order.
func Bases() []string {
	out := make([]string, len(bases))
	copy(out, bases)
	return out
}

// Solvency returns what is escrowed and what is issued for a base name. They are
// read from two different places on the chain, the GRC20 ledger and the bank,
// and this realm's own bookkeeping is not consulted for either: if they ever
// disagree, the disagreement is the answer.
func Solvency(base string) (escrowed, issued int64) {
	p := mustPair(base)
	escrowed = grc20reg.MustGet(p.key).BalanceOf(home)
	issued = banker.NewReadonlyBanker().TotalCoin(p.denom)
	return escrowed, issued
}

// IsSolvent reports whether every coin issued for a base name is backed.
//
// It allows escrowed > issued, which is what a donation to this realm's address
// looks like and cannot hurt anybody, and refuses the reverse.
func IsSolvent(base string) bool {
	escrowed, issued := Solvency(base)
	return escrowed >= issued
}

// Underlying returns the underlying token behind a base name, for a caller that
// wants its name, symbol or decimals.
func Underlying(base string) *grc20.Token {
	return grc20reg.MustGet(mustPair(base).key)
}

func mustPair(base string) *pair {
	v := byBase.Get(base)
	if v == nil {
		panic("this realm does not issue " + base)
	}
	return v.(*pair)
}

// assertBase applies the chain's own base-denom rule before the banker does, so
// the caller reads a sentence instead of a stack trace.
func assertBase(base string) {
	if len(base) < MinBase || len(base) > MaxBase {
		panic(ufmt.Sprintf("base %q is %d characters, must be %d to %d",
			base, len(base), MinBase, MaxBase))
	}
	for i := 0; i < len(base); i++ {
		c := base[i]
		lower := c >= 'a' && c <= 'z'
		digit := c >= '0' && c <= '9'
		if lower || (i > 0 && digit) {
			continue
		}
		panic(ufmt.Sprintf("base %q: a base denom is a lowercase letter followed by "+
			"lowercase letters or digits, and %q is not", base, string(c)))
	}
	if strings.Contains(base, ":") { // unreachable past the charset loop; belt and braces
		panic("a base denom cannot contain a colon")
	}
}
