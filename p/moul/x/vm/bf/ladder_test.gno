package bf

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/uassert/v0"
)

// heavy is the benchmark program: 200 increments, then an outer loop that on
// each of its 200 iterations moves right, adds 200, clears that cell with the
// "[-]" idiom, and moves back.
//
// It writes nothing, so a measurement of it is a measurement of the dispatch
// loop and not of the output path.
var heavy = rep("+", 200) + "[" + "-" + ">" + rep("+", 200) + "[-]" + "<" + "]"

// GuestOps and NaiveDispatches are the two counts for [heavy], and the
// difference between them is the reason the ladder needs both named.
//
// A guest instruction is one operator the language executes, counted the way
// any jump-table interpreter counts it. The naive interpreter dispatches more
// often than that for the same program: its "]" handler scans back to the
// matching "[" and lands on it, so "[" is re-evaluated on every iteration of
// every loop. On heavy that is 1.33 dispatches per guest instruction.
//
// Rung 1 removes exactly that excess, so a ladder that used the naive
// dispatch count as its denominator would be crediting rung 1 twice. Both
// numbers come from an independent simulator, not from this package, so the
// denominator is not derived from the thing being measured.
const (
	GuestOps        = 121201
	NaiveDispatches = 161200
)

func rep(s string, n int) string {
	out := ""
	for i := 0; i < n; i++ {
		out += s
	}
	return out
}

// nullHost is a Host that costs as close to nothing as a Host can, so the
// ladder measures the dispatch loop rather than the storage or output path.
type nullHost struct{}

func (nullHost) Caller() address                     { return address("") }
func (nullHost) Origin() address                     { return address("") }
func (nullHost) Now() int64                          { return 0 }
func (nullHost) Height() int64                       { return 0 }
func (nullHost) Get(key []byte) []byte               { return nil }
func (nullHost) Set(key, val []byte)                 {}
func (nullHost) Input() []byte                       { return nil }
func (nullHost) Output(p []byte)                     {}
func (nullHost) Emit(typ string, kv ...string)       {}
func (nullHost) Send(to address, amount int64) error { return vmkit.ErrNotGranted }
func (nullHost) Log(msg string)                      {}

// runHeavy compiles heavy at lvl and runs it on the shipped machine,
// returning how many machine ops it executed. The count is the fuel the
// machine charged itself, so the ladder's "machine ops" column is measured by
// the machine and not counted by hand.
func runHeavy(t *testing.T, lvl Level) int64 {
	t.Helper()
	prog, err := Compile(heavy, lvl)
	uassert.NoError(t, err)
	if prog == nil {
		return 0
	}
	m := NewMachine(prog)
	used, status := m.Step(nullHost{}, vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	return used
}

// The rungs. One test each, so `gno test -print-runtime-metrics` prints one
// cycle count per rung and the README's table is a transcription rather than
// an estimate. They assert that the run completed and how many machine ops it
// took: what is being recorded is the metric line.

func TestRung0Naive(t *testing.T) {
	uassert.Equal(t, "", Execute(heavy))
}

func TestRung0Naive4x(t *testing.T) {
	for i := 0; i < 4; i++ {
		Execute(heavy)
	}
}

func TestRung1Jumps(t *testing.T) {
	uassert.Equal(t, int64(GuestOps+1), runHeavy(t, LevelJumps))
}

func TestRung2Fuse(t *testing.T) {
	uassert.True(t, runHeavy(t, LevelFuse) < GuestOps)
}

func TestRung3Idioms(t *testing.T) {
	uassert.True(t, runHeavy(t, LevelIdioms) < GuestOps)
}

func TestRung3Idioms4x(t *testing.T) {
	for i := 0; i < 4; i++ {
		runHeavy(t, LevelIdioms)
	}
}

func TestRung5Metered(t *testing.T) {
	// Same program, same rung, but every op goes through the fuel meter's
	// budget branch instead of its unmetered one. The delta against
	// TestRung3Idioms is the price of being a machine that can be stopped.
	prog, err := Compile(heavy, LevelIdioms)
	uassert.NoError(t, err)
	m := NewMachine(prog)
	_, status := m.Step(nullHost{}, 1<<40)
	uassert.Equal(t, "halted", status.String())
}

// TestLadderOpCounts records the compile-time half of the ladder: how many
// machine ops each rung executes for the same 121,201 guest instructions.
// These are the numbers the README's table quotes, asserted here so the table
// cannot silently go stale.
func TestLadderOpCounts(t *testing.T) {
	jumps := runHeavy(t, LevelJumps)
	fuse := runHeavy(t, LevelFuse)
	idioms := runHeavy(t, LevelIdioms)

	// Rung 1 executes exactly one machine op per guest instruction, plus
	// the halt: the independent simulator and this machine agree to the op.
	uassert.Equal(t, int64(121202), jumps)
	// Fusing runs of + and > collapses the two 200-long runs.
	uassert.Equal(t, int64(81203), fuse)
	// Recognizing "[-]" turns the inner clear loop into a single op.
	uassert.Equal(t, int64(1203), idioms)

	uassert.True(t, fuse < jumps)
	uassert.True(t, idioms < fuse)
}
