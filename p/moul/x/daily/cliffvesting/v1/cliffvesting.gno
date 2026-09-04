// Package cliffvesting computes cliff-then-linear vesting schedules as a PURE
// calculator — no state, no balances, no transfers.
//
// The shape is the standard employee/token grant: nothing vests until the
// cliff, the cliff releases the whole elapsed portion at once, and the rest
// accrues linearly until the end of the term. Keeping it pure is deliberate:
// the arithmetic is the part that is easy to get subtly wrong and easy to test,
// while custody belongs to the realm holding the coins.
//
// Everything is integer arithmetic. Vested is computed as
// total*elapsed/duration with the multiplication FIRST, so the usual rounding
// bug — dividing before multiplying and truncating the rate to zero — cannot
// happen. Rounding is always DOWN, which means the beneficiary never receives
// more than they have earned and the final instalment collects the remainder;
// at t >= end the result is exactly total, never total-1.
//
// Times are int64 so the caller can use block heights or unix seconds. The unit
// only has to be consistent.
//
// A live demo of this package is at
// [r/moul/x/daily/cliffvestingdemo](/r/moul/x/daily/cliffvestingdemo/v1).
package cliffvesting

import "errors"

var (
	ErrBadTotal    = errors.New("cliffvesting: total must be positive")
	ErrBadDuration = errors.New("cliffvesting: duration must be positive")
	ErrCliffAfter  = errors.New("cliffvesting: cliff must not fall after the end")
	ErrCliffBefore = errors.New("cliffvesting: cliff must not fall before the start")
)

// Schedule is a cliff-then-linear vesting plan. Construct with New so the
// invariants are checked once.
type Schedule struct {
	Total int64 // total amount to vest
	Start int64 // vesting begins
	Cliff int64 // nothing is claimable before this
	End   int64 // fully vested at or after this
}

// New validates and returns a Schedule. cliff must lie within [start, end].
// Passing cliff == start means "no cliff".
func New(total, start, cliff, end int64) (Schedule, error) {
	s := Schedule{Total: total, Start: start, Cliff: cliff, End: end}
	if total <= 0 {
		return Schedule{}, ErrBadTotal
	}
	if end <= start {
		return Schedule{}, ErrBadDuration
	}
	if cliff > end {
		return Schedule{}, ErrCliffAfter
	}
	if cliff < start {
		return Schedule{}, ErrCliffBefore
	}
	return s, nil
}

// NewLinear is New with no cliff.
func NewLinear(total, start, end int64) (Schedule, error) {
	return New(total, start, start, end)
}

// Duration returns the length of the vesting term.
func (s Schedule) Duration() int64 { return s.End - s.Start }

// HasCliff reports whether the schedule has a non-trivial cliff.
func (s Schedule) HasCliff() bool { return s.Cliff > s.Start }

// Vested returns how much has vested at time t. Zero before the cliff, exactly
// Total at or after End, and floor(total*elapsed/duration) in between.
func (s Schedule) Vested(t int64) int64 {
	if t < s.Cliff || t < s.Start {
		return 0
	}
	if t >= s.End {
		return s.Total
	}
	elapsed := t - s.Start
	// Multiply BEFORE dividing: the reverse truncates the per-tick rate to
	// zero whenever total < duration, which is the classic vesting bug.
	return s.Total * elapsed / s.Duration()
}

// Unvested returns the remainder still locked at time t.
func (s Schedule) Unvested(t int64) int64 { return s.Total - s.Vested(t) }

// Claimable returns what can be withdrawn at time t given how much has already
// been claimed. Never negative, even if claimed somehow exceeds vested.
func (s Schedule) Claimable(t, claimed int64) int64 {
	v := s.Vested(t) - claimed
	if v < 0 {
		return 0
	}
	return v
}

// IsFullyVested reports whether the term has completed at time t.
func (s Schedule) IsFullyVested(t int64) bool { return t >= s.End }

// PercentVested returns the vested share at t as an integer percentage,
// rounded down. Integer-only: no floats reach consensus state.
func (s Schedule) PercentVested(t int64) int64 {
	return s.Vested(t) * 100 / s.Total
}

// CliffAmount returns the lump sum released the instant the cliff is reached.
func (s Schedule) CliffAmount() int64 { return s.Vested(s.Cliff) }
