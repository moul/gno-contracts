package patron

import (
	"strings"
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

// plan opens one plan with the given price and period and returns its id,
// failing the test rather than returning an error nobody reads.
func plan(t *testing.T, r *Registry, price, period int64) store.ID {
	t.Helper()
	id, err := r.Open(alice, "a plan", "every period, forever", price, period)
	urequire.NoError(t, err)
	return id
}

// planOf reads a plan back, failing the test when it is not there.
func planOf(t *testing.T, r *Registry, id store.ID) *Plan {
	t.Helper()
	p, ok := r.Get(id)
	urequire.True(t, ok, "plan #"+id.String()+" exists")
	return p
}

func TestValidTitle(t *testing.T) {
	tests := []struct {
		name  string
		title string
		want  bool
	}{
		{"plain", "monthly support", true},
		{"markdown is allowed and escaped later", "[x](y) | z", true},
		{"at the limit", strings.Repeat("x", MaxTitleLen), true},
		{"empty", "", false},
		{"blank", "   ", false},
		{"too long", strings.Repeat("x", MaxTitleLen+1), false},
		{"a title is one line", "two\nlines", false},
		{"tab is a control character here", "a\tb", false},
		{"delete character", "a\x7fb", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidTitle(tt.title), tt.name)
	}
}

func TestValidDescription(t *testing.T) {
	tests := []struct {
		name string
		desc string
		want bool
	}{
		{"empty is fine, the title may say it all", "", true},
		{"newlines and tabs are content", "a\nb\tc", true},
		{"at the limit", strings.Repeat("x", MaxDescriptionLen), true},
		{"too long", strings.Repeat("x", MaxDescriptionLen+1), false},
		{"control character", "a\x01b", false},
		{"delete character", "a\x7fb", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidDescription(tt.desc), tt.name)
	}
}

func TestOpenRejectsWhatItCannotStore(t *testing.T) {
	tests := []struct {
		name   string
		title  string
		desc   string
		price  int64
		period int64
		want   error
	}{
		{"no title", "", "d", 100, 100, ErrBadTitle},
		{"description too long", "t", strings.Repeat("x", MaxDescriptionLen+1), 100, 100, ErrBadDescription},
		{"a free plan is a tip jar", "t", "d", 0, 100, ErrBadPrice},
		{"a negative price", "t", "d", -1, 100, ErrBadPrice},
		{"no period at all", "t", "d", 100, 0, ErrBadPeriod},
		{"under the floor", "t", "d", 100, MinPeriodBlocks - 1, ErrBadPeriod},
		{"over the ceiling", "t", "d", 100, MaxPeriodBlocks + 1, ErrBadPeriod},
	}
	r := NewRegistry()
	for _, tt := range tests {
		_, err := r.Open(alice, tt.title, tt.desc, tt.price, tt.period)
		uassert.ErrorIs(t, err, tt.want, tt.name)
	}
	uassert.Equal(t, 0, r.Count(), "nothing refused was stored")

	// The edges themselves are accepted.
	_, err := r.Open(alice, "t", "", MinPricePerPeriod, MinPeriodBlocks)
	uassert.NoError(t, err)
	_, err = r.Open(alice, "t", "", MinPricePerPeriod, MaxPeriodBlocks)
	uassert.NoError(t, err)
	uassert.Equal(t, 2, r.Count())
}

func TestOnePeriodBuysExactlyOnePeriod(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)

	pay, err := r.Subscribe(id, bob, 1000, 500)
	urequire.NoError(t, err)

	uassert.Equal(t, int64(1), pay.Periods)
	uassert.Equal(t, int64(1000), pay.Spent)
	uassert.Equal(t, int64(0), pay.Change)
	uassert.Equal(t, int64(600), pay.PaidThrough, "500 + one period of 100 blocks")
	uassert.True(t, pay.NewSupporter)

	uassert.Equal(t, int64(1000), r.CreditOf(alice), "the creator is credited at payment time")
	uassert.Equal(t, int64(1000), r.EarnedBy(alice))
	uassert.Equal(t, int64(0), r.CreditOf(bob), "an exact payment leaves no change")
	uassert.Equal(t, int64(1000), r.TotalOwed())
}

func TestThreePeriodsAtOnce(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)

	pay, err := r.Subscribe(id, bob, 3000, 500)
	urequire.NoError(t, err)

	uassert.Equal(t, int64(3), pay.Periods)
	uassert.Equal(t, int64(3000), pay.Spent)
	uassert.Equal(t, int64(0), pay.Change)
	uassert.Equal(t, int64(800), pay.PaidThrough, "three periods of 100 blocks from 500")
}

// Renewing before the current period ends adds a whole period on top of what
// is left, rather than restarting the clock and discarding it.
func TestRenewingEarlyExtendsFromPaidThrough(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)

	first, err := r.Subscribe(id, bob, 1000, 500)
	urequire.NoError(t, err)
	urequire.Equal(t, int64(600), first.PaidThrough)

	// Two blocks before the lapse, with 98 blocks still paid for.
	second, err := r.Subscribe(id, bob, 1000, 502)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(700), second.PaidThrough, "600 + 100, not 502 + 100")
	uassert.False(t, second.NewSupporter, "bob was already a supporter")
	uassert.Equal(t, 1, planOf(t, r, id).SupporterCount(), "renewing is not a second supporter")
}

// Renewing after a lapse starts from now: the gap was never paid for and
// nothing backdates it.
func TestRenewingAfterLapseStartsFromNow(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)

	_, err := r.Subscribe(id, bob, 1000, 500)
	urequire.NoError(t, err)

	// 900 is long past the 600 the first period ran to.
	second, err := r.Subscribe(id, bob, 1000, 900)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1000), second.PaidThrough, "900 + 100, the gap is not backdated")
}

// Paying exactly at the paid-through height is the boundary between the two
// rules above, and it resolves the same way either way: 600 is not later than
// 600, so the extension runs from 600.
func TestRenewingAtTheBoundary(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)

	_, err := r.Subscribe(id, bob, 1000, 500)
	urequire.NoError(t, err)
	second, err := r.Subscribe(id, bob, 1000, 600)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(700), second.PaidThrough)
}

func TestAPaymentShortOfOnePeriodIsRefused(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)

	for _, sent := range []int64{0, 1, 999} {
		_, err := r.Subscribe(id, bob, sent, 500)
		uassert.ErrorIs(t, err, ErrShortOfOnePeriod)
	}
	uassert.Equal(t, int64(0), r.CreditOf(alice), "a refused payment credits nobody")
	uassert.Equal(t, int64(0), planOf(t, r, id).PaidThrough(bob))
	uassert.Equal(t, 0, planOf(t, r, id).SupporterCount())
}

// The remainder under one period is the supporter's, not the realm's: keeping
// it would be a fee nobody agreed to.
func TestChangeIsCreditedBackAndIsWithdrawable(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)

	pay, err := r.Subscribe(id, bob, 2500, 500)
	urequire.NoError(t, err)

	uassert.Equal(t, int64(2), pay.Periods)
	uassert.Equal(t, int64(2000), pay.Spent)
	uassert.Equal(t, int64(500), pay.Change)
	uassert.Equal(t, int64(700), pay.PaidThrough)

	uassert.Equal(t, int64(500), r.CreditOf(bob), "the change is the supporter's")
	uassert.Equal(t, int64(2000), r.CreditOf(alice))
	uassert.Equal(t, int64(2500), r.TotalOwed(), "every ugnot that came in is owed to somebody")
	uassert.Equal(t, int64(0), r.EarnedBy(bob), "change is not earnings")

	got, err := r.Withdraw(bob)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(500), got)
	uassert.Equal(t, int64(0), r.CreditOf(bob))
	uassert.Equal(t, int64(2000), r.TotalOwed())
}

// Withdraw zeroes the credit before it reports it, so the second call of a
// reentrant pair finds nothing.
func TestWithdrawZeroesBeforeItPays(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)
	_, err := r.Subscribe(id, bob, 1000, 500)
	urequire.NoError(t, err)

	got, err := r.Withdraw(alice)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1000), got)

	_, err = r.Withdraw(alice)
	uassert.ErrorIs(t, err, ErrNothingToWithdraw)

	_, err = r.Withdraw(carol)
	uassert.ErrorIs(t, err, ErrNothingToWithdraw, "an address owed nothing withdraws nothing")

	uassert.Equal(t, int64(1000), r.EarnedBy(alice), "earnings outlive the withdrawal")
	uassert.Equal(t, int64(0), r.CreditOf(alice))
}

// IsActive is strict on both sides: active at paidThrough-1, not at
// paidThrough.
func TestIsActiveFlipsAtTheRightHeight(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)
	_, err := r.Subscribe(id, bob, 1000, 500)
	urequire.NoError(t, err)
	p := planOf(t, r, id)

	tests := []struct {
		name string
		now  int64
		want bool
	}{
		{"the block it was bought in", 500, true},
		{"one before the end", 599, true},
		{"the end itself", 600, false},
		{"after", 601, false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, p.IsActive(bob, tt.now), tt.name)
	}

	uassert.False(t, p.IsActive(carol, 500), "an address that never paid is never active")
	uassert.Equal(t, int64(600), p.PaidThrough(bob))
	uassert.Equal(t, int64(0), p.PaidThrough(carol))
	uassert.Equal(t, 1, p.ActiveCount(599))
	uassert.Equal(t, 0, p.ActiveCount(600))
}

func TestCloseStopsNewMoneyAndNotPaidTime(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)
	_, err := r.Subscribe(id, bob, 1000, 500)
	urequire.NoError(t, err)

	uassert.ErrorIs(t, r.Close(id, bob), ErrNotCreator)
	urequire.NoError(t, r.Close(id, alice))
	uassert.ErrorIs(t, r.Close(id, alice), ErrAlreadyClosed)

	_, err = r.Subscribe(id, carol, 1000, 501)
	uassert.ErrorIs(t, err, ErrPlanClosed)

	p := planOf(t, r, id)
	uassert.False(t, p.Open)
	uassert.True(t, p.IsActive(bob, 599), "a closed plan does not take back a paid period")

	uassert.ErrorIs(t, r.Reopen(id, bob), ErrNotCreator)
	urequire.NoError(t, r.Reopen(id, alice))
	uassert.ErrorIs(t, r.Reopen(id, alice), ErrAlreadyOpen)

	_, err = r.Subscribe(id, carol, 1000, 501)
	uassert.NoError(t, err)
}

func TestNothingWorksOnAPlanThatIsNotThere(t *testing.T) {
	r := NewRegistry()
	_, err := r.Subscribe(4242, bob, 1000, 500)
	uassert.ErrorIs(t, err, ErrNoPlan)
	uassert.ErrorIs(t, r.Close(4242, alice), ErrNoPlan)
	uassert.ErrorIs(t, r.Reopen(4242, alice), ErrNoPlan)

	_, ok := r.Get(4242)
	uassert.False(t, ok)
}

func TestOnePaymentCannotBuyUnboundedTime(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1, MaxPeriodBlocks)

	_, err := r.Subscribe(id, bob, MaxPeriodsPerPayment+1, 500)
	uassert.ErrorIs(t, err, ErrTooManyPeriods)
	uassert.Equal(t, int64(0), planOf(t, r, id).PaidThrough(bob))

	// The ceiling itself is accepted, and the product is the one place the
	// naive arithmetic would have wrapped.
	pay, err := r.Subscribe(id, bob, MaxPeriodsPerPayment, 500)
	urequire.NoError(t, err)
	uassert.Equal(t, 500+MaxPeriodsPerPayment*MaxPeriodBlocks, pay.PaidThrough)
}

func TestSupportersAreDistinctAndInFirstPaymentOrder(t *testing.T) {
	r := NewRegistry()
	id := plan(t, r, 1000, 100)

	_, err := r.Subscribe(id, carol, 1000, 500)
	urequire.NoError(t, err)
	_, err = r.Subscribe(id, bob, 1000, 501)
	urequire.NoError(t, err)
	_, err = r.Subscribe(id, carol, 1000, 502)
	urequire.NoError(t, err)

	p := planOf(t, r, id)
	got := p.Supporters()
	urequire.Equal(t, 2, len(got))
	uassert.Equal(t, carol.String(), got[0].String(), "first payment wins the first slot")
	uassert.Equal(t, bob.String(), got[1].String())
	uassert.Equal(t, 2, p.SupporterCount())

	// The slice handed out is a copy: writing to it cannot reach the plan.
	got[0] = bob
	uassert.Equal(t, carol.String(), p.Supporters()[0].String())
}

func TestEarningsAccumulateAcrossPlansAndSupporters(t *testing.T) {
	r := NewRegistry()
	first := plan(t, r, 1000, 100)
	second := plan(t, r, 2000, 200)

	_, err := r.Subscribe(first, bob, 1000, 500)
	urequire.NoError(t, err)
	_, err = r.Subscribe(second, carol, 4000, 500)
	urequire.NoError(t, err)

	uassert.Equal(t, int64(5000), r.EarnedBy(alice))
	uassert.Equal(t, int64(5000), r.CreditOf(alice))
	uassert.Equal(t, int64(1000), planOf(t, r, first).Received)
	uassert.Equal(t, int64(4000), planOf(t, r, second).Received)
	uassert.Equal(t, 2, r.Count())
}

func TestListIsNewestFirst(t *testing.T) {
	r := NewRegistry()
	first := plan(t, r, 1000, 100)
	second := plan(t, r, 1000, 100)
	third := plan(t, r, 1000, 100)

	got := r.List(1, 10)
	urequire.Equal(t, 3, len(got))
	uassert.Equal(t, uint64(third), uint64(got[0].ID))
	uassert.Equal(t, uint64(second), uint64(got[1].ID))
	uassert.Equal(t, uint64(first), uint64(got[2].ID))
	uassert.Equal(t, 2, r.Pages(2))
	uassert.Equal(t, 0, len(r.List(9, 10)))
}

func TestURLsStripTheChainDomain(t *testing.T) {
	uassert.Equal(t, "/r/moul/x/social/patron/v0", RealmURL("gno.land/r/moul/x/social/patron/v0"))
	uassert.Equal(t, "/r/a/b:plan/7", PlanURL("gno.land/r/a/b", 7))
}
