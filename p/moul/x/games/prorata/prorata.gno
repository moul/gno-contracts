// Package prorata splits an integer amount across weighted claimants without
// leaking or inventing a unit.
//
// Every payout in a game is this operation: a pot, a roster, and a weight each.
// Written the obvious way, `amount*weight/total` per claimant, it is wrong in
// two ways that only show up with real money in the contract. The shares are
// each rounded down, so their sum is short of the amount by up to one unit per
// claimant, and that dust either accumulates in the contract forever or gets
// handed to whoever the code happens to pay last. And `amount*weight` overflows
// an int64 long before either factor does, which turns a large payout negative.
//
// Split fixes both. It distributes by largest remainder: floor every share,
// then hand the leftover units out one at a time to the claimants whose
// truncated fraction was largest, ties going to the lower index. The result
// sums to EXACTLY the amount, every time, and the rule is deterministic, so
// every node computes the same split and a Render of it does not change between
// calls.
//
// Nothing here reads the chain and nothing holds coins: the caller owns the
// roster and the custody. A game built on this package is at
// [r/moul/x/games/lastwords](/r/moul/x/games/lastwords/v0).
package prorata

import (
	"errors"
	"sort"
)

const maxInt64 = int64(9223372036854775807)

var (
	// ErrNegativeAmount is returned when the amount to split is negative.
	ErrNegativeAmount = errors.New("prorata: amount must not be negative")
	// ErrNegativeWeight is returned when any weight is negative.
	ErrNegativeWeight = errors.New("prorata: weights must not be negative")
	// ErrNoWeight is returned when there is nobody to pay, or every weight is
	// zero. The caller must decide where the amount goes instead: silently
	// returning an empty split would strand it.
	ErrNoWeight = errors.New("prorata: total weight is zero, nothing to split across")
	// ErrOverflow is returned when the arithmetic does not fit in an int64.
	ErrOverflow = errors.New("prorata: weights overflow int64")
)

// Split divides amount across weights and returns one share per weight, in the
// same order. The shares sum to exactly amount.
//
// A zero weight is allowed and receives nothing, including no remainder unit:
// somebody with no claim is not paid dust.
func Split(amount int64, weights []int64) ([]int64, error) {
	if amount < 0 {
		return nil, ErrNegativeAmount
	}
	total, err := Total(weights)
	if err != nil {
		return nil, err
	}
	if total == 0 {
		return nil, ErrNoWeight
	}

	shares := make([]int64, len(weights))
	if amount == 0 {
		return shares, nil
	}

	// Floor each share, and keep the truncated numerator to rank by.
	rems := make([]entry, 0, len(weights))
	assigned := int64(0)
	for i, w := range weights {
		if w == 0 {
			continue
		}
		share, rem, err := divide(amount, w, total)
		if err != nil {
			return nil, err
		}
		shares[i] = share
		assigned += share
		rems = append(rems, entry{index: i, rem: rem})
	}

	// Hand the leftover out by largest remainder. There are strictly fewer
	// leftover units than claimants, so one pass over the ranking is enough.
	left := amount - assigned
	if left <= 0 {
		return shares, nil
	}
	sort.Sort(byRemainder(rems))
	for i := 0; i < len(rems) && left > 0; i++ {
		shares[rems[i].index]++
		left--
	}
	return shares, nil
}

// Share returns what one weight is owed out of amount, rounded down. It is the
// "what would I get" query, and deliberately does NOT account for the
// remainder: use Split when the shares have to add up.
func Share(amount, weight, total int64) (int64, error) {
	if amount < 0 {
		return 0, ErrNegativeAmount
	}
	if weight < 0 || total < 0 {
		return 0, ErrNegativeWeight
	}
	if total == 0 {
		return 0, ErrNoWeight
	}
	if weight > total {
		weight = total
	}
	share, _, err := divide(amount, weight, total)
	return share, err
}

// Total sums weights, refusing an int64 overflow rather than wrapping into a
// negative total that would make every share nonsense.
func Total(weights []int64) (int64, error) {
	sum := int64(0)
	for _, w := range weights {
		if w < 0 {
			return 0, ErrNegativeWeight
		}
		if w > maxInt64-sum {
			return 0, ErrOverflow
		}
		sum += w
	}
	return sum, nil
}

// divide returns amount*weight/total rounded down, plus the remainder of that
// division, without ever computing amount*weight.
//
// It splits the amount into whole multiples of total and what is left over:
// amount = q*total + r, so amount*weight/total is exactly q*weight +
// r*weight/total. The first term is exact and the second multiplies a value
// already smaller than total, which is what keeps the product in range.
func divide(amount, weight, total int64) (share, rem int64, err error) {
	q := amount / total
	r := amount % total
	if weight != 0 && q > maxInt64/weight {
		return 0, 0, ErrOverflow
	}
	whole := q * weight
	if weight != 0 && r > maxInt64/weight {
		return 0, 0, ErrOverflow
	}
	part := r * weight
	if whole > maxInt64-part/total {
		return 0, 0, ErrOverflow
	}
	return whole + part/total, part % total, nil
}

// entry is one claimant's truncated fraction, for ranking the leftover.
type entry struct {
	index int
	rem   int64
}

// byRemainder ranks by largest truncated remainder, ties by lowest index, so
// the split is identical on every node.
type byRemainder []entry

func (b byRemainder) Len() int      { return len(b) }
func (b byRemainder) Swap(i, j int) { b[i], b[j] = b[j], b[i] }
func (b byRemainder) Less(i, j int) bool {
	if b[i].rem != b[j].rem {
		return b[i].rem > b[j].rem
	}
	return b[i].index < b[j].index
}
