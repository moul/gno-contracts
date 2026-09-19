package crowdfund

import (
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestProgressBarAndPct(t *testing.T) {
	uassert.Equal(t, "░░░░░░░░░░░░░░░░░░░░", progressBar(0, 100))
	uassert.Equal(t, "▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░", progressBar(50, 100))
	uassert.Equal(t, "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓", progressBar(100, 100))
	// over-funded is capped at full width
	uassert.Equal(t, "▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓", progressBar(250, 100))
	// zero goal never divides by zero
	uassert.Equal(t, "░░░░░░░░░░░░░░░░░░░░", progressBar(10, 0))

	uassert.Equal(t, 0, pct(0, 100))
	uassert.Equal(t, 25, pct(25, 100))
	uassert.Equal(t, 100, pct(100, 100))
	uassert.Equal(t, 100, pct(500, 100)) // capped
	uassert.Equal(t, 0, pct(5, 0))       // no goal
}

func TestState(t *testing.T) {
	active := &Campaign{Goal: 100, Pledged: 10, Deadline: 100}
	uassert.Equal(t, "Active", state(active, 50))
	uassert.Equal(t, "Active", state(active, 100)) // deadline block still active

	funded := &Campaign{Goal: 100, Pledged: 150, Deadline: 100}
	uassert.Equal(t, "Funded", state(funded, 101))

	claimed := &Campaign{Goal: 100, Pledged: 150, Deadline: 100, Claimed: true}
	uassert.Equal(t, "Funded (claimed)", state(claimed, 101))

	failed := &Campaign{Goal: 100, Pledged: 50, Deadline: 100}
	uassert.Equal(t, "Failed", state(failed, 101))

	// exactly meeting the goal counts as funded
	exact := &Campaign{Goal: 100, Pledged: 100, Deadline: 100}
	uassert.Equal(t, "Funded", state(exact, 200))
}

// v0 asserted that its own key() padded to width 12. That rule held only below
// the width: key(10^12) is 13 characters and sorts before key(10^12-1), so the
// campaign list would have rendered out of order from that id on. The store key
// has no width to outgrow.
func TestKeyOrdering(t *testing.T) {
	uassert.True(t, store.ID(2).Key() < store.ID(10).Key())
	uassert.True(t, store.ID(9).Key() < store.ID(100).Key())
	uassert.True(t, store.ID(999999999999).Key() < store.ID(1000000000000).Key(),
		"and it keeps holding one past v0's width-12 ceiling")
}
