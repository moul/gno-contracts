package bf

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/uassert/v0"
)

// oneShot runs src to completion and returns what it wrote.
func oneShot(t *testing.T, src string) string {
	t.Helper()
	h := vmkit.NewTestHost()
	status, err := Run(src, h)
	uassert.NoError(t, err)
	uassert.Equal(t, "halted", status.String())
	return h.OutString()
}

// TestSlicedRunEqualsOneShot is the property that makes a guest program a
// contract rather than a function call: chopping the execution into fuel
// slices, snapshotting between each, must produce exactly the single run.
func TestSlicedRunEqualsOneShot(t *testing.T) {
	for _, slice := range []int64{1, 2, 7, 64} {
		prog, err := CompileDefault(hello)
		uassert.NoError(t, err)

		h := vmkit.NewTestHost()
		snap := []byte(nil)
		status := vmkit.Running
		slices := 0
		for status == vmkit.Running && slices < 10000 {
			m := NewMachine(prog) // a realm holds bytes, not a machine
			if snap != nil {
				uassert.NoError(t, m.Restore(snap))
			}
			_, status = m.Step(h, slice)
			snap = m.Snapshot()
			slices++
		}
		uassert.Equal(t, "halted", status.String())
		uassert.Equal(t, "Hello World", h.OutString())
	}
}

func TestSlicedRunAgreesAcrossTheCorpus(t *testing.T) {
	for _, tc := range corpus {
		prog, err := CompileDefault(tc.src)
		uassert.NoError(t, err)
		if prog == nil {
			continue
		}
		h := vmkit.NewTestHost()
		snap := []byte(nil)
		status := vmkit.Running
		n := 0
		for status == vmkit.Running && n < 20000 {
			m := NewMachine(prog)
			if snap != nil {
				uassert.NoError(t, m.Restore(snap))
			}
			_, status = m.Step(h, 3)
			snap = m.Snapshot()
			n++
		}
		if h.OutString() != tc.want {
			t.Errorf("%s sliced: got %q, want %q", tc.name, h.OutString(), tc.want)
		}
	}
}

func TestFuelStopsTheMachine(t *testing.T) {
	prog, err := CompileDefault(hello)
	uassert.NoError(t, err)
	m := NewMachine(prog)
	h := vmkit.NewTestHost()

	used, status := m.Step(h, 5)
	uassert.Equal(t, int64(5), used)
	uassert.Equal(t, "running", status.String())
	uassert.Equal(t, "", h.OutString()) // not far enough to print anything
}

// TestScanIsChargedPerCell pins the thing that would otherwise be a way to
// buy unbounded work for one unit: a scan walks one cell per unit of fuel,
// and stopping mid-scan resumes the same walk.
func TestScanIsChargedPerCell(t *testing.T) {
	// 20 non-zero cells, then scan left back to the zero at cell 0.
	src := ">+>+>+>+>+>+>+>+>+>+>+>+>+>+>+>+>+>+>+>+[<]"
	prog, err := CompileDefault(src)
	uassert.NoError(t, err)

	m := NewMachine(prog)
	h := vmkit.NewTestHost()
	used, status := m.Step(h, 45)
	uassert.Equal(t, int64(45), used)
	uassert.Equal(t, "running", status.String())
	uassert.True(t, m.Pointer() > 0) // stopped part way down the scan

	// Resuming finishes the same walk and lands on the zero cell.
	_, status = m.Step(h, vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, 0, m.Pointer())
}

func TestSnapshotRoundTrip(t *testing.T) {
	prog, err := CompileDefault(hello)
	uassert.NoError(t, err)

	a := NewMachine(prog)
	h := vmkit.NewTestHost()
	a.Step(h, 40)

	b := NewMachine(prog)
	uassert.NoError(t, b.Restore(a.Snapshot()))
	uassert.Equal(t, a.PC(), b.PC())
	uassert.Equal(t, a.Pointer(), b.Pointer())
	uassert.Equal(t, a.Touched(), b.Touched())
	for i := 0; i < a.Touched(); i++ {
		uassert.Equal(t, uint64(a.Cell(i)), uint64(b.Cell(i)))
	}
	uassert.Equal(t, string(a.Snapshot()), string(b.Snapshot()))
}

// TestSnapshotIsTrimmed is the continuation kill criterion in test form: if a
// pause carried the whole 30,000 byte tape, resuming would cost more than
// re-running and continuations would be theater.
func TestSnapshotIsTrimmed(t *testing.T) {
	m, err := Load(hello)
	uassert.NoError(t, err)
	h := vmkit.NewTestHost()
	m.Step(h, vmkit.Unmetered)

	uassert.Equal(t, 5, m.Touched()) // hello world uses five cells
	snap := m.Snapshot()
	// 4 magic + 1 version + 3x8 zig-zag ints + 1 status + 4 empty trap
	// + 4 length + 5 tape. The README quotes this number.
	uassert.Equal(t, 43, len(snap))
	uassert.True(t, len(snap) < TapeSize/100)
}

func TestRestoreRejectsJunk(t *testing.T) {
	prog, err := CompileDefault(hello)
	uassert.NoError(t, err)
	good := NewMachine(prog)
	good.Step(vmkit.NewTestHost(), 20)
	snap := good.Snapshot()

	cases := []struct {
		name string
		b    []byte
	}{
		{"empty", []byte{}},
		{"truncated", snap[:len(snap)-3]},
		{"bad magic", append([]byte{0, 0, 0, 0}, snap[4:]...)},
	}
	for _, tc := range cases {
		m := NewMachine(prog)
		if err := m.Restore(tc.b); err == nil {
			t.Errorf("Restore(%s) should have failed", tc.name)
		}
	}

	// A snapshot with a wrong version byte is refused rather than decoded
	// into a plausible-looking wrong state.
	bad := make([]byte, len(snap))
	copy(bad, snap)
	bad[4] = 99
	m := NewMachine(prog)
	uassert.ErrorIs(t, m.Restore(bad), vmkit.ErrBadSnapshot)
}

func TestRestoreRejectsAnOutOfRangePC(t *testing.T) {
	small, err := CompileDefault("+")
	uassert.NoError(t, err)
	big, err := CompileDefault(hello)
	uassert.NoError(t, err)

	m := NewMachine(big)
	m.Step(vmkit.NewTestHost(), 30)
	snap := m.Snapshot()

	// The same snapshot against a two-op program points past the end.
	other := NewMachine(small)
	uassert.ErrorIs(t, other.Restore(snap), vmkit.ErrBadSnapshot)
}

func TestHaltedMachineStaysHalted(t *testing.T) {
	m, err := Load("+++.")
	uassert.NoError(t, err)
	h := vmkit.NewTestHost()
	m.Step(h, vmkit.Unmetered)
	uassert.Equal(t, "halted", m.Status().String())

	used, status := m.Step(h, vmkit.Unmetered)
	uassert.Equal(t, int64(0), used)
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, "\x03", h.OutString()) // still only one write
}

func TestLoadRejectsBadSource(t *testing.T) {
	_, err := Load("[[")
	uassert.Error(t, err)
	status, err := Run("]", vmkit.NewTestHost())
	uassert.Error(t, err)
	uassert.Equal(t, "trapped", status.String())
}

// TestInstanceIntegration wires the machine through vmkit's realm-facing
// plumbing, which is the shape the demo realm uses.
func TestInstanceIntegration(t *testing.T) {
	prog, err := CompileDefault(hello)
	uassert.NoError(t, err)

	inst := vmkit.NewInstance("001", address("g1x"), VMName, []byte(hello), vmkit.Unmetered)
	h := vmkit.NewTestHost()
	for i := 0; i < 200 && inst.Status == vmkit.Running; i++ {
		uassert.NoError(t, inst.Run(NewMachine(prog), h, 8))
	}
	uassert.Equal(t, "halted", inst.Status.String())
	uassert.Equal(t, "Hello World", h.OutString())
	uassert.True(t, inst.Slices > 1)
	uassert.True(t, inst.FuelUsed > 0)
}

func TestInstanceHonoursItsBudget(t *testing.T) {
	prog, err := CompileDefault(hello)
	uassert.NoError(t, err)

	inst := vmkit.NewInstance("002", address("g1x"), VMName, []byte(hello), 10)
	h := vmkit.NewTestHost()
	uassert.NoError(t, inst.Run(NewMachine(prog), h, vmkit.Unmetered))
	uassert.Equal(t, "out of fuel", inst.Status.String())
	uassert.Equal(t, int64(10), inst.FuelUsed)
	uassert.ErrorIs(t, inst.Run(NewMachine(prog), h, vmkit.Unmetered), vmkit.ErrBudgetExhausted)
}
