package accrual

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func mustNew(t *testing.T, amount, period, capacity int64) Rate {
	t.Helper()
	r, err := New(amount, period, capacity)
	uassert.NoError(t, err)
	return r
}

func TestNewValidation(t *testing.T) {
	cases := []struct {
		name                     string
		amount, period, capacity int64
		want                     error
	}{
		{"zero amount", 0, 60, 100, ErrBadAmount},
		{"negative amount", -1, 60, 100, ErrBadAmount},
		{"zero period", 1, 0, 100, ErrBadPeriod},
		{"negative period", 1, -60, 100, ErrBadPeriod},
		{"negative cap", 1, 60, -1, ErrBadCap},
		{"zero cap is unbounded", 1, 60, 0, nil},
		{"all positive", 5, 60, 100, nil},
	}
	for _, tc := range cases {
		_, err := New(tc.amount, tc.period, tc.capacity)
		if tc.want == nil {
			uassert.NoError(t, err, tc.name)
			continue
		}
		uassert.ErrorIs(t, err, tc.want, tc.name)
	}
}

func TestAdvance(t *testing.T) {
	cases := []struct {
		name                     string
		amount, period, capacity int64
		stock, anchor, now       int64
		wantStock, wantAnchor    int64
	}{
		{"nothing elapsed", 1, 60, 0, 0, 1000, 1000, 0, 1000},
		{"less than one period", 1, 60, 0, 0, 1000, 1059, 0, 1000},
		{"exactly one period", 1, 60, 0, 0, 1000, 1060, 1, 1060},
		{"one period and change keeps the change", 1, 60, 0, 0, 1000, 1119, 1, 1060},
		{"ten periods", 3, 60, 0, 0, 1000, 1600, 30, 1600},
		{"adds to what was held", 3, 60, 0, 7, 1000, 1600, 37, 1600},
		{"saturates at the cap", 1, 60, 10, 0, 1000, 9000, 10, 8980},
		{"already full produces nothing", 1, 60, 10, 10, 1000, 9000, 10, 8980},
		{"over the cap is left alone", 1, 60, 10, 25, 1000, 9000, 25, 8980},
		{"uncapped keeps going", 1, 60, 0, 0, 0, 604800, 10080, 604800},
	}
	for _, tc := range cases {
		r := mustNew(t, tc.amount, tc.period, tc.capacity)
		gotStock, gotAnchor, err := r.Advance(tc.stock, tc.anchor, tc.now)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.wantStock, gotStock, tc.name+": stock")
		uassert.Equal(t, tc.wantAnchor, gotAnchor, tc.name+": anchor")
	}
}

// TestAnchorKeepsTheRemainder pins the one decision the whole package rests
// on: the new anchor is not now. Advancing to a time halfway through a period
// leaves that half on the clock, which is what makes splitting free.
func TestAnchorKeepsTheRemainder(t *testing.T) {
	r := mustNew(t, 1, 60, 0)
	_, anchor, err := r.Advance(0, 0, 599)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(540), anchor, "anchor must stop at the last whole period, not at now")
}

// TestSplitInvariant is the contract of this package:
//
//	Advance(s, a, c) == Advance(Advance(s, a, b), b, c)
//
// It runs over pseudo-random partitions rather than hand-picked ones, because
// an implementation that re-anchors to now passes every round span and only
// fails on the ones that land mid-period. The generator is a fixed LCG, so a
// failure is reproducible.
func TestSplitInvariant(t *testing.T) {
	rates := []Rate{
		mustNew(t, 1, 60, 0),      // one a minute, unbounded
		mustNew(t, 7, 13, 0),      // coprime, so remainders never line up
		mustNew(t, 1, 60, 500),    // capped
		mustNew(t, 250, 3600, 0),  // coarse period
		mustNew(t, 1, 1, 0),       // degenerate: every tick pays
		mustNew(t, 3, 1000, 1234), // capped and coarse
	}

	seed := uint64(0x9E3779B97F4A7C15)
	next := func(n int64) int64 {
		seed = seed*6364136223846793005 + 1442695040888963407
		return int64(seed>>33) % n
	}

	for _, r := range rates {
		for i := 0; i < 400; i++ {
			start := next(10000)
			span := next(100000)
			stock := next(600)
			end := start + span

			wantStock, wantAnchor, err := r.Advance(stock, start, end)
			uassert.NoError(t, err)

			// Cut the span into between one and six pieces and walk them.
			cuts := next(6) + 1
			gotStock, gotAnchor := stock, start
			at := start
			for c := int64(0); c < cuts; c++ {
				remaining := end - at
				if remaining <= 0 {
					break
				}
				step := next(remaining + 1)
				if c == cuts-1 {
					step = remaining
				}
				at += step
				gotStock, gotAnchor, err = r.Advance(gotStock, gotAnchor, at)
				uassert.NoError(t, err)
			}
			// Land on the end whatever the cuts did.
			gotStock, gotAnchor, err = r.Advance(gotStock, gotAnchor, end)
			uassert.NoError(t, err)

			uassert.Equal(t, wantStock, gotStock, "split stock diverged")
			uassert.Equal(t, wantAnchor, gotAnchor, "split anchor diverged")
		}
	}
}

// TestClaimingEveryTickIsNotFree is the regression for the bug this package
// exists to make unrepresentable. r/moul/x/daily/tamagotchi truncated its
// per-call decay, so acting every tick cost nothing and acting rarely cost
// everything. Here the two agree exactly.
func TestClaimingEveryTickIsNotFree(t *testing.T) {
	r := mustNew(t, 1, 60, 0)
	const span = 6000 // 100 whole periods

	oneShot, _, err := r.Advance(0, 0, span)
	uassert.NoError(t, err)

	for _, cadence := range []int64{1, 2, 7, 60, 61, 599, 3000} {
		stock, anchor := int64(0), int64(0)
		for at := cadence; at <= span; at += cadence {
			stock, anchor, err = r.Advance(stock, anchor, at)
			uassert.NoError(t, err)
		}
		stock, _, err = r.Advance(stock, anchor, span)
		uassert.NoError(t, err)
		uassert.Equal(t, oneShot, stock, "cadence changed the payout")
	}
}

// TestAtMatchesAdvance pins that the read path cannot drift from the write
// path, which was the second and quieter half of the tamagotchi bug.
func TestAtMatchesAdvance(t *testing.T) {
	r := mustNew(t, 5, 17, 900)
	for now := int64(3); now < 4000; now += 37 {
		want, _, err := r.Advance(11, 3, now)
		uassert.NoError(t, err)
		got, err := r.At(11, 3, now)
		uassert.NoError(t, err)
		uassert.Equal(t, want, got, "At diverged from Advance")
	}
}

func TestAdvanceRejects(t *testing.T) {
	r := mustNew(t, 1, 60, 0)

	_, _, err := r.Advance(-1, 0, 100)
	uassert.ErrorIs(t, err, ErrNegativeStock)

	_, _, err = r.Advance(0, 100, 99)
	uassert.ErrorIs(t, err, ErrBackwards)

	// A Rate built by literal instead of New is still checked.
	_, _, err = Rate{}.Advance(0, 0, 100)
	uassert.ErrorIs(t, err, ErrBadAmount)
	_, _, err = Rate{Amount: 1}.Advance(0, 0, 100)
	uassert.ErrorIs(t, err, ErrBadPeriod)
	_, _, err = Rate{Amount: 1, Period: 1, Cap: -1}.Advance(0, 0, 100)
	uassert.ErrorIs(t, err, ErrBadCap)
}

func TestAdvanceOverflow(t *testing.T) {
	// An uncapped rate that would pass int64 refuses rather than wrapping
	// into a negative stock, which is how a large vesting grant once
	// reported a negative balance.
	r := mustNew(t, maxInt64/2, 1, 0)
	_, _, err := r.Advance(0, 0, 100)
	uassert.ErrorIs(t, err, ErrOverflow)

	// The same rate with a cap always has an answer, so it gives one
	// instead of an error, whichever of the two guards it trips.
	capped := mustNew(t, maxInt64/2, 1, 1000)
	got, anchor, err := capped.Advance(0, 0, 100)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(1000), got)
	uassert.Equal(t, int64(100), anchor, "a saturated advance still moves the anchor")

	got, _, err = capped.Advance(999, 0, 1)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(1000), got, "the sum guard saturates too")

	// A negative anchor far enough below now wraps the elapsed span itself.
	slow := mustNew(t, 1, maxInt64, 0)
	_, _, err = slow.Advance(0, -10, maxInt64-5)
	uassert.ErrorIs(t, err, ErrOverflow)
}

func TestFull(t *testing.T) {
	cases := []struct {
		name                     string
		amount, period, capacity int64
		stock, anchor            int64
		want                     int64
	}{
		{"uncapped never fills", 1, 60, 0, 0, 1000, 0},
		{"already full is now", 1, 60, 10, 10, 1000, 1000},
		{"past full is now", 1, 60, 10, 99, 1000, 1000},
		{"empty takes the whole cap", 1, 60, 10, 0, 1000, 1600},
		{"partly full takes the rest", 1, 60, 10, 4, 1000, 1360},
		{"rounds up to the payout that crosses", 3, 60, 10, 0, 0, 240},
		{"exact division does not round up", 5, 60, 10, 0, 0, 120},
	}
	for _, tc := range cases {
		r := mustNew(t, tc.amount, tc.period, tc.capacity)
		got, err := r.Full(tc.stock, tc.anchor)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

// TestFullAgreesWithAdvance checks the two halves of the API against each
// other: at the time Full names, the stock is at the cap, and one period
// earlier it is not.
func TestFullAgreesWithAdvance(t *testing.T) {
	for _, r := range []Rate{
		mustNew(t, 1, 60, 10),
		mustNew(t, 3, 60, 10),
		mustNew(t, 7, 13, 1000),
		mustNew(t, 250, 3600, 875),
	} {
		full, err := r.Full(0, 0)
		uassert.NoError(t, err)

		atFull, err := r.At(0, 0, full)
		uassert.NoError(t, err)
		uassert.Equal(t, r.Cap, atFull, "not full at the time Full named")

		before, err := r.At(0, 0, full-r.Period)
		uassert.NoError(t, err)
		if before >= r.Cap {
			t.Errorf("already full a period early: %d >= %d", before, r.Cap)
		}
	}
}

func TestFullRejects(t *testing.T) {
	r := mustNew(t, 1, 60, 10)
	_, err := r.Full(-1, 0)
	uassert.ErrorIs(t, err, ErrNegativeStock)

	_, err = Rate{}.Full(0, 0)
	uassert.ErrorIs(t, err, ErrBadAmount)

	far := mustNew(t, 1, maxInt64/2, 1000)
	_, err = far.Full(0, 0)
	uassert.ErrorIs(t, err, ErrOverflow)
}
