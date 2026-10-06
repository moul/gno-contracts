// Package patron is recurring support for a builder, on chain.
//
// A creator opens a plan with a price per period and a period measured in
// blocks. A supporter attaches ugnot to [Subscribe] and buys whole periods of
// it. Anybody can ask at any height whether a given address is still active,
// which is the one question a tip cannot answer.
//
// # There is no cron on chain, so a renewal is a pull and not a push
//
// Nothing in this realm can charge anybody. A renewal happens because the
// supporter sends another payment, never because a timer fired: there is no
// scheduler here, and there is no way to write one, since a native coin
// cannot be pulled at all. A reader arriving from web2 expects a standing
// mandate on a card and there is nothing of the kind, anywhere on this chain.
//
// # What this adds over the tip jar
//
// gno.land/r/moul/x/daily/tipjar is the one-shot version and is already live:
// one payment, a leaderboard, and then nothing. The recurrence is the whole
// difference. A plan has a price and a period, a payment buys whole periods
// of it, renewing early never discards time already paid for, and the realm
// answers "is this address active right now" at any height. It is the one app
// in the x/social family that produces a recurring write rather than a
// one-off.
//
// # Earnings are credited at payment time, not streamed
//
// The creator can withdraw the full price the instant it is paid. A supporter
// who stops being active is NOT refunded, and no part of a paid period ever
// comes back. That is a deliberate v0 limitation: escrowed streaming, where
// the creator claims only what has elapsed and the supporter cancels and
// reclaims the rest, needs a claim schedule and a refund path, and that is a
// larger realm than this one rather than a flag on it.
//
// # Money leaves by pull
//
// Both halves of what this realm owes, a creator's earnings and a supporter's
// change, land in one credit ledger and leave through [Withdraw]. The credit
// is zeroed before any coin moves, and the realm never loops over payees: one
// unpayable address would otherwise fail the whole batch and hand a griefer a
// cheap denial of service.
//
// # v0 ships no token
//
// Deliberately, and the README says why: a creator coin minted per period
// paid is easy, and the sink is not, because what it would be redeemed for is
// a promise made off chain.
package patron

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"strconv"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/x/envelope/v0"
	pt "gno.land/p/moul/x/social/patron/v0"
)

// realmPath is this realm's own path, the one its gnomod.toml module line
// declares. It is written out rather than read from the frame, because a
// plain read exported by a realm reports the CALLER and would build every
// link against whoever asked.
const realmPath = "gno.land/r/moul/x/social/patron/v0"

// denom is the only coin this realm handles.
const denom = "ugnot"

// plans holds every plan and the credit ledger. A redeploy wipes it, which is
// the trade `private = true` makes: see gnomod.toml.
var plans = pt.NewRegistry()

// Open creates a plan and returns its id. Anyone may open one, and opening
// one costs nothing beyond gas and the storage deposit.
//
// pricePerPeriod is in ugnot and must be at least one: a free plan is a tip
// jar, not a subscription. periodBlocks is a period in BLOCKS, bounded both
// ways by the engine, because height is the clock consensus agrees on and a
// block timestamp is not something to build a billing cliff out of.
func Open(cur realm, title, description string, pricePerPeriod, periodBlocks int64) int64 {
	who := caller(cur)
	id, err := plans.Open(who, title, description, pricePerPeriod, periodBlocks)
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Open",
		"id", id.String(),
		"creator", who.String(),
		"price", strconv.FormatInt(pricePerPeriod, 10),
		"period", strconv.FormatInt(periodBlocks, 10))
	return int64(id)
}

// Subscribe buys whole periods on a plan with the ugnot attached to the call,
// and returns the caller's new paid-through height.
//
// Attach the coins with -send: a payment short of one period is refused, and
// the remainder under one period is credited back to the caller rather than
// kept, so an overpayment is change and never a silent fee. Take it back with
// [Withdraw].
//
// # It has to be called directly by a user, and that is not a style choice
//
// The envelope is what the SIGNER attached to the transaction. A realm the
// user called has already received those coins itself, and could then call in
// here as many times as it liked against one payment, so the caller is
// checked before the envelope is read. The same property means a realm cannot
// forward an envelope it was handed (`NewBanker` requires the previous frame
// to be a user call), and that `maketx run` cannot reach this function at all,
// because a run script is itself a code realm. Use `maketx call -send`.
func Subscribe(cur realm, planID int64) int64 {
	// The frame is read here rather than through caller(), because this
	// function asks the previous frame two questions and the order of them is
	// the whole guard: is the token live, is the caller a user, and only then
	// what did they send.
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("patron: Subscribe must be called directly by a user with maketx call -send, " +
			"not through another realm and not from maketx run")
	}
	who := prev.Address()

	id := store.ID(planID)
	p := mustGet(id)
	if !p.Open {
		panic(pt.ErrPlanClosed.Error())
	}

	// RequireAtLeast names both numbers when the envelope falls short, which
	// is the difference between a caller fixing their command and a caller
	// opening their wallet.
	sent := envelope.RequireAtLeast(denom, p.PricePerPeriod)

	pay, err := plans.Subscribe(id, who, sent, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Subscribe",
		"id", id.String(),
		"supporter", who.String(),
		"periods", strconv.FormatInt(pay.Periods, 10),
		"spent", strconv.FormatInt(pay.Spent, 10),
		"change", strconv.FormatInt(pay.Change, 10),
		"paidThrough", strconv.FormatInt(pay.PaidThrough, 10))
	return pay.PaidThrough
}

// Close stops a plan taking new subscriptions. Creator only.
//
// Everything already paid for runs to its own paid-through height. Closing a
// plan is not a way to take a period back.
func Close(cur realm, planID int64) {
	who := caller(cur)
	id := store.ID(planID)
	if err := plans.Close(id, who); err != nil {
		panic(err.Error())
	}
	chain.Emit("Close", "id", id.String(), "by", who.String())
}

// Reopen lets a closed plan take subscriptions again. Creator only.
func Reopen(cur realm, planID int64) {
	who := caller(cur)
	id := store.ID(planID)
	if err := plans.Reopen(id, who); err != nil {
		panic(err.Error())
	}
	chain.Emit("Reopen", "id", id.String(), "by", who.String())
}

// Withdraw pays the caller everything this realm owes them and returns the
// amount: a creator's earnings, a supporter's change, or both at once.
//
// The credit is zeroed by the engine before a coin moves, so a recipient that
// calls straight back in finds nothing left to take.
func Withdraw(cur realm) int64 {
	who := caller(cur)
	amount, err := plans.Withdraw(who)
	if err != nil {
		panic(err.Error())
	}
	banker.NewBanker(banker.BankerTypeRealmSend, cur).SendCoins(
		cur.Address(), who, chain.NewCoins(chain.NewCoin(denom, amount)))
	chain.Emit("Withdraw", "to", who.String(), "amount", strconv.FormatInt(amount, 10))
	return amount
}

// Get returns a plan's fields.
//
// It returns a tuple rather than the stored record: handing out a pointer to
// realm state is a live mutation handle, and this realm is private, so an
// importer retaining one of its objects would be a runtime panic rather than
// a design debate.
func Get(planID int64) (creator address, title, description string, pricePerPeriod, periodBlocks int64, open bool) {
	p := mustGet(store.ID(planID))
	return p.Creator, p.Title, p.Description, p.PricePerPeriod, p.PeriodBlocks, p.Open
}

// Count is how many plans exist.
func Count() int { return plans.Count() }

// IsActive reports whether who is paid up on this plan at the current height.
//
// Active means now < paidThrough, strictly: an address paid through height h
// is active at h-1 and not at h.
func IsActive(planID int64, who address) bool {
	return mustGet(store.ID(planID)).IsActive(who, runtime.ChainHeight())
}

// PaidThrough is the height who stops being active at on this plan, or zero
// if they never paid.
func PaidThrough(planID int64, who address) int64 {
	return mustGet(store.ID(planID)).PaidThrough(who)
}

// SupporterCount is how many distinct addresses have ever paid this plan,
// active or not.
func SupporterCount(planID int64) int {
	return mustGet(store.ID(planID)).SupporterCount()
}

// Supporters is every address that has ever paid this plan, in first-payment
// order. It is a copy, not the stored slice.
func Supporters(planID int64) []address {
	return mustGet(store.ID(planID)).Supporters()
}

// EarnedBy is the lifetime ugnot credited to creator across every plan,
// whether or not it has been withdrawn.
func EarnedBy(creator address) int64 { return plans.EarnedBy(creator) }

// CreditOf is what addr can withdraw right now.
func CreditOf(addr address) int64 { return plans.CreditOf(addr) }

// TotalOwed is everything this realm owes, which is what it must keep in
// reserve at its own address.
func TotalOwed() int64 { return plans.TotalOwed() }

// mustGet reads a plan or aborts naming it.
func mustGet(id store.ID) *pt.Plan {
	p, ok := plans.Get(id)
	if !ok {
		panic("patron: plan #" + id.String() + " not found")
	}
	return p
}

// caller is the address that called us, checked the one way that is safe.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	return cur.Previous().Address()
}
