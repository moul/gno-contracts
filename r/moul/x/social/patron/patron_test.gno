package patron

import (
	"strconv"
	"strings"
	"testing"

	"chain"
	"chain/banker"
	"chain/runtime"

	pt "gno.land/p/moul/x/social/patron/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

const (
	price  = int64(1000000) // 1 GNOT per period
	period = int64(100)     // blocks
)

var (
	alice = testutils.TestAddress("alice") // the creator, throughout
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")

	realmAddr = chain.PackageAddress(realmPath)
)

// reset clears realm state. Realm globals live for the whole test binary, so
// everything a later test or the Render tests read starts here.
func reset() { plans = pt.NewRegistry() }

// pay stages a payment the way the chain does: the coins land at the realm's
// address before a line of its code runs, and OriginSend is what the crossing
// function then reads.
func pay(amount int64) {
	testing.IssueCoins(realmAddr, chain.Coins{{denom, amount}})
	testing.SetOriginSend(chain.Coins{{denom, amount}})
}

// open creates a plan as alice. SetRealm is call-frame scoped, so the account
// is switched here and then crossed from here, never from a helper that does
// not itself cross.
func open(cur realm, t *testing.T) int64 {
	t.Helper()
	testing.SetRealm(testing.NewUserRealm(alice))
	return Open(cross(cur), "monthly support", "a plan with a | pipe in it", price, period)
}

func TestOpenStoresWhatItWasGiven(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	creator, title, desc, p, blocks, isOpen := Get(id)
	uassert.Equal(t, alice.String(), creator.String())
	uassert.Equal(t, "monthly support", title)
	uassert.Equal(t, "a plan with a | pipe in it", desc)
	uassert.Equal(t, price, p)
	uassert.Equal(t, period, blocks)
	uassert.True(t, isOpen)
	uassert.Equal(t, 1, Count())
	uassert.Equal(t, 0, SupporterCount(id))
}

func TestOpenRefusesAFreePlanAndASillyPeriod(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "at least one ugnot per period", func() {
		Open(cross(cur), "free", "", 0, period)
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "period out of range", func() {
		Open(cross(cur), "instant", "", price, 0)
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "period out of range", func() {
		Open(cross(cur), "forever", "", price, pt.MaxPeriodBlocks+1)
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "title is empty", func() {
		Open(cross(cur), "   ", "", price, period)
	})
	uassert.Equal(t, 0, Count())
}

// One period, paid exactly, credited to the creator at payment time and
// withdrawable as real coins in this same test, because the bank does not
// carry over between test functions.
func TestOnePeriodIsBoughtAndTheCreatorIsPaid(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)
	start := runtime.ChainHeight()

	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	through := Subscribe(cross(cur), id)

	uassert.Equal(t, start+period, through)
	uassert.Equal(t, start+period, PaidThrough(id, bob))
	uassert.True(t, IsActive(id, bob))
	uassert.Equal(t, 1, SupporterCount(id))
	uassert.Equal(t, price, EarnedBy(alice))
	uassert.Equal(t, price, CreditOf(alice))
	uassert.Equal(t, int64(0), CreditOf(bob), "an exact payment leaves no change")
	uassert.Equal(t, price, TotalOwed())

	ro := banker.NewReadonlyBanker()
	before := ro.GetCoin(alice, denom)

	testing.SetRealm(testing.NewUserRealm(alice))
	got := Withdraw(cross(cur))

	uassert.Equal(t, price, got)
	uassert.Equal(t, price, ro.GetCoin(alice, denom)-before, "the creator was really paid")
	uassert.Equal(t, int64(0), CreditOf(alice))
	uassert.Equal(t, price, EarnedBy(alice), "earnings outlive the withdrawal")
	uassert.Equal(t, int64(0), TotalOwed())
}

func TestThreePeriodsAtOnce(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)
	start := runtime.ChainHeight()

	pay(3 * price)
	testing.SetRealm(testing.NewUserRealm(bob))
	through := Subscribe(cross(cur), id)

	uassert.Equal(t, start+3*period, through)
	uassert.Equal(t, 3*price, CreditOf(alice))
	uassert.Equal(t, int64(0), CreditOf(bob))
}

// Renewing before the lapse extends from paidThrough, so the time already
// paid for is still there afterwards.
func TestRenewingEarlyExtendsRatherThanRestarts(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	first := Subscribe(cross(cur), id)

	// Ten blocks in, with ninety still paid for.
	testing.SkipHeights(10)
	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	second := Subscribe(cross(cur), id)

	uassert.Equal(t, first+period, second, "the second period starts where the first ended")
	uassert.True(t, second > runtime.ChainHeight()+period,
		"more than one period is left, which is the point")
	uassert.Equal(t, 1, SupporterCount(id), "renewing is not a second supporter")
}

// Renewing after a lapse starts from now: the gap was never paid for.
func TestRenewingAfterALapseStartsFromNow(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	Subscribe(cross(cur), id)

	testing.SkipHeights(500)
	uassert.False(t, IsActive(id, bob), "the first period lapsed long ago")

	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	second := Subscribe(cross(cur), id)

	uassert.Equal(t, runtime.ChainHeight()+period, second)
	uassert.True(t, IsActive(id, bob))
}

// IsActive flips at the block the period ends on, and not a block either side.
func TestIsActiveFlipsAtTheRightHeight(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)
	start := runtime.ChainHeight()

	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	Subscribe(cross(cur), id)

	testing.SetHeight(start + period - 1)
	uassert.True(t, IsActive(id, bob), "the last block of the period")

	testing.SetHeight(start + period)
	uassert.False(t, IsActive(id, bob), "the first block after it")

	uassert.False(t, IsActive(id, carol), "an address that never paid is never active")
	uassert.Equal(t, int64(0), PaidThrough(id, carol))
}

func TestAPaymentShortOfOnePeriodIsRefused(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	pay(price - 1)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "this call costs at least", func() {
		Subscribe(cross(cur), id)
	})

	uassert.Equal(t, int64(0), PaidThrough(id, bob))
	uassert.Equal(t, int64(0), EarnedBy(alice))
	uassert.Equal(t, 0, SupporterCount(id))
}

// The remainder under one period is the supporter's, not the realm's, and it
// comes back out as real coins.
func TestChangeIsCreditedBackAndWithdrawable(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	pay(2*price + 250000)
	testing.SetRealm(testing.NewUserRealm(bob))
	Subscribe(cross(cur), id)

	uassert.Equal(t, int64(250000), CreditOf(bob), "the change is the supporter's")
	uassert.Equal(t, 2*price, CreditOf(alice))
	uassert.Equal(t, 2*price+250000, TotalOwed(), "every ugnot in is owed to somebody")

	ro := banker.NewReadonlyBanker()
	before := ro.GetCoin(bob, denom)

	testing.SetRealm(testing.NewUserRealm(bob))
	got := Withdraw(cross(cur))

	uassert.Equal(t, int64(250000), got)
	uassert.Equal(t, int64(250000), ro.GetCoin(bob, denom)-before)
	uassert.Equal(t, int64(0), CreditOf(bob))

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "nothing to withdraw", func() { Withdraw(cross(cur)) })
}

func TestWithdrawRefusesSomebodyOwedNothing(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "nothing to withdraw", func() { Withdraw(cross(cur)) })
}

// A realm that the user called holds the coins itself and could subscribe
// over and over against one payment. The guard runs before the envelope is
// read, so it cannot.
func TestOnlyAUserCanSubscribe(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	pay(price)
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/g1relay/forwarder"))
	uassert.AbortsContains(t, cur, "must be called directly by a user", func() {
		Subscribe(cross(cur), id)
	})
	uassert.Equal(t, int64(0), EarnedBy(alice))
}

func TestCloseAndReopenAreTheCreatorsAlone(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	Subscribe(cross(cur), id)

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only the plan's creator", func() { Close(cross(cur), id) })

	testing.SetRealm(testing.NewUserRealm(alice))
	Close(cross(cur), id)
	_, _, _, _, _, isOpen := Get(id)
	uassert.False(t, isOpen)
	uassert.True(t, IsActive(id, bob), "closing does not take back a paid period")

	pay(price)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "closed to new subscriptions", func() {
		Subscribe(cross(cur), id)
	})

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "already closed", func() { Close(cross(cur), id) })

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only the plan's creator", func() { Reopen(cross(cur), id) })

	testing.SetRealm(testing.NewUserRealm(alice))
	Reopen(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "already open", func() { Reopen(cross(cur), id) })

	pay(price)
	testing.SetRealm(testing.NewUserRealm(carol))
	Subscribe(cross(cur), id)
	uassert.Equal(t, 2, SupporterCount(id))
}

func TestAPlanThatIsNotThere(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "plan #4242 not found", func() {
		Subscribe(cross(cur), 4242)
	})
	uassert.PanicsContains(t, cur, "plan #4242 not found", func() { Count(); IsActive(4242, bob) })
}

func TestSupportersAreDistinctAndInFirstPaymentOrder(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	pay(price)
	testing.SetRealm(testing.NewUserRealm(carol))
	Subscribe(cross(cur), id)
	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	Subscribe(cross(cur), id)
	pay(price)
	testing.SetRealm(testing.NewUserRealm(carol))
	Subscribe(cross(cur), id)

	got := Supporters(id)
	urequire.Equal(t, 2, len(got))
	uassert.Equal(t, carol.String(), got[0].String())
	uassert.Equal(t, bob.String(), got[1].String())
}

// TestRender uses uassert rather than an Example because every view contains
// consecutive blank lines, which gno collapses inside an // Output: block.
func TestRender(cur realm, t *testing.T) {
	reset()

	empty := Render("")
	uassert.True(t, strings.Contains(empty, "No plans yet."), empty)
	uassert.True(t, strings.Contains(empty, "no cron on chain"), "the index says it: "+empty)

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Open(cross(cur), "a | pipe and [a link](x)", "about **everything**", price, period)

	pay(price)
	testing.SetRealm(testing.NewUserRealm(bob))
	Subscribe(cross(cur), id)

	index := Render("")
	uassert.False(t, strings.Contains(index, "| a | pipe"),
		"a raw pipe would open a column: "+index)
	uassert.True(t, strings.Contains(index, "a \\| pipe and \\[a link\\]\\(x\\)"),
		"the title is escaped once in the listing, pipe included: "+index)
	uassert.True(t, strings.Contains(index, "["+strconv.FormatInt(id, 10)+"](/r/moul/x/social/patron/v0:plan/"),
		"the link text is the plan number, which is ours and not the caller's: "+index)
	uassert.True(t, strings.Contains(index, "func=Open"), "the index offers the transaction")
	uassert.True(t, strings.Contains(index, "1 of 1"), "one active of one supporter: "+index)

	sid := strconv.FormatInt(id, 10)
	page := Render("plan/" + sid)
	uassert.True(t, strings.Contains(page, "# Plan #"+sid))
	// A heading is prose, so ui.Inline escapes the link syntax and leaves the
	// pipe alone: a pipe only means something inside a table.
	uassert.True(t, strings.Contains(page, "# Plan #"+sid+": a | pipe and \\[a link\\]\\(x\\)"),
		"the title is escaped in the heading too: "+page)
	uassert.True(t, strings.Contains(page, "about \\*\\*everything\\*\\*"),
		"the description is escaped: "+page)
	uassert.True(t, strings.Contains(page, "func=Subscribe"))
	uassert.True(t, strings.Contains(page, ".send="+strconv.FormatInt(price, 10)+"ugnot"),
		"the support link carries the price: "+page)
	uassert.True(t, strings.Contains(page, "func=Close"))

	testing.SetRealm(testing.NewUserRealm(alice))
	Close(cross(cur), id)
	closed := Render("plan/" + sid)
	uassert.True(t, strings.Contains(closed, "takes no new subscriptions"), closed)
	uassert.False(t, strings.Contains(closed, "func=Subscribe"),
		"a closed plan offers no payment: "+closed)

	uassert.Equal(t, "# Patron\nNo plan #4242", Render("plan/4242"))
	uassert.Equal(t, "# Patron\nNot a plan id: nope", Render("plan/nope"))
	uassert.True(t, strings.HasPrefix(Render("elsewhere"), "# Not found"))

	// A page past the end is an empty listing, not a panic.
	uassert.True(t, strings.Contains(Render("?page=99"), "No plans yet."))
	uassert.True(t, strings.Contains(Render("?page=nonsense"), "a \\| pipe"),
		"an unreadable page number falls back to the first")
}
