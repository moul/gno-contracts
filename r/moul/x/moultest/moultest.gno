// Package moultest issues `moultest`, a NATIVE coin, and gives it away.
//
// Native here means the chain's own bank holds it, exactly as it holds GNOT.
// It is not a GRC20: there is no ledger in this realm's storage, no balance
// map, no Transfer function, no allowance. A realm with the right banker calls
// IssueCoin once and from that moment the coin is a first-class chain object,
// and this realm has no further say in who holds it.
//
// # What that buys, and what it costs
//
// The interesting half is what disappears. Moving moultest needs no code here
// at all: a plain bank send does it, from any wallet, with no realm call and no
// approval dance, because the transfer is a tm2 bank message rather than a
// function call. It can also RIDE a transaction: the `-send` envelope of a call
// carries it into the realm being called, which is the one thing no GRC20 can
// do, and [Tip] exists to show it. The account page of any explorer lists it
// beside GNOT with nothing registered anywhere.
//
// The half that is worse is the authority. A GRC20's mint and burn live behind
// a PrivateLedger this realm chooses to guard; a native coin's live in a banker
// minted from a realm handle, and banker.RemoveCoin takes an ARBITRARY address.
// Nothing in the chain stops the issuing realm from deleting anybody's balance
// at any time. This realm does not expose that (see [Burn], which is scoped to
// the caller and to nobody else), but "does not expose it" is the only
// protection there is, and it lasts exactly as long as the deployed code. That
// is the real asymmetry against a GRC20, not the ergonomics.
//
// There is no decimals field either, nor a name, nor a symbol: a native denom
// is a string and nothing else. 1000 moultest is a thousand moultest.
//
// # Why it is capped
//
// Free money with no ceiling is a spam vector rather than a faucet, so [Claim]
// is bounded four ways, and the caps are the point of the experiment as much as
// the coin is:
//
//   - [ClaimAmount] per call, to the CALLER only, never to an address the
//     caller names, so nobody can dust a stranger with it.
//   - [ClaimEvery] blocks of cooldown between two claims by one account.
//   - [MaxPerAccount] over that account's lifetime.
//   - [MaxSupply] over the realm's lifetime.
//
// [Burn] does not give any of it back. Issuance is counted monotonically, so
// claim-burn-claim cannot walk around the per-account cap; what burning moves
// is the circulating supply, which is why the two numbers are reported
// separately.
//
// # It is a private realm
//
// gnomod.toml declares private = true, so this path can be redeployed with
// corrected code instead of being abandoned for a v1. The price is measured
// elsewhere in this repo and applies here too: the coins survive a redeploy
// (they are bank state, held at their owners' addresses, and the denom embeds
// the package path, which does not move), and everything on this page does not.
// Claim history, caps consumed and the tip board all return to their init
// values, which would hand every account a fresh [MaxPerAccount]. For a coin
// that is worthless by construction that is an acceptable trade; it would not
// be for one that is not.
package moultest

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

const (
	// Name is the coin's base denom: the part after the colon. The chain caps
	// it at 16 lowercase characters.
	Name = "moultest"
	// Path is this realm's package path. The denom embeds it verbatim, so the
	// coin and the code are permanently the same name.
	Path = "gno.land/r/moul/x/moultest/v0"
	// Link is Path as a gnoweb route.
	Link = "/r/moul/x/moultest/v0"
)

// Denom is the full chain denom, "/" + [Path] + ":" + [Name]. This is the
// string a wallet, an explorer or a `-send` flag needs; the bank knows nothing
// about the realm behind it.
var Denom = chain.CoinDenom(Path, Name)

const (
	// ClaimAmount is issued per successful [Claim].
	ClaimAmount = int64(10_000)
	// ClaimEvery is the cooldown, in blocks, between two claims by one account.
	ClaimEvery = int64(100)
	// MaxPerAccount is the lifetime ceiling on what one address can claim here,
	// ten claims' worth. Burning does not raise it.
	MaxPerAccount = int64(100_000)
	// MaxSupply is the lifetime ceiling on what this realm can ever issue: a
	// hundred claims' worth, all told. Nothing lowers it, so the coin cannot be
	// inflated after the fact, and the experiment has an end rather than a
	// budget. A faucet meant to serve a crowd would put the ceiling somewhere
	// else; this one is meant to run out.
	MaxSupply = int64(1_000_000)

	// MaxNote is the longest tip note kept, in bytes.
	MaxNote = 120
	// MaxTips is how many tips the board shows. Older ones fall off.
	MaxTips = 20
)

type account struct {
	lastClaim int64 // block height of the most recent claim
	claims    int64 // how many times this address has claimed
	issued    int64 // lifetime total issued to it, never decremented
}

// Tip is one entry of the public board written by [Tip].
type tip struct {
	from   address
	to     address
	amount int64
	note   string
	height int64
}

var (
	accounts = avl.NewTree() // address string -> *account

	// issued and burned are counted here rather than derived from the bank:
	// TotalCoin reports what CIRCULATES, and the caps are about what was ever
	// minted. The two differ by exactly `burned`, which a test pins.
	issued int64
	burned int64

	tips []*tip // most recent last, at most MaxTips
)

// Claim issues [ClaimAmount] of moultest to the caller and returns it.
//
// It never issues to an address the caller names. That is deliberate: a faucet
// that mints to a third party is a way to spray a denom nobody asked for into
// strangers' wallets, and their account page then carries it forever.
func Claim(cur realm) int64 {
	who := caller(cur)
	a := accountOf(who)
	now := runtime.ChainHeight()

	if a.claims > 0 && now < a.lastClaim+ClaimEvery {
		panic(ufmt.Sprintf("too soon: next claim at block %d, current %d",
			a.lastClaim+ClaimEvery, now))
	}
	if a.issued+ClaimAmount > MaxPerAccount {
		panic(ufmt.Sprintf("account cap reached: %d of %d already claimed by this address",
			a.issued, MaxPerAccount))
	}
	if issued+ClaimAmount > MaxSupply {
		panic(ufmt.Sprintf("supply cap reached: %d of %d already issued",
			issued, MaxSupply))
	}

	a.lastClaim = now
	a.claims++
	a.issued += ClaimAmount
	accounts.Set(who.String(), a)
	issued += ClaimAmount

	banker.NewBanker(banker.BankerTypeRealmIssue, cur).IssueCoin(who, Denom, ClaimAmount)
	return ClaimAmount
}

// Burn destroys `amount` of the CALLER's moultest, and only the caller's.
//
// The banker this realm holds could remove coins from any address on the chain
// without asking, so the `who` here is read from the call frame and is never a
// parameter. A clawback is what an issuing realm is always able to write; the
// choice not to is made here, once, and cannot be revisited without a redeploy.
//
// Burning lowers what circulates and does not return any cap headroom: see
// [MaxPerAccount].
func Burn(cur realm, amount int64) {
	if amount <= 0 {
		panic("burn a positive amount")
	}
	who := caller(cur)
	if bal := BalanceOf(who); bal < amount {
		panic(ufmt.Sprintf("balance is %d, cannot burn %d", bal, amount))
	}

	banker.NewBanker(banker.BankerTypeRealmIssue, cur).RemoveCoin(who, Denom, amount)
	burned += amount
}

// Tip forwards the moultest attached to THIS transaction to `to`, and writes
// the note on a public board.
//
// The coin arrives in the `-send` envelope of the call, credited to this
// realm's address before a line of this function runs, and leaves through a
// BankerTypeOriginSend banker, whose whole authority is that envelope: it can
// spend what this message paid in and not one coin more, not even out of the
// realm's own balance. So the realm can route a payment it was handed while
// being structurally unable to touch anything else.
//
// A GRC20 has no equivalent. Its tokens cannot ride a message, so the same flow
// costs an Approve, then a call, then an allowance that outlives both.
//
// Anything else in the envelope (the GNOT covering a storage deposit, say) is
// left alone and stays with the realm.
func Tip(cur realm, to address, note string) int64 {
	who := caller(cur)
	if !to.IsValid() {
		panic("tip a valid address")
	}
	if to == who {
		panic("tip somebody else")
	}
	if len(note) > MaxNote {
		panic(ufmt.Sprintf("note is %d bytes, max %d", len(note), MaxNote))
	}

	amount := unsafe.OriginSend().AmountOf(Denom)
	if amount <= 0 {
		panic("attach moultest to the transaction: -send " + Denom)
	}

	b := banker.NewBanker(banker.BankerTypeOriginSend, cur)
	b.SendCoins(cur.Address(), to, chain.NewCoins(chain.NewCoin(Denom, amount)))

	tips = append(tips, &tip{
		from:   who,
		to:     to,
		amount: amount,
		note:   note,
		height: runtime.ChainHeight(),
	})
	if len(tips) > MaxTips {
		tips = tips[len(tips)-MaxTips:]
	}
	return amount
}

// BalanceOf returns what the bank holds of moultest for `who`. It reads the
// chain, not this realm: a balance this realm never saw counts the same.
func BalanceOf(who address) int64 {
	return banker.NewReadonlyBanker().GetCoin(who, Denom)
}

// Circulating returns how much moultest exists right now, from the bank.
func Circulating() int64 {
	return banker.NewReadonlyBanker().TotalCoin(Denom)
}

// Issued returns how much this realm has ever issued. It only grows, and it is
// what [MaxSupply] caps.
func Issued() int64 { return issued }

// Burned returns how much has been destroyed through [Burn].
func Burned() int64 { return burned }

// NextClaim returns the block height at which `who` may claim again, and
// whether they have ever claimed at all.
func NextClaim(who address) (int64, bool) {
	a := accounts.Get(who.String())
	if a == nil {
		return 0, false
	}
	return a.(*account).lastClaim + ClaimEvery, true
}

// ClaimedBy returns the lifetime total issued to `who` by this realm, which is
// what [MaxPerAccount] caps.
func ClaimedBy(who address) int64 {
	a := accounts.Get(who.String())
	if a == nil {
		return 0
	}
	return a.(*account).issued
}

// Accounts returns how many addresses have ever claimed.
func Accounts() int { return accounts.Size() }

func accountOf(who address) *account {
	if v := accounts.Get(who.String()); v != nil {
		return v.(*account)
	}
	return &account{}
}

// caller is the account or realm that crossed into this one.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("moultest: stale realm token")
	}
	return cur.Previous().Address()
}
