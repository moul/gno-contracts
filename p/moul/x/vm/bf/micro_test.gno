package bf

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
)

// The microarchitecture matrix.
//
// The rungs in ladder_test.gno are the classic interpreter optimizations:
// fewer instructions for the same program. These are the other axis, and on
// the GnoVM they matter as much: the same instruction stream, executed by
// loops that differ from each other by exactly one line.
//
// They are deliberately simplified (no host, no snapshot, no scan) so that
// the one line is the only difference. They are comparable to each other and
// not to the shipped machine, which does more. What the shipped machine took
// from them is documented on [Machine.Step].

type vm struct {
	prog *Program
	tape [TapeSize]byte
	ptr  int
	pc   int
}

// V0: cursors as struct fields. No meter, no bounds check, no defer.
func (m *vm) runFields() int64 {
	ops := m.prog.ops
	var used int64
	for {
		used++
		switch ops[m.pc].code {
		case opAdd:
			m.tape[m.ptr] += byte(ops[m.pc].arg)
		case opMove:
			m.ptr = wrap(m.ptr + ops[m.pc].arg)
		case opSet:
			m.tape[m.ptr] = byte(ops[m.pc].arg)
		case opAddMul:
			if v := m.tape[m.ptr]; v != 0 {
				m.tape[wrap(m.ptr+ops[m.pc].off)] += v * byte(ops[m.pc].arg)
			}
		case opJmpZ:
			if m.tape[m.ptr] == 0 {
				m.pc = ops[m.pc].arg
			}
		case opJmpNZ:
			if m.tape[m.ptr] != 0 {
				m.pc = ops[m.pc].arg
			}
		case opHalt:
			return used
		}
		m.pc++
	}
}

// V1: V0 with the two cursors hoisted into locals. Only change.
func (m *vm) runLocals() int64 {
	ops := m.prog.ops
	pc, ptr := m.pc, m.ptr
	var used int64
	for {
		used++
		switch ops[pc].code {
		case opAdd:
			m.tape[ptr] += byte(ops[pc].arg)
		case opMove:
			ptr = wrap(ptr + ops[pc].arg)
		case opSet:
			m.tape[ptr] = byte(ops[pc].arg)
		case opAddMul:
			if v := m.tape[ptr]; v != 0 {
				m.tape[wrap(ptr+ops[pc].off)] += v * byte(ops[pc].arg)
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
			m.pc, m.ptr = pc, ptr
			return used
		}
		pc++
	}
}

// V2: V1 plus a vmkit.Meter charged once per op. Only change.
func (m *vm) runLocalsMeter(fuel int64) int64 {
	ops := m.prog.ops
	meter := vmkit.NewMeter(fuel)
	pc, ptr := m.pc, m.ptr
	for {
		if !meter.Charge(1) {
			m.pc, m.ptr = pc, ptr
			return meter.Used()
		}
		switch ops[pc].code {
		case opAdd:
			m.tape[ptr] += byte(ops[pc].arg)
		case opMove:
			ptr = wrap(ptr + ops[pc].arg)
		case opSet:
			m.tape[ptr] = byte(ops[pc].arg)
		case opAddMul:
			if v := m.tape[ptr]; v != 0 {
				m.tape[wrap(ptr+ops[pc].off)] += v * byte(ops[pc].arg)
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
			m.pc, m.ptr = pc, ptr
			return meter.Used()
		}
		pc++
	}
}

// V3: V1 plus an inline fuel counter instead of the Meter object. Isolates
// the cost of the method call from the cost of metering at all.
func (m *vm) runLocalsInlineFuel(fuel int64) int64 {
	ops := m.prog.ops
	pc, ptr := m.pc, m.ptr
	var used int64
	for {
		if used >= fuel {
			m.pc, m.ptr = pc, ptr
			return used
		}
		used++
		switch ops[pc].code {
		case opAdd:
			m.tape[ptr] += byte(ops[pc].arg)
		case opMove:
			ptr = wrap(ptr + ops[pc].arg)
		case opSet:
			m.tape[ptr] = byte(ops[pc].arg)
		case opAddMul:
			if v := m.tape[ptr]; v != 0 {
				m.tape[wrap(ptr+ops[pc].off)] += v * byte(ops[pc].arg)
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
			m.pc, m.ptr = pc, ptr
			return used
		}
		pc++
	}
}


// V4: V3 with the tape as a local slice instead of an array field. Only
// change, so this settles the "a fixed array removes a bounds check" claim.
func (m *vm) runLocalsInlineFuelSliceTape(fuel int64) int64 {
	ops := m.prog.ops
	tape := make([]byte, TapeSize)
	pc, ptr := m.pc, m.ptr
	var used int64
	for {
		if used >= fuel {
			m.pc, m.ptr = pc, ptr
			return used
		}
		used++
		switch ops[pc].code {
		case opAdd:
			tape[ptr] += byte(ops[pc].arg)
		case opMove:
			ptr = wrap(ptr + ops[pc].arg)
		case opSet:
			tape[ptr] = byte(ops[pc].arg)
		case opAddMul:
			if v := tape[ptr]; v != 0 {
				tape[wrap(ptr+ops[pc].off)] += v * byte(ops[pc].arg)
			}
		case opJmpZ:
			if tape[ptr] == 0 {
				pc = ops[pc].arg
			}
		case opJmpNZ:
			if tape[ptr] != 0 {
				pc = ops[pc].arg
			}
		case opHalt:
			m.pc, m.ptr = pc, ptr
			return used
		}
		pc++
	}
}

func microProg(lvl Level) *Program {
	p, err := Compile(heavy, lvl)
	if err != nil {
		panic(err)
	}
	return p
}

// Rung 1's instruction stream, 121,202 ops, under each loop.

func TestMicroJumpsCursorsAsFields(t *testing.T) {
	(&vm{prog: microProg(LevelJumps)}).runFields()
}

func TestMicroJumpsCursorsInLocals(t *testing.T) {
	(&vm{prog: microProg(LevelJumps)}).runLocals()
}

func TestMicroJumpsMeterPerOp(t *testing.T) {
	(&vm{prog: microProg(LevelJumps)}).runLocalsMeter(vmkit.Unmetered)
}

func TestMicroJumpsInlineFuel(t *testing.T) {
	(&vm{prog: microProg(LevelJumps)}).runLocalsInlineFuel(1 << 40)
}

// Rung 3's instruction stream, 1,203 ops, under the same loops.

func TestMicroJumpsSliceTape(t *testing.T) {
	(&vm{prog: microProg(LevelJumps)}).runLocalsInlineFuelSliceTape(1 << 40)
}

func TestMicroIdiomsCursorsAsFields(t *testing.T) {
	(&vm{prog: microProg(LevelIdioms)}).runFields()
}

func TestMicroIdiomsCursorsInLocals(t *testing.T) {
	(&vm{prog: microProg(LevelIdioms)}).runLocals()
}

func TestMicroIdiomsMeterPerOp(t *testing.T) {
	(&vm{prog: microProg(LevelIdioms)}).runLocalsMeter(vmkit.Unmetered)
}

func TestMicroIdiomsInlineFuel(t *testing.T) {
	(&vm{prog: microProg(LevelIdioms)}).runLocalsInlineFuel(1 << 40)
}

func TestMicroIdiomsSliceTape(t *testing.T) {
	(&vm{prog: microProg(LevelIdioms)}).runLocalsInlineFuelSliceTape(1 << 40)
}
