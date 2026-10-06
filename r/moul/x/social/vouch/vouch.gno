// Package vouch is a web of trust other realms can gate on: one address
// vouches for another, in writing, optionally with GNOT locked behind it.
//
// The one call that matters is a plain read:
//
//	import "gno.land/r/moul/x/social/vouch/v0"
//
//	func Claim(cur realm) {
//		if !vouch.IsTrusted(cur.Previous().Address(), 2) {
//			panic("get two people to vouch for you first")
//		}
//		…
//	}
//
// [IsTrusted] takes no cur realm on purpose. A read with no realm token is
// borrowed: gno opens no realm frame for it, so it costs the caller nothing
// beyond the read and cannot be tricked into acting as anybody. Nothing here
// branches on who is asking, and no read in this realm ever will: the answer
// to "is this address trusted" must not depend on who wants to know.
//
// # What it does, and what it refuses to do
//
// [Vouch] is payable. Any coins sent with it are locked as a bond on that
// vouch, which is the voucher putting their own money where their claim is. A
// bond is optional and zero is the ordinary case. [Revoke] takes the vouch
// back and credits the bond to the voucher, who collects it with [Withdraw].
//
// There is no slashing in v0 and that is the interesting half. Slashing needs
// an arbiter, somebody who decides a vouch was a lie, and every candidate is
// a design question rather than a feature: a DAO vote is a popularity contest,
// a challenge market pays whoever is loudest, an oracle is one key that can
// confiscate anybody's money. The bond is still worth having without it,
// because an illiquid deposit is a cost a hundred throwaway addresses cannot
// all pay at once.
//
// # No token
//
// This realm issues none, deliberately. A transferable vouch is a bought
// reputation, and the moment a vouch can be sold the score stops measuring
// what it says it measures. The bond is GNOT: value at risk, without being a
// market in trust itself. The README says what would change the answer.
package vouch

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"strconv"

	"gno.land/p/moul/x/envelope/v0"
	vo "gno.land/p/moul/x/social/vouch/v0"
)

// realmPath is this realm's own path, the one its gnomod.toml module line
// declares. It is written out rather than read from the frame, because every
// read this realm exports is borrowed and would report whichever realm called
// it, building every link against somebody else's page.
const realmPath = "gno.land/r/moul/x/social/vouch/v0"

// denom is the only coin a bond can be posted in.
const denom = "ugnot"

// BoardSize is how many addresses the index page ranks.
const BoardSize = 10

// graph holds every vouch and the refund ledger. A redeploy would wipe it
// while leaving the bonded coins at this address, which is why this realm is
// not private (see gnomod.toml).
var graph = vo.NewGraph()

// Vouch records that the caller stands behind target, for the stated reason.
//
// It is payable: coins sent with the call are locked as a bond on this vouch
// and are returned by [Revoke], never by anything else. Sending nothing is
// fine and is the ordinary case.
//
// Vouching again for the same address UPDATES the reason and ADDS to the
// bond. It does not count twice: the score this realm exists to publish is a
// count of people, so a second transaction from the same address buys
// precisely nothing. Vouching for yourself is refused.
func Vouch(cur realm, target address, reason string) {
	who, userCall := caller(cur)
	bond := bondOf(userCall)

	updated, err := graph.Record(who, target, reason, bond, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	event := "Vouch"
	if updated {
		event = "Revouch"
	}
	chain.Emit(event, "from", who.String(), "for", target.String(),
		"bond", strconv.FormatInt(bond, 10))
}

// Revoke withdraws the caller's vouch for target and credits any bond back to
// them. The coins do not move here: call [Withdraw] to collect them.
//
// Splitting it in two is the pull-payment pattern. A realm that sent on revoke
// would be handing control to the recipient in the middle of its own state
// change, and a recipient that refuses the coins could make revoking
// impossible.
func Revoke(cur realm, target address) int64 {
	who, _ := caller(cur)
	refund, err := graph.Revoke(who, target)
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Revoke", "from", who.String(), "for", target.String(),
		"refund", strconv.FormatInt(refund, 10))
	return refund
}

// Withdraw pays the caller every bond their revoked vouches freed, and
// returns the amount sent.
//
// The credit is zeroed before the coins leave, so a recipient that calls
// straight back in finds nothing to take.
func Withdraw(cur realm) int64 {
	who, _ := caller(cur)
	amount, err := graph.Withdraw(who)
	if err != nil {
		panic(err.Error())
	}
	bnk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bnk.SendCoins(cur.Address(), who, chain.NewCoins(chain.NewCoin(denom, amount)))
	chain.Emit("Withdraw", "to", who.String(), "amount", strconv.FormatInt(amount, 10))
	return amount
}

// IsTrusted reports whether addr is vouched for by at least min distinct
// addresses. This is the gate, and it is one line at the call site.
//
// A min below one is read as one: a gate that lets everybody through is a bug
// in the caller rather than an answer this realm will agree to.
//
// It cannot tell you that the vouchers are distinct people. Two addresses
// vouching for each other both reach a score of one, which [Mutual] exposes
// and which is the reason to ask for more than one.
func IsTrusted(addr address, min int) bool { return graph.IsTrusted(addr, min) }

// ScoreOf is how many distinct addresses vouch for addr.
func ScoreOf(addr address) int { return graph.ScoreOf(addr) }

// BondedFor is the total ugnot locked on addr by everyone vouching for them.
func BondedFor(addr address) int64 { return graph.BondedFor(addr) }

// VouchedBy is every address that vouches for addr, sorted.
func VouchedBy(addr address) []address { return graph.VouchedBy(addr) }

// VouchesOf is every address addr vouches for, sorted.
func VouchesOf(addr address) []address { return graph.VouchesOf(addr) }

// Mutual reports whether a and b vouch for each other, which is the cheapest
// sybil shape and therefore worth discounting.
func Mutual(a, b address) bool { return graph.Mutual(a, b) }

// ReasonFrom is what from wrote about target, or the empty string. It is raw
// caller text: escape it before rendering it anywhere.
func ReasonFrom(from, target address) string { return graph.ReasonFrom(from, target) }

// BondFrom is what from locked on target, or zero.
func BondFrom(from, target address) int64 { return graph.BondFrom(from, target) }

// Count is how many vouches exist.
func Count() int { return graph.Count() }

// People is how many addresses have at least one vouch for them.
func People() int { return graph.People() }

// Owed is what addr can collect with [Withdraw].
func Owed(addr address) int64 { return graph.Owed(addr) }

// TotalBonded is everything locked on vouches that still stand.
func TotalBonded() int64 { return graph.TotalBonded() }

// TotalOwed is every revoked bond nobody has collected yet. This realm holds
// TotalBonded plus TotalOwed on behalf of other people.
func TotalOwed() int64 { return graph.TotalOwed() }

// Badge is the one-line trust mark for addr, for a host realm that wants to
// show what its gate just read. Like [IsTrusted] it is a borrowed read and
// takes no realm token.
func Badge(addr address) string {
	return vo.Badge(realmPath, addr, graph.ScoreOf(addr), graph.BondedFor(addr))
}

// bondOf reads the coins attached to this call, and only when the chain
// credited them to THIS realm.
//
// The envelope is the transaction's, not the frame's: a realm that was itself
// paid and then calls here would report coins sitting at its own address, and
// crediting them would let it bond money this realm never received. A realm
// may vouch, with no bond; a realm may not vouch while holding somebody's
// payment, and saying so loudly beats silently reading the bond as zero.
//
// It takes the answer rather than the frame because a realm argument in this
// package must be named cur, which would make this a crossing function.
func bondOf(userCall bool) int64 {
	if userCall {
		return envelope.Amount(denom)
	}
	if !envelope.IsEmpty() {
		panic("a realm cannot forward a bond: those coins were credited to the realm the user paid, not to this one")
	}
	return 0
}

// caller is the address that called us, checked the one way that is safe,
// plus whether it reached us as a direct user transaction.
//
// Both come from here so the realm reads cur.Previous() in exactly one place,
// the one guarded by cur.IsCurrent().
func caller(cur realm) (who address, userCall bool) {
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	prev := cur.Previous()
	return prev.Address(), prev.IsUserCall()
}
