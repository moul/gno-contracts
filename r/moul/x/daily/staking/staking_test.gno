package staking

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestComputeRewardPerToken(t *testing.T) {
	// No stakers: accumulator is frozen at its stored value.
	uassert.Equal(t, uint64(42), computeRewardPerToken(42, 100, 10, 0))

	// rate=100, elapsed=2, total=200, precision=1e6 => 100*2*1e6/200 = 1e6.
	uassert.Equal(t, precision, computeRewardPerToken(0, 100, 2, 200))

	// Accumulation builds on the stored value.
	uassert.Equal(t, 2*precision, computeRewardPerToken(precision, 100, 2, 200))
}

func TestComputeEarned(t *testing.T) {
	// balance=50, delta=precision => 50*1e6/1e6 = 50.
	uassert.Equal(t, uint64(50), computeEarned(50, precision, 0, 0))

	// Prior accrual is added on top.
	uassert.Equal(t, uint64(57), computeEarned(50, precision, 0, 7))

	// Only the un-paid portion of the accumulator counts.
	uassert.Equal(t, uint64(50), computeEarned(50, 3*precision, 2*precision, 0))

	// Zero stake earns only what was already accrued.
	uassert.Equal(t, uint64(9), computeEarned(0, 5*precision, 0, 9))
}
