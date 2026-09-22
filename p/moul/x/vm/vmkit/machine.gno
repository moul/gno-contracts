// Package vmkit is the host ABI shared by every guest virtual machine that
// runs inside a gno realm: a stepping contract with an explicit fuel budget,
// a capability-scoped [Host], and a snapshot format that lets a guest program
// outlive the transaction that started it.
//
// A guest VM implements [Machine]. Everything else in this package is the
// machinery a VM should not have to write twice: the [Meter], the [Codec] the
// snapshots are built from, an in-memory [TestHost], and the avl-backed
// [Store] a realm keeps its instances in.
//
// The three things the ABI exists to fix:
//
//   - Fuel is the interface, not the backstop. Running out of fuel yields
//     [OutOfFuel] plus a machine that can be snapshotted, never a panic. Gas
//     still bounds the transaction, but a guest that stops is a normal outcome.
//   - Continuations. Snapshot and Restore mean a program runs across blocks.
//     The realm stores the bytes, and the next caller pays for the next slice.
//     Gno realm code itself cannot pause; a guest can.
//   - Capabilities, not ambient authority. A guest gets exactly the [Host] it
//     was handed. No Send without a grant, no storage outside its own scope.
//
// Live demo: [r/moul/x/vm/bfdemo](/r/moul/x/vm/bfdemo/v0), running the
// [p/moul/x/vm/bf](/p/moul/x/vm/bf/v0) guest.
package vmkit

// Status is the outcome of a call to [Machine.Step].
type Status int

const (
	// Running means the machine stopped because it ran out of the fuel
	// handed to this slice, but the program has not finished. It is
	// resumable: snapshot it, and step it again later.
	Running Status = iota

	// Halted means the program reached its end. Terminal.
	Halted

	// Trapped means the guest did something the machine refuses to do:
	// an invalid instruction, an out-of-range access, a capability it was
	// not granted. Terminal.
	Trapped

	// OutOfFuel means the instance exhausted its total budget, not just the
	// fuel for this slice. Terminal unless the owner raises the budget.
	OutOfFuel
)

// String renders the status as the lowercase word used in realm output.
func (s Status) String() string {
	switch s {
	case Running:
		return "running"
	case Halted:
		return "halted"
	case Trapped:
		return "trapped"
	case OutOfFuel:
		return "out of fuel"
	}
	return "unknown"
}

// Done reports whether the status is terminal, i.e. stepping again is
// pointless without operator intervention.
func (s Status) Done() bool { return s != Running }

// Machine is one guest virtual machine, mid-execution.
//
// Step runs until the program halts, traps, or burns `fuel` units, whichever
// comes first, and reports how much fuel it actually used. A Machine must
// charge at least one unit per guest instruction so that a fuel budget is a
// real bound on work; beyond that the unit is the VM's own business, and
// [r/moul/x/vm/bfdemo](/r/moul/x/vm/bfdemo/v0) compares them by measurement
// rather than by trusting the number.
//
// Snapshot must round-trip through Restore: a machine stepped to exhaustion,
// snapshotted, restored and stepped again must produce exactly what the same
// machine stepped in one go would have. That property is what makes a guest
// program a contract instead of a function call.
type Machine interface {
	Step(h Host, fuel int64) (used int64, status Status)
	Snapshot() []byte
	Restore(b []byte) error
}

// Trapper is an optional refinement of [Machine]: a machine that can explain
// why it trapped. Kept out of [Machine] so the core ABI stays three methods.
type Trapper interface {
	// Trap returns the reason for a [Trapped] status, or "" when the
	// machine has not trapped.
	Trap() string
}

// TrapReason returns m's trap reason when m implements [Trapper], else "".
func TrapReason(m Machine) string {
	if t, ok := m.(Trapper); ok {
		return t.Trap()
	}
	return ""
}
