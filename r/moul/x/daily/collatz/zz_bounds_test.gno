package collatz

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Anyone may Compute, and each new n is an entry the root page sorts: the
// leaderboard refuses a new n once it is full, and still updates an old one.
func TestLeaderboardIsBounded(cur realm, t *testing.T) {
	var added []string
	for i := 1; results.Size() < MaxResults; i++ {
		k := strconv.Itoa(1_000_000 + i)
		results.Set(k, Result{N: int64(1_000_000 + i)})
		added = append(added, k)
	}
	// One realm state per package run: leave the board as it was found.
	defer func() {
		for _, k := range added {
			results.Remove(k)
		}
	}()
	uassert.AbortsContains(t, cur, "leaderboard is full", func() { Compute(cross(cur), 999_999_937) })
	Compute(cross(cur), 1_000_001) // an n already recorded is refreshed, not refused
}
