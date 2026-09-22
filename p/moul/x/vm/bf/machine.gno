package bf

import (
	"errors"

	"gno.land/p/moul/x/vm/vmkit/v0"
)

// VMName is the identifier this machine registers under in a
// [vmkit.Instance].
const VMName = "bf"

// snapMagic and snapVersion tag a snapshot so a machine refuses bytes that
// were not written by this machine at this version, instead of decoding them
// into a plausible-looking wrong state.
const (
	snapMagic   uint32 = 0x62660001 // "bf" 0001
	snapVersion byte   = 1
)

// ErrNoProgram is returned when a [Machine] is stepped without a program.
var ErrNoProgram = errors.New("bf: machine has no program")

// Machine is a compiled Brainfuck program, mid-execution: a
// [vmkit.Machine] with a fixed tape, a fuel-metered step loop, input and
// output through the host, and a snapshot small enough that pausing is
// cheaper than starting over.
//
// The tape is a fixed-size array rather than a slice: that is rung 4 of the
// ladder, and the README reports what it actually bought.
type Machine struct {
	prog *Program

	tape  [TapeSize]byte
	ptr   int
	pc    int
	inPos int // read cursor into Host.Input, carried across slices

	status vmkit.Status
	trap   string

	// hi is the highest tape index written so far, so a snapshot can stop
	// there instead of carrying 30,000 bytes of zeros.
	hi int
}

// NewMachine returns a machine ready to run prog from the start.
func NewMachine(prog *Program) *Machine {
	return &Machine{prog: prog, status: vmkit.Running}
}

// Load compiles src at [Default] and returns a machine for it.
func Load(src string) (*Machine, error) {
	prog, err := CompileDefault(src)
	if err != nil {
		return nil, err
	}
	return NewMachine(prog), nil
}

// Program returns the program the machine is running.
func (m *Machine) Program() *Program { return m.prog }

// Status returns the machine's current status.
func (m *Machine) Status() vmkit.Status { return m.status }

// Trap returns the reason the machine trapped, or "". It makes Machine a
// [vmkit.Trapper].
func (m *Machine) Trap() string { return m.trap }

// Pointer returns the tape pointer.
func (m *Machine) Pointer() int { return m.ptr }

// PC returns the index of the next op to execute.
func (m *Machine) PC() int { return m.pc }

// Cell returns the tape byte at i, wrapped into range.
func (m *Machine) Cell(i int) byte { return m.tape[wrap(i)] }

// Touched returns how many tape cells the program has reached, which is the
// length a snapshot has to carry.
func (m *Machine) Touched() int { return m.hi + 1 }

// Step runs until the program halts, traps, or spends `fuel` units, charging
// one unit per op executed and one per cell a scan walks over. Pass
// [vmkit.Unmetered] to run to completion.
//
// Fuel is charged before the op runs, so a machine that stops for lack of
// fuel has not half-executed anything: it is exactly at the op it could not
// pay for, and resuming re-executes that op and nothing else.
//
// Three things in here are written the way they are because the alternative
// was measured and lost. The README has the table.
//
//   - The fuel counter is two locals, not a [vmkit.Meter]. Calling
//     Meter.Charge once per instruction costs 86% on top of the whole
//     dispatch loop and triples the allocation count. Meter stays the type
//     at the API boundary, where it is called once; it is not a hot-path
//     type, and no guest VM should treat it as one.
//   - The program counter and the tape pointer are locals, written back once
//     by the deferred closure. Reaching through m. for them on every
//     instruction costs 16%.
//   - The pc range check happens once, before the loop, not per op. Every
//     jump target is produced by [Compile] and every restored pc is
//     validated by [Machine.Restore], so per-op checking buys nothing.
func (m *Machine) Step(h vmkit.Host, fuel int64) (int64, vmkit.Status) {
	if m.prog == nil {
		m.status, m.trap = vmkit.Trapped, "no program"
		return 0, m.status
	}
	if m.status != vmkit.Running {
		return 0, m.status
	}

	ops := m.prog.ops
	pc, ptr, hi := m.pc, m.ptr, m.hi
	// One write-back, on every return path, including a panic.
	defer func() { m.pc, m.ptr, m.hi = pc, ptr, hi }()

	if pc < 0 || pc >= len(ops) {
		m.status, m.trap = vmkit.Trapped, "pc out of range"
		return 0, m.status
	}

	// budget < 0 is vmkit.Unmetered.
	budget := fuel
	if budget < 0 {
		budget = vmkit.Unmetered
	}
	var used int64

	for {
		if budget != vmkit.Unmetered && used >= budget {
			return used, vmkit.Running
		}
		used++

		switch ops[pc].code {
		case opAdd:
			m.tape[ptr] += byte(ops[pc].arg)
		case opMove:
			ptr = wrap(ptr + ops[pc].arg)
			if ptr > hi {
				hi = ptr
			}
		case opSet:
			m.tape[ptr] = byte(ops[pc].arg)
		case opAddMul:
			if v := m.tape[ptr]; v != 0 {
				t := wrap(ptr + ops[pc].off)
				m.tape[t] += v * byte(ops[pc].arg)
				if t > hi {
					hi = t
				}
			}
		case opScan:
			// A scan is charged per cell, so it cannot be a way to
			// buy unbounded work for one unit of fuel. Stopping
			// mid-scan is safe: the pointer has moved, the pc has
			// not, so resuming continues the same walk.
			for m.tape[ptr] != 0 {
				if budget != vmkit.Unmetered && used >= budget {
					return used, vmkit.Running
				}
				used++
				ptr = wrap(ptr + ops[pc].arg)
				if ptr > hi {
					hi = ptr
				}
			}
		case opOut:
			h.Output([]byte{m.tape[ptr]})
		case opIn:
			in := h.Input()
			if m.inPos < len(in) {
				m.tape[ptr] = in[m.inPos]
				m.inPos++
			} else {
				// End of input is a zero cell, the most common
				// of the three conventions the language never
				// settled.
				m.tape[ptr] = 0
			}
		case opJmpZ:
			if m.tape[ptr] == 0 {
				pc = ops[pc].arg
			}
		case opJmpNZ:
			if m.tape[ptr] != 0 {
				pc = ops[pc].arg
			}
		case opHalt:
			m.status = vmkit.Halted
			return used, m.status
		default:
			m.status, m.trap = vmkit.Trapped, "unknown opcode"
			return used, m.status
		}
		pc++
	}
}

// Snapshot serializes the machine. The tape is truncated at the highest cell
// the program has reached, which is what makes pausing affordable: a hello
// world that touched six cells snapshots six bytes of tape, not 30,000.
func (m *Machine) Snapshot() []byte {
	w := vmkit.NewWriter(m.hi + 48)
	w.Uint32(snapMagic)
	w.Byte(snapVersion)
	w.Int(int64(m.pc))
	w.Int(int64(m.ptr))
	w.Int(int64(m.inPos))
	w.Byte(byte(m.status))
	w.String(m.trap)

	n := m.hi + 1
	if n > TapeSize {
		n = TapeSize
	}
	w.Bytes(m.tape[:n])
	return w.Out()
}

// Restore loads a snapshot into a machine that already carries the program
// the snapshot was taken from. The program is not in the snapshot: a realm
// stores it once, beside the instance, instead of once per pause.
func (m *Machine) Restore(b []byte) error {
	r := vmkit.NewReader(b)
	if r.Uint32() != snapMagic {
		return vmkit.ErrBadSnapshot
	}
	if r.Byte() != snapVersion {
		return vmkit.ErrBadSnapshot
	}
	pc := int(r.Int())
	ptr := int(r.Int())
	inPos := int(r.Int())
	status := vmkit.Status(r.Byte())
	trap := r.String()
	tape := r.Bytes()
	if err := r.Err(); err != nil {
		return err
	}
	if len(tape) > TapeSize || ptr < 0 || ptr >= TapeSize || inPos < 0 {
		return vmkit.ErrBadSnapshot
	}
	if m.prog != nil && (pc < 0 || pc > len(m.prog.ops)) {
		return vmkit.ErrBadSnapshot
	}

	m.pc, m.ptr, m.inPos = pc, ptr, inPos
	m.status, m.trap = status, trap
	// Zero only what this machine could have written: hi bounds every
	// write it has made, and a 30,000 element composite literal is not
	// something to put in a restore path.
	for i := 0; i <= m.hi && i < TapeSize; i++ {
		m.tape[i] = 0
	}
	copy(m.tape[:], tape)
	m.hi = len(tape) - 1
	if m.hi < 0 {
		m.hi = 0
	}
	return nil
}

// Run compiles src at [Default] and runs it to completion against h, with no
// fuel bound. It is the one-shot path: convenient for a test or a small
// program, and exactly the thing a realm should not do with untrusted input.
func Run(src string, h vmkit.Host) (vmkit.Status, error) {
	m, err := Load(src)
	if err != nil {
		return vmkit.Trapped, err
	}
	_, status := m.Step(h, vmkit.Unmetered)
	return status, nil
}

// wrap folds a tape index into range, the way the naive interpreter does one
// step at a time.
func wrap(i int) int {
	i %= TapeSize
	if i < 0 {
		i += TapeSize
	}
	return i
}
