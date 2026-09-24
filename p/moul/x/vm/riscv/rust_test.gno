package riscv

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/uassert/v0"
)

// The demo the design issue actually asked for: Rust code, compiled by rustc,
// running on gno.land, moving a balance from one account to another.
//
// The image is guests.gno's, built from tools/riscv-guests/ledger. It is worth
// more than the C guest for one reason: it links Rust's real core and
// compiler_builtins, so this exercises the standard library's own software
// arithmetic rather than only what the compiler emitted for my source.

func runLedger(t *testing.T, in string) (string, vmkit.Status, *Machine) {
	t.Helper()
	m, err := NewMachine(GuestLedger(), entry)
	uassert.NoError(t, err)
	if m == nil {
		return "", vmkit.Trapped, nil
	}
	h := vmkit.NewTestHost().WithInput([]byte(in))
	_, status := m.Step(h, 5000000)
	return string(h.Out()), status, m
}

func TestRustLedgerTransfers(t *testing.T) {
	out, status, _ := runLedger(t,
		"mint alice 100\nmint bob 50\nsend alice bob 30\n")
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, "alice 70\nbob 80\n", out)
}

func TestRustLedgerMintBurnAndBlankLines(t *testing.T) {
	out, status, _ := runLedger(t, "mint a 5\n\n   \nburn a 2\n")
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, "a 3\n", out)

	out, status, _ = runLedger(t, "")
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, "", out)
}

// A refusal is halted, not trapped, and it names the line. This is the
// semantic the whole VM is built around: the program said no, the machine did
// not break, and a chain has to be able to tell a user which one happened.
func TestRustLedgerRefusalsAreHaltsNotTraps(t *testing.T) {
	cases := []struct{ in, want string }{
		{"mint a 1\nsend a b 9\n", "line 2: insufficient balance\n"},
		{"send nobody b 1\n", "line 1: unknown sender\n"},
		{"burn ghost 1\n", "line 1: unknown account\n"},
		{"frobnicate\n", "line 1: unknown command\n"},
		{"mint a x\n", "line 1: bad amount\n"},
	}
	for _, c := range cases {
		out, status, m := runLedger(t, c.in)
		uassert.Equal(t, "halted", status.String(), c.in+": "+m.Trap())
		uassert.Equal(t, c.want, out)
		uassert.Equal(t, uint64(1), uint64(m.Registers()[10]), "a refusal exits 1")
	}
}

// 64-bit arithmetic on a 32-bit machine goes through compiler_builtins, and
// printing a balance above 2^32 is the path that proves __udivdi3 ran.
func TestRustLedgerDoes64BitArithmetic(t *testing.T) {
	// Nine-digit mints, accumulated past what 32 bits holds.
	in := ""
	for i := 0; i < 6; i++ {
		in += "mint whale 999999999\n"
	}
	out, status, _ := runLedger(t, in)
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, "whale 5999999994\n", out)
}

// Compiled Rust pauses and resumes like anything else, including in the middle
// of a library routine it never asked to call.
func TestRustLedgerSurvivesSlicing(t *testing.T) {
	image := GuestLedger()
	h := vmkit.NewTestHost().WithInput([]byte("mint alice 100\nsend alice bob 30\n"))

	sliced, err := NewMachine(image, entry)
	uassert.NoError(t, err)
	status := vmkit.Running
	slices := 0
	for i := 0; i < 4000 && status == vmkit.Running; i++ {
		var fresh Machine
		uassert.NoError(t, fresh.Restore(sliced.Snapshot()))
		_, status = fresh.Step(h, 17)
		sliced = &fresh
		slices++
	}
	uassert.Equal(t, "halted", status.String())
	uassert.True(t, slices > 20, "a sliced run must actually have been sliced")
	uassert.Equal(t, "alice 70\nbob 30\n", string(h.Out()))
}
