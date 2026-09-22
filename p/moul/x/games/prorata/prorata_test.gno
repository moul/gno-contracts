package prorata

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func sum(xs []int64) int64 {
	t := int64(0)
	for _, x := range xs {
		t += x
	}
	return t
}

func TestSplitTable(t *testing.T) {
	cases := []struct {
		name    string
		amount  int64
		weights []int64
		want    []int64
	}{
		{"exact thirds", 99, []int64{1, 1, 1}, []int64{33, 33, 33}},
		{"one unit of dust, to the lowest index", 10, []int64{1, 1, 1}, []int64{4, 3, 3}},
		{"two units of dust", 11, []int64{1, 1, 1}, []int64{4, 4, 3}},
		{"uneven weights", 100, []int64{1, 2, 3}, []int64{17, 33, 50}},
		{"a single claimant takes it all", 7, []int64{5}, []int64{7}},
		{"zero weight is paid nothing", 10, []int64{0, 1, 1}, []int64{0, 5, 5}},
		{"zero weight is not paid dust either", 10, []int64{0, 1, 1, 1}, []int64{0, 4, 3, 3}},
		{"nothing to split", 0, []int64{3, 1}, []int64{0, 0}},
		{"amount smaller than the roster", 2, []int64{1, 1, 1, 1}, []int64{1, 1, 0, 0}},
		{"weight dominates", 1000, []int64{999, 1}, []int64{999, 1}},
	}
	for _, tc := range cases {
		got, err := Split(tc.amount, tc.weights)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, len(tc.want), len(got), tc.name)
		for i := range tc.want {
			uassert.Equal(t, tc.want[i], got[i], tc.name)
		}
	}
}

// TestSplitAlwaysSumsToTheAmount is the whole point: a split that is short by
// dust strands coins in the realm forever, and one that is over cannot be paid.
func TestSplitAlwaysSumsToTheAmount(t *testing.T) {
	weightsets := [][]int64{
		{1, 1, 1},
		{1, 2, 3, 4, 5, 6, 7},
		{7, 0, 1},
		{100, 1},
		{3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3},
		{1},
		{999983, 17, 5},
	}
	for _, ws := range weightsets {
		for amount := int64(0); amount < 60; amount++ {
			got, err := Split(amount, ws)
			uassert.NoError(t, err)
			uassert.Equal(t, amount, sum(got), "shares must sum to the amount")
		}
		for _, amount := range []int64{1000, 123457, 999999999} {
			got, err := Split(amount, ws)
			uassert.NoError(t, err)
			uassert.Equal(t, amount, sum(got))
		}
	}
}

// TestLargestRemainderWins pins the allocation rule, so a payout cannot quietly
// change to "whoever the loop paid last".
func TestLargestRemainderWins(t *testing.T) {
	// total 10, amount 4: floors are 0,0,1,1 with remainders 4,8,2,6.
	got, err := Split(4, []int64{1, 2, 3, 4})
	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), got[0], "smallest remainder, no extra unit")
	uassert.Equal(t, int64(1), got[1], "largest remainder, gets one")
	uassert.Equal(t, int64(1), got[2], "floor 1, remainder 2, gets none")
	uassert.Equal(t, int64(2), got[3], "second largest, gets the other")
	uassert.Equal(t, int64(4), sum(got))
}

func TestSplitValidation(t *testing.T) {
	_, err := Split(-1, []int64{1})
	uassert.ErrorIs(t, err, ErrNegativeAmount)

	_, err = Split(10, []int64{1, -1})
	uassert.ErrorIs(t, err, ErrNegativeWeight)

	_, err = Split(10, nil)
	uassert.ErrorIs(t, err, ErrNoWeight, "an empty roster is the caller's problem, not dust")

	_, err = Split(10, []int64{0, 0})
	uassert.ErrorIs(t, err, ErrNoWeight, "every weight zero is the same problem")
}

// TestNoOverflowOnLargePots is the second failure mode: amount*weight wraps
// negative long before either factor is anywhere near the limit.
func TestNoOverflowOnLargePots(t *testing.T) {
	// A pot of 10^18 ugnot split across weights that would overflow if
	// multiplied together first.
	pot := int64(1000000000000000000)
	got, err := Split(pot, []int64{3000000000, 1000000000})
	uassert.NoError(t, err)
	uassert.Equal(t, pot, sum(got))
	uassert.Equal(t, int64(750000000000000000), got[0])
	uassert.Equal(t, int64(250000000000000000), got[1])

	got, err = Split(maxInt64, []int64{1, 1})
	uassert.NoError(t, err)
	uassert.Equal(t, maxInt64, sum(got), "even the largest possible pot")

	_, err = Total([]int64{maxInt64, 1})
	uassert.ErrorIs(t, err, ErrOverflow, "a wrapped total makes every share nonsense")
}

func TestShare(t *testing.T) {
	got, err := Share(100, 1, 3)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(33), got, "rounded down, the remainder is Split's job")

	got, err = Share(1000000000000000000, 3000000000, 4000000000)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(750000000000000000), got)

	got, err = Share(100, 7, 3)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(100), got, "a weight above the total is clamped, never over-paid")

	_, err = Share(10, 1, 0)
	uassert.ErrorIs(t, err, ErrNoWeight)
	_, err = Share(-1, 1, 2)
	uassert.ErrorIs(t, err, ErrNegativeAmount)
	_, err = Share(10, -1, 2)
	uassert.ErrorIs(t, err, ErrNegativeWeight)
}

func TestTotal(t *testing.T) {
	got, err := Total([]int64{1, 2, 3})
	uassert.NoError(t, err)
	uassert.Equal(t, int64(6), got)

	got, err = Total(nil)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), got, "empty sums to zero; Split is what refuses it")
}
