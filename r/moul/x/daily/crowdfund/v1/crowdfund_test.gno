package crowdfund

import (
	"testing"

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

func TestKeyOrdering(t *testing.T) {
	uassert.Equal(t, "000000000001", key(1))
	uassert.Equal(t, "000000000042", key(42))
	// zero-padded keys keep numeric order under lexical string sort
	uassert.True(t, key(2) < key(10))
	uassert.True(t, key(9) < key(100))
}
