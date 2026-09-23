// Package vesting computes a gno.land account's vesting curve, as a PURE
// calculator: no state, no balances, no transfers.
//
// It is not a vesting scheme of its own. It is a faithful reimplementation of
// the one the CHAIN enforces, tm2's std.VestingSchedule, so that a realm can
// answer "how much of this balance can actually move right now" with the same
// arithmetic the ante handler uses. Divergence here is worse than useless, so
// every rule below is copied from tm2/pkg/std/vesting.go rather than designed:
//
//   - Times are unix seconds, and nothing compares them against the chain's
//     clock. A schedule already over when the chain starts is valid and vests
//     everything at once.
//   - [Continuous] vests linearly between Start and End. [Delayed] is a cliff:
//     nothing before End, everything at or after it, and Start is ignored.
//   - Rounding is DOWN, always, so the account never counts as spendable a
//     ugnot the chain would refuse to move.
//   - A zero Original is "no schedule", which locks nothing.
//
// # Why this is not p/moul/x/daily/cliffvesting
//
// That package is the employee-grant shape (start, cliff, end) and multiplies
// in plain int64, which silently wraps for the amounts a chain actually holds:
// over the 63,158,400 second mainnet term, any grant above 146,036 GNOT
// overflows, and a 318,720,000 GNOT grant reports a NEGATIVE vested amount.
// tm2 reaches for math/big at exactly this point. gno has no math/big, so
// [Schedule.Vested] goes through a 128-bit intermediate instead.
//
// # What this package cannot do
//
// Find out an address's schedule. Realm code cannot read one: the VM's whole
// view of an account is banker.GetCoins, which returns the TOTAL balance with
// the locked part included, and no native exposes std.VestingSchedule. The
// schedule has to come from the caller. See gno.land/r/moul/vesting for what
// that means for a page that wants to show real numbers.
package vesting

import (
	"errors"
	"math/bits"
)

// Type selects the curve.
type Type uint8

const (
	// Continuous vests linearly from Start to End. The tm2 default.
	Continuous Type = iota
	// Delayed is a cliff: nothing vests until End, then all of it.
	Delayed
)

func (t Type) String() string {
	if t == Delayed {
		return "delayed"
	}
	return "continuous"
}

var (
	ErrNegativeOriginal = errors.New("vesting: original amount cannot be negative")
	ErrEndNotPositive   = errors.New("vesting: end time must be positive")
	ErrNegativeStart    = errors.New("vesting: start time cannot be negative")
	ErrStartAfterEnd    = errors.New("vesting: start time must be before end time")
)

// Schedule is one account's vesting plan, as the chain stores it.
type Schedule struct {
	Original int64 // the granted amount, in the smallest unit
	Start    int64 // unix seconds; ignored by Delayed
	End      int64 // unix seconds
	Type     Type
}

// New validates a schedule, applying tm2's own rules in tm2's own order.
//
// The Start >= 0 check is not cosmetic and is the reason Vested can stay in
// int64 for its subtractions: with 0 <= Start < End, neither End-Start nor
// now-Start can overflow. tm2 rejects a negative start for exactly this.
func New(original, start, end int64, typ Type) (Schedule, error) {
	s := Schedule{Original: original, Start: start, End: end, Type: typ}
	if original < 0 {
		return Schedule{}, ErrNegativeOriginal
	}
	if s.IsZero() {
		return s, nil // no schedule; the other fields do not matter
	}
	if end <= 0 {
		return Schedule{}, ErrEndNotPositive
	}
	if typ != Delayed {
		if start < 0 {
			return Schedule{}, ErrNegativeStart
		}
		if start >= end {
			return Schedule{}, ErrStartAfterEnd
		}
	}
	return s, nil
}

// IsZero reports whether there is no schedule at all, which locks nothing.
func (s Schedule) IsZero() bool { return s.Original == 0 }

// Vested returns how much of Original has vested at unix time now.
func (s Schedule) Vested(now int64) int64 {
	if s.IsZero() {
		return 0
	}
	if now >= s.End {
		return s.Original
	}
	if s.Type == Delayed {
		return 0 // a cliff vests nothing until End
	}
	if now <= s.Start {
		return 0
	}
	return mulDiv(s.Original, now-s.Start, s.End-s.Start)
}

// Locked returns the part of Original that has not vested at unix time now.
// This is what the chain refuses to let leave the account.
func (s Schedule) Locked(now int64) int64 { return s.Original - s.Vested(now) }

// Spendable returns how much of balance can actually move at unix time now.
//
// balance is the account's TOTAL, which is what banker.GetCoins reports. The
// locked part is capped at the balance: an account that has already spent down
// to less than it still owes to the schedule has nothing spendable, not a
// negative amount. tm2 reaches the same answer by subtracting locked coins
// from the balance and refusing the transfer if the result does not cover it.
func (s Schedule) Spendable(balance, now int64) int64 {
	if balance <= 0 {
		return 0
	}
	locked := s.Locked(now)
	if locked >= balance {
		return 0
	}
	return balance - locked
}

// PermilleVested returns the vested share at now in tenths of a percent,
// rounded down, so a page can show one decimal without a float. Integer only:
// no float ever reaches consensus state.
func (s Schedule) PermilleVested(now int64) int64 {
	if s.IsZero() {
		return 1000 // nothing to vest is fully vested
	}
	return mulDiv(s.Vested(now), 1000, s.Original)
}

// RemainingSeconds returns how long until the schedule completes, zero once it
// has. Reported rather than formatted: the caller owns how a duration reads.
func (s Schedule) RemainingSeconds(now int64) int64 {
	if s.IsZero() || now >= s.End {
		return 0
	}
	return s.End - now
}

// mulDiv computes floor(a*b/den) through a 128-bit intermediate, so a product
// that leaves int64 does not wrap.
//
// Every caller here passes 0 <= b <= den with den > 0, which is what makes the
// bits.Div64 precondition hold: the quotient is then at most a, so it fits in
// 64 bits, which is exactly the hi < den that Div64 requires and panics
// without. Keep that invariant at the call site, not by checking it here.
func mulDiv(a, b, den int64) int64 {
	if a == 0 || b == 0 {
		return 0
	}
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	q, _ := bits.Div64(hi, lo, uint64(den))
	return int64(q)
}
