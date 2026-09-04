package cliffvesting

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func mustNew(t *testing.T, total, start, cliff, end int64) Schedule {
	s, err := New(total, start, cliff, end)
	uassert.NoError(t, err)
	return s
}

func TestNewValidation(t *testing.T) {
	_, err := New(0, 0, 0, 100)
	uassert.ErrorIs(t, err, ErrBadTotal)
	_, err = New(-5, 0, 0, 100)
	uassert.ErrorIs(t, err, ErrBadTotal)

	_, err = New(100, 50, 50, 50)
	uassert.ErrorIs(t, err, ErrBadDuration, "end must be after start")
	_, err = New(100, 50, 50, 10)
	uassert.ErrorIs(t, err, ErrBadDuration)

	_, err = New(100, 0, 200, 100)
	uassert.ErrorIs(t, err, ErrCliffAfter)

	_, err = New(100, 50, 10, 100)
	uassert.ErrorIs(t, err, ErrCliffBefore)

	_, err = New(100, 0, 100, 100)
	uassert.NoError(t, err, "a cliff exactly at the end is allowed")
}

func TestNewLinearHasNoCliff(t *testing.T) {
	s, err := NewLinear(1000, 0, 100)
	uassert.NoError(t, err)
	uassert.False(t, s.HasCliff())
	uassert.Equal(t, int64(0), s.CliffAmount())
	uassert.Equal(t, int64(500), s.Vested(50), "linear from the start")
}

// TestNothingBeforeCliff is the defining behaviour.
func TestNothingBeforeCliff(t *testing.T) {
	s := mustNew(t, 1200, 0, 300, 1200)

	uassert.Equal(t, int64(0), s.Vested(0))
	uassert.Equal(t, int64(0), s.Vested(299), "one tick before the cliff, still nothing")
	uassert.Equal(t, int64(1200), s.Unvested(299))
}

// TestCliffReleasesElapsedPortionAtOnce pins the step, not a ramp.
func TestCliffReleasesElapsedPortionAtOnce(t *testing.T) {
	s := mustNew(t, 1200, 0, 300, 1200)

	uassert.Equal(t, int64(300), s.Vested(300), "25% of the term elapsed, released in one step")
	uassert.Equal(t, int64(300), s.CliffAmount())
	uassert.Equal(t, int64(25), s.PercentVested(300))
}

func TestLinearAfterCliff(t *testing.T) {
	s := mustNew(t, 1200, 0, 300, 1200)

	uassert.Equal(t, int64(600), s.Vested(600))
	uassert.Equal(t, int64(900), s.Vested(900))
	uassert.Equal(t, int64(1199), s.Vested(1199))
}

// TestExactlyTotalAtEnd is what rounding down must never break.
func TestExactlyTotalAtEnd(t *testing.T) {
	s := mustNew(t, 1000, 0, 0, 3) // 1000/3 does not divide evenly

	uassert.Equal(t, int64(333), s.Vested(1))
	uassert.Equal(t, int64(666), s.Vested(2))
	uassert.Equal(t, int64(1000), s.Vested(3), "the last instalment collects the remainder")
	uassert.Equal(t, int64(0), s.Unvested(3))
	uassert.Equal(t, int64(1000), s.Vested(99999), "still exactly total long after the end")
}

// TestSmallTotalLongDuration is the rounding bug this package exists to avoid:
// with total < duration, dividing before multiplying truncates the rate to 0
// and nothing ever vests.
func TestSmallTotalLongDuration(t *testing.T) {
	s := mustNew(t, 7, 0, 0, 1000)

	uassert.Equal(t, int64(0), s.Vested(100), "7*100/1000 = 0.7, floors to 0")
	uassert.Equal(t, int64(1), s.Vested(150), "7*150/1000 = 1.05, floors to 1")
	uassert.Equal(t, int64(3), s.Vested(500), "half the term, half of 7, floored")
	uassert.Equal(t, int64(7), s.Vested(1000), "and still exactly total at the end")
}

func TestVestedIsMonotonic(t *testing.T) {
	s := mustNew(t, 997, 10, 40, 310)

	prev := int64(-1)
	for tick := int64(0); tick <= 320; tick++ {
		v := s.Vested(tick)
		uassert.True(t, v >= prev, "vested must never decrease")
		uassert.True(t, v <= s.Total, "vested must never exceed total")
		prev = v
	}
}

func TestUnvestedComplementsVested(t *testing.T) {
	s := mustNew(t, 500, 0, 100, 400)
	for _, tick := range []int64{0, 99, 100, 250, 399, 400, 500} {
		uassert.Equal(t, s.Total, s.Vested(tick)+s.Unvested(tick),
			"vested + unvested must always equal total")
	}
}

func TestClaimable(t *testing.T) {
	s := mustNew(t, 1000, 0, 0, 100)

	uassert.Equal(t, int64(500), s.Claimable(50, 0))
	uassert.Equal(t, int64(300), s.Claimable(50, 200), "already-claimed is deducted")
	uassert.Equal(t, int64(0), s.Claimable(50, 500), "nothing left right now")
	uassert.Equal(t, int64(500), s.Claimable(100, 500), "the rest at the end")
}

// TestClaimableNeverNegative guards the case where bookkeeping says more was
// claimed than has vested — the caller gets 0, not a negative payout.
func TestClaimableNeverNegative(t *testing.T) {
	s := mustNew(t, 1000, 0, 0, 100)
	uassert.Equal(t, int64(0), s.Claimable(10, 999))
}

func TestPercentVested(t *testing.T) {
	s := mustNew(t, 1000, 0, 0, 100)
	uassert.Equal(t, int64(0), s.PercentVested(0))
	uassert.Equal(t, int64(50), s.PercentVested(50))
	uassert.Equal(t, int64(99), s.PercentVested(99))
	uassert.Equal(t, int64(100), s.PercentVested(100))
	uassert.Equal(t, int64(100), s.PercentVested(1000))
}

// TestNonZeroStart checks the schedule is relative to Start, not to zero.
func TestNonZeroStart(t *testing.T) {
	s := mustNew(t, 400, 1000, 1100, 1400)

	uassert.Equal(t, int64(0), s.Vested(999), "before the start")
	uassert.Equal(t, int64(0), s.Vested(1099), "before the cliff")
	uassert.Equal(t, int64(100), s.Vested(1100), "cliff: a quarter elapsed")
	uassert.Equal(t, int64(200), s.Vested(1200))
	uassert.Equal(t, int64(400), s.Vested(1400))
}

func TestDurationAndFlags(t *testing.T) {
	s := mustNew(t, 100, 10, 20, 110)
	uassert.Equal(t, int64(100), s.Duration())
	uassert.True(t, s.HasCliff())
	uassert.False(t, s.IsFullyVested(109))
	uassert.True(t, s.IsFullyVested(110))
	uassert.True(t, s.IsFullyVested(999))
}

// TestCliffAtEndIsAllOrNothing covers the degenerate schedule.
func TestCliffAtEndIsAllOrNothing(t *testing.T) {
	s := mustNew(t, 100, 0, 100, 100)
	uassert.Equal(t, int64(0), s.Vested(99))
	uassert.Equal(t, int64(100), s.Vested(100))
	uassert.Equal(t, int64(100), s.CliffAmount())
}
