// Package curated is a list anyone can get onto by locking a deposit, and
// anyone can try to get somebody else off by matching that deposit with a bond.
// The loser of the challenge pays the winner.
//
// It is the registry member of a family of small social apps: a list is the
// thing every other one of them eventually needs, and a list is only worth
// reading if being on it cost something.
//
//	Apply(key, url, description)  -send 1000000ugnot   list it, immediately
//	Challenge(key)                -send <the deposit>  object to it
//	Vote(key, keep)                                    while the window is open
//	Resolve(key)                                       anyone, after it closes
//	Unlist(key)                                        the owner, if unchallenged
//	Withdraw()                                         collect what you won
//
// # Money in, money out
//
// Coins arrive in the envelope of a call and sit at this realm's address. They
// never leave by being pushed: a payout is a credit in a ledger and the payee
// calls [Withdraw] for their own. A realm that looped over winners and sent to
// each one would fail entirely when one of them could not be paid, and would
// hand a griefer a cheap denial of service for the price of one entry.
//
// Every ugnot here is therefore either backing a live entry or an open
// challenge, or already assigned to somebody. The realm's own tests assert
// exactly that against the chain balance.
//
// # Voting is sybil-prone, and the bonds are GNOT
//
// [Vote] is one address, one vote, unweighted, and an address is free. Read a
// resolution as "nobody with a stake objected enough", never as a verdict.
// Gating a vote on something harder to manufacture is a different problem with
// its own realm behind it, r/moul/x/social/vouch, a sibling in this family.
//
// Bonds are GNOT and not a token of this list's own: see the README on why
// that is the only answer available at v0 and what would change it.
//
// # What v0 does not do, in the order it should be fixed
//
//  1. Voters are paid nothing. Voting costs gas and returns nothing, so the
//     only two addresses with a reason to vote are the ones with money on the
//     outcome. A share of the loser's stake for the winning side is the
//     standard answer and the first thing to add.
//  2. There is no application period: [Apply] lists immediately.
//  3. A challenge cannot be withdrawn and a vote cannot be changed.
package curated

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"strconv"

	"gno.land/p/moul/x/envelope/v0"
	cu "gno.land/p/moul/x/social/curated/v0"
)

// realmPath is this realm's own path, the one its gnomod.toml module line
// declares. Render builds its links from it rather than from
// unsafe.CurrentRealm(), which in a plain read reports the CALLER.
const realmPath = "gno.land/r/moul/x/social/curated/v0"

const (
	// Denom is what a deposit and a bond are paid in. Native coins, so the
	// amounts are real to a challenger before this list is worth anything.
	Denom = "ugnot"

	// Deposit is what listing costs, and therefore also what challenging one
	// of today's entries costs. One GNOT: enough to make a thousand junk
	// entries a real expense, cheap enough that one honest entry is not a
	// decision.
	Deposit = int64(1000000)

	// ChallengeBlocks is how long a challenge takes to resolve. Long enough
	// for a reader who is not watching the chain to notice and vote, short
	// enough that an entry is not held hostage.
	ChallengeBlocks = int64(1000)
)

// list is every entry and the credit ledger behind them. A redeploy would wipe
// it while leaving the coins at the address, which is what the note in
// gnomod.toml is about.
var list = cu.New(Deposit, ChallengeBlocks)

// Apply lists an entry under key, in exchange for exactly [Deposit] ugnot.
//
// The entry is on the list the moment this returns: there is no application
// period in v0, and the check on a bad entry is that anybody can challenge it.
// The deposit comes back through [Unlist] and [Withdraw] if nobody ever does.
//
// key is a slug: lowercase ASCII letters, digits, '-', '_' and '.', starting
// alphanumeric. A key whose entry was removed is free to apply for again.
func Apply(cur realm, key, url, description string) {
	who := caller(cur)
	paid := envelope.RequireExactly(Denom, Deposit)
	if err := list.Apply(key, url, description, who, paid, runtime.ChainHeight()); err != nil {
		panic(err.Error())
	}
	chain.Emit("Apply", "key", key, "owner", who.String(),
		"deposit", strconv.FormatInt(paid, 10))
}

// Challenge objects to an entry, in exchange for a bond equal to that entry's
// own deposit, and opens a vote that closes [ChallengeBlocks] blocks later.
//
// An owner cannot challenge their own entry: it would cost them nothing and
// would make the entry immune to a real challenge for the whole window.
func Challenge(cur realm, key string) {
	who := caller(cur)
	// The bond is read before the envelope is, so somebody who attaches coins
	// to a challenge of something unchallengeable is told which of the two is
	// wrong.
	bond, ok := list.BondFor(key)
	if !ok {
		panic("curated: " + key + " is not an entry that can be challenged")
	}
	envelope.RequireExactly(Denom, bond)
	if err := list.Challenge(key, who, bond, runtime.ChainHeight()); err != nil {
		panic(err.Error())
	}
	c, _ := list.ChallengeOf(key)
	chain.Emit("Challenge", "key", key, "by", who.String(),
		"bond", strconv.FormatInt(bond, 10),
		"deadline", strconv.FormatInt(c.Deadline, 10))
}

// Vote takes a side on an open challenge: keep the entry, or remove it.
//
// One address, one vote, unweighted, and it cannot be changed. An address is
// free, so this is cheap to manufacture; see the package doc.
func Vote(cur realm, key string, keep bool) {
	who := caller(cur)
	if err := list.Vote(key, who, keep, runtime.ChainHeight()); err != nil {
		panic(err.Error())
	}
	chain.Emit("Vote", "key", key, "by", who.String(), "keep", strconv.FormatBool(keep))
}

// Resolve closes a challenge whose window has passed. Anyone may call it, so
// neither party can stall the other by sitting still.
//
// A majority of keep votes keeps the entry and credits its owner the bond.
// Otherwise the entry is removed and the challenger is credited the bond plus
// the deposit. A tie, including nobody voting at all, keeps the entry: the
// incumbent is the one already at risk, so a challenge that convinced nobody
// loses, which is what makes being wrong cost something.
func Resolve(cur realm, key string) {
	who := caller(cur)
	out, err := list.Resolve(key, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Resolve", "key", key,
		"kept", strconv.FormatBool(out.Kept),
		"winner", out.Winner.String(),
		"amount", strconv.FormatInt(out.Amount, 10),
		"keep", strconv.FormatInt(out.Keep, 10),
		"remove", strconv.FormatInt(out.Remove, 10),
		"by", who.String())
}

// Unlist takes the caller's own entry off the list and credits them the
// deposit back, which [Withdraw] then pays out.
//
// It is refused while a challenge is open: an owner who could walk away
// mid-challenge would be risking nothing, which is the one thing the deposit
// exists to prevent.
func Unlist(cur realm, key string) {
	who := caller(cur)
	if err := list.Unlist(key, who); err != nil {
		panic(err.Error())
	}
	chain.Emit("Unlist", "key", key, "owner", who.String())
}

// Withdraw pays the caller everything credited to them and returns it.
//
// This is the only way coins leave the realm. The credit is zeroed before the
// transfer, so a reentrant call finds nothing left to take.
func Withdraw(cur realm) int64 {
	who := caller(cur)
	amount, err := list.Withdraw(who)
	if err != nil {
		panic(err.Error())
	}
	bnk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bnk.SendCoins(cur.Address(), who, chain.NewCoins(chain.NewCoin(Denom, amount)))

	chain.Emit("Withdraw", "to", who.String(), "amount", strconv.FormatInt(amount, 10))
	return amount
}

// Get returns what is known about an entry: its URL, its description, its
// owner, the deposit behind it, the height it was listed at, and its state,
// which is one of "listed", "challenged" or "removed".
//
// A key that was never applied for reads as the zero value with an empty
// state, which is how a caller tells it from a removed one.
func Get(key string) (url, description string, owner address, deposit, at int64, state string) {
	e, ok := list.Get(key)
	if !ok {
		return "", "", "", 0, 0, ""
	}
	return e.URL, e.Description, e.Owner, e.Deposit, e.At, e.State.String()
}

// Count is how many entries are on the list right now. A challenged entry
// counts: a challenge is an objection, not a verdict.
func Count() int { return list.Count() }

// Listed is every key on the list, oldest first.
func Listed() []string {
	entries := list.Listed()
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.Key)
	}
	return out
}

// IsListed reports whether key is on the list right now.
func IsListed(key string) bool { return list.IsListed(key) }

// ChallengeOf returns the open challenge against key: who opened it, the bond
// they put up, the height voting closes at, the two vote counts, and whether
// there is one at all.
func ChallengeOf(key string) (challenger address, bond, deadline, keep, remove int64, open bool) {
	c, ok := list.ChallengeOf(key)
	if !ok {
		return "", 0, 0, 0, 0, false
	}
	return c.Challenger, c.Bond, c.Deadline, c.Keep, c.Remove, true
}

// CreditOf is what who can collect with [Withdraw] right now.
func CreditOf(who address) int64 { return list.CreditOf(who) }

// caller is the address that called us, checked the one way that is safe.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	return cur.Previous().Address()
}
