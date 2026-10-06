// Package crews is small-group coordination you can create in one
// transaction: three to fifteen people with a shared pot, a way to decide, and
// a way to leave with their share.
//
// It is the chain wiring for [gno.land/p/moul/x/social/crew], which holds the
// share math and the proposal state. This realm reads the caller, reads the
// coins attached to the call, asks the engine, and renders the result.
//
//	Create    pay in, and you are the crew's first member
//	Join      pay in at what a share is worth NOW, not at what it cost them
//	Fund      pay in and mint nothing, so every existing share is worth more
//	Propose   any member opens an advisory question
//	Vote      weighted by the shares you hold, changeable while it is open
//	Close     anyone, once the deadline has gone by
//	Ragequit  burn your shares, be credited your slice, leave
//	Withdraw  collect what you were credited
//
// # The shares are the token
//
// There is no second asset to issue. A share is the vote weight and the claim
// on the treasury at the same moment, minted by paying in and burned by
// leaving, so nothing about it is decorative and nobody has to be persuaded it
// is worth something. v0 keeps the shares as an internal ledger rather than one
// GRC20 per crew, because a GRC20 per crew means a realm per crew. A
// transferable share belongs in [gno.land/p/moul/x/social/coin], the sibling
// that refuses to exist until its mint rule, sink and buyer are declared; this
// realm does not import it.
//
// # The custody caveat, which is real
//
// ONE realm address holds EVERY crew's treasury, with per-crew accounting
// inside it. The chain sees one balance; which crew owns which part of it is a
// number in this realm's state. So a bug in the accounting is a bug across
// crews, not inside one: an arithmetic error that over-credits one crew's
// ragequit pays it out of another crew's money, and nothing at the bank layer
// would refuse that transfer.
//
// The fix is the instance-per-realm pattern (EFFECTIVE_GNO.md section 1.4): one
// realm per crew, each holding its own coins at its own address, with this
// package as the shared engine. That is v1. It is not v0 because deploying a
// realm per crew is a publish per crew, which is the opposite of "create it in
// one transaction", and the whole product claim here is the one transaction.
//
// # Payouts are pulled
//
// Nothing is ever pushed. A ragequit credits an internal ledger and the leaver
// calls [Withdraw] themselves, so one address that cannot be paid cannot wedge
// anybody else, and the credit is zeroed before the coins move.
package crews

import (
	"strconv"

	"chain"
	"chain/banker"
	"chain/runtime"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/x/envelope/v0"
	"gno.land/p/moul/x/social/crew/v0"
)

// realmPath is this realm's own path, the one its gnomod.toml module line
// declares. It is written out rather than read from the runtime, because every
// plain read this realm exports reports its CALLER and would build every link
// against the wrong realm.
const realmPath = "gno.land/r/moul/x/social/crews/v0"

// denom is the only coin a crew holds. ugnot and nothing else: a treasury that
// can hold several denominations needs a per-denomination share price, which is
// a different product.
const denom = "ugnot"

// IndexCrews is how many crews the index page lists.
const IndexCrews = 20

// crews holds every crew, every proposal and the credit ledger. A redeploy
// wipes it, which is the trade gnomod.toml's private = true makes: see the
// comment there.
var crews = crew.New()

// Create opens a crew and makes the caller its first member.
//
// Send ugnot with the call: the founder's shares are bought out of it at
// crew.InitialPricePerShare, and the whole amount, remainder included, becomes
// the treasury. Returns the new crew's id.
func Create(cur realm, name string) int64 {
	// Both checks have to be here and not behind a helper. cur.IsCurrent()
	// before cur.Previous() is the realm-token rule; IsUserCall before the
	// envelope read is the payment one, because the envelope reports what
	// the SIGNER attached to the transaction and not what reached this
	// realm. Without it a realm the user called keeps the coins and calls
	// in here as many times as it likes, every call reading the same send.
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	if !cur.Previous().IsUserCall() {
		panic("crews: paying in must be a direct user transaction")
	}
	who := cur.Previous().Address()
	amount := envelope.RequireAtLeast(denom, crew.InitialPricePerShare)

	id, err := crews.Create(name, who, amount, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Create",
		"crew", id.String(),
		"founder", who.String(),
		"amount", strconv.FormatInt(amount, 10),
	)
	return int64(id)
}

// Join mints the caller shares at what a share is worth right now and adds what
// they sent to the treasury. Returns the shares minted.
//
// The price is amount * totalShares / treasury, rounded down, so somebody
// joining a crew that has tripled its money pays three times what the founders
// did. Send at least ValuePerShare ugnot, or there is no whole share to mint.
func Join(cur realm, crewID int64) int64 {
	// The two guards every payable call needs; see Create.
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	if !cur.Previous().IsUserCall() {
		panic("crews: paying in must be a direct user transaction")
	}
	who := cur.Previous().Address()
	id := store.ID(crewID)
	c, ok := crews.Get(id)
	if !ok {
		panic(crew.ErrNoCrew.Error())
	}
	amount := envelope.RequireAtLeast(denom, c.PricePerShare())

	shares, err := crews.Join(id, who, amount)
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Join",
		"crew", id.String(),
		"member", who.String(),
		"amount", strconv.FormatInt(amount, 10),
		"shares", strconv.FormatInt(shares, 10),
	)
	return shares
}

// Fund adds what the caller sent to a crew's treasury and mints nothing, so
// every existing share is worth more afterwards.
//
// It is how revenue, a grant or a member topping the pot up arrives. Anyone may
// fund any crew, member or not: there is no way to refuse a transfer on this
// chain anyway, and pretending otherwise would only move the donation to a bank
// send the realm cannot account for.
func Fund(cur realm, crewID int64) int64 {
	// The two guards every payable call needs; see Create.
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	if !cur.Previous().IsUserCall() {
		panic("crews: paying in must be a direct user transaction")
	}
	who := cur.Previous().Address()
	amount := envelope.RequireAtLeast(denom, 1)

	if err := crews.Fund(store.ID(crewID), amount); err != nil {
		panic(err.Error())
	}
	chain.Emit("Fund",
		"crew", store.ID(crewID).String(),
		"from", who.String(),
		"amount", strconv.FormatInt(amount, 10),
	)
	return amount
}

// Propose opens an advisory question on a crew. Any member may propose, and it
// stays open for crew.VoteBlocks blocks. Returns the proposal's id.
//
// A proposal EXECUTES NOTHING. Passing one records that the crew agreed by
// share weight, and moves no coins, changes no membership and binds no code.
// Executing a payout is the next step and it is not in v0.
func Propose(cur realm, crewID int64, text string) int64 {
	who := caller(cur)
	pid, err := crews.Propose(store.ID(crewID), who, text, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Propose",
		"crew", store.ID(crewID).String(),
		"proposal", pid.String(),
		"author", who.String(),
	)
	return int64(pid)
}

// Vote records the caller's ballot, weighted by the shares they hold at this
// moment. One ballot per member, changeable while the proposal is open.
func Vote(cur realm, proposalID int64, yes bool) {
	who := caller(cur)
	pid := store.ID(proposalID)
	if err := crews.Vote(pid, who, yes, runtime.ChainHeight()); err != nil {
		panic(err.Error())
	}
	chain.Emit("Vote",
		"proposal", pid.String(),
		"voter", who.String(),
		"yes", strconv.FormatBool(yes),
	)
}

// Close records a proposal as passed or failed once its deadline has gone by,
// and returns which. Anyone may call it: closing is bookkeeping, not authority.
func Close(cur realm, proposalID int64) bool {
	pid := store.ID(proposalID)
	passed, err := crews.Close(pid, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Close", "proposal", pid.String(), "passed", strconv.FormatBool(passed))
	return passed
}

// Ragequit burns every share the caller holds, credits them their pro-rata
// slice of the treasury and removes them from the crew. Returns the amount
// credited, which [Withdraw] collects.
//
// Nobody has to agree. That is what makes a share mean something: the exit is
// priced by the same number that votes, and a member outvoted on everything can
// still leave with what they put in plus their part of what the crew built.
func Ragequit(cur realm, crewID int64) int64 {
	who := caller(cur)
	id := store.ID(crewID)
	shares, amount, err := crews.Ragequit(id, who)
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Ragequit",
		"crew", id.String(),
		"member", who.String(),
		"shares", strconv.FormatInt(shares, 10),
		"amount", strconv.FormatInt(amount, 10),
	)
	return amount
}

// Withdraw sends the caller everything they have been credited, and returns it.
//
// The credit is zeroed before the coins move, so a reentrant call finds nothing
// left to take. Nothing in this realm ever pushes value: one address that
// cannot be paid must not be able to wedge everybody else.
func Withdraw(cur realm) int64 {
	who := caller(cur)
	amount, err := crews.Withdraw(who)
	if err != nil {
		panic(err.Error())
	}

	bnk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bnk.SendCoins(cur.Address(), who, chain.NewCoins(chain.NewCoin(denom, amount)))

	chain.Emit("Withdraw", "payee", who.String(), "amount", strconv.FormatInt(amount, 10))
	return amount
}

// Get returns a crew's name, the height it was created at, how many members it
// has, its total shares and its treasury in ugnot.
//
// Flat values rather than the crew itself: handing out a pointer to live state
// is a mutation handle nothing checks, and a struct is not something a wallet
// can decode anyway.
func Get(crewID int64) (string, int64, int, int64, int64) {
	c, ok := crews.Get(store.ID(crewID))
	if !ok {
		return "", 0, 0, 0, 0
	}
	return c.Name, c.CreatedAt, c.MemberCount(), c.TotalShares, c.Treasury
}

// Count is how many crews exist.
func Count() int { return crews.Len() }

// SharesOf is how many shares who holds in a crew.
func SharesOf(crewID int64, who address) int64 {
	c, _ := crews.Get(store.ID(crewID))
	return c.SharesOf(who)
}

// MemberCount is how many people are in a crew.
func MemberCount(crewID int64) int {
	c, _ := crews.Get(store.ID(crewID))
	return c.MemberCount()
}

// Treasury is what a crew holds, in ugnot. The coins themselves sit at this
// realm's single address: see the package doc on custody.
func Treasury(crewID int64) int64 {
	c, _ := crews.Get(store.ID(crewID))
	if c == nil {
		return 0
	}
	return c.Treasury
}

// ValuePerShare is what one of a crew's shares is worth in ugnot, rounded down.
func ValuePerShare(crewID int64) int64 {
	c, _ := crews.Get(store.ID(crewID))
	return c.ValuePerShare()
}

// ProposalOf returns a proposal's crew, author, text, deadline and whether it
// has been closed and passed.
func ProposalOf(proposalID int64) (int64, address, string, int64, bool, bool) {
	p, ok := crews.Proposal(store.ID(proposalID))
	if !ok {
		return 0, "", "", 0, false, false
	}
	return int64(p.CrewID), p.Author, p.Text, p.Deadline, p.Closed, p.Passed
}

// Tally is a proposal's share-weighted yes and no.
func Tally(proposalID int64) (int64, int64) {
	p, ok := crews.Proposal(store.ID(proposalID))
	if !ok {
		return 0, 0
	}
	return p.Yes, p.No
}

// CreditOf is what an address can withdraw right now, in ugnot.
func CreditOf(who address) int64 { return crews.CreditOf(who) }

// TotalOwed is every outstanding credit, which is the part of this realm's
// balance that belongs to people who have already left.
func TotalOwed() int64 { return crews.TotalOwed() }

// caller is the address that called us, checked the one way that is safe.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	return cur.Previous().Address()
}
