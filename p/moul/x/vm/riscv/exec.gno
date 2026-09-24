// Package riscv is an RV32IM emulator for gno.land: 48 instructions that every
// real compiler already targets.
//
// A guest here is not written in a new language. `rustc --target
// riscv32im-unknown-none-elf`, `clang -target riscv32`, TinyGo and Zig all emit
// it, so a program arrives compiled by the real compiler and optimized by the
// real optimizer. The interpreter is a decode loop rather than a semantic
// minefield: fetch four bytes, switch on seven bits, do arithmetic.
//
// No F or D. No floats means no rounding-mode ambiguity and nothing that can
// differ between nodes. The M extension's divide-by-zero and overflow cases are
// defined by the spec to RETURN a value rather than trap, which is exactly what
// a deterministic chain wants.
//
// It implements [vmkit.Machine], so it shares the fuel meter, the snapshot
// codec and the instance store with [p/moul/x/vm/bf](/p/moul/x/vm/bf/v0). That
// sharing is the point: the second guest is what tells you whether the ABI was
// shaped around the first one.
//
// Live demo: [r/moul/x/vm/riscvdemo](/r/moul/x/vm/riscvdemo/v0).
package riscv

import (
	"errors"

	"gno.land/p/moul/x/vm/vmkit/v0"
)

// VMName is the identifier this machine registers under in a vmkit.Instance.
const VMName = "riscv32im"

// DefaultEntry is where a flat text image is conventionally loaded and where
// execution starts. Low enough to leave a scratch page below it, aligned, and
// nothing about the machine requires it: NewMachine takes the entry point.
const DefaultEntry uint32 = 0x1000

const (
	snapMagic uint32 = 0x52563332 // "RV32"

	// snapVersion 2 carries the text segment's extent, which version 1 did
	// not need because the interpreter decoded from memory on every fetch.
	// Predecoding moved that work to load time, so a restored hart has to be
	// told which part of its memory is code.
	snapVersion byte = 2
)

// ErrNoProgram is returned when a Machine is stepped with no image loaded.
var ErrNoProgram = errors.New("riscv: machine has no program")

// Machine is an RV32IM hart, mid-execution.
type Machine struct {
	reg [32]uint32
	pc  uint32
	mem *Memory

	// code is the text segment with its fields already pulled apart. See
	// predecode.gno for why the dispatch loop reads arrays and not memory.
	code *code

	status vmkit.Status
	trap   string

	// out is what the guest wrote through the write syscall, mirrored to the
	// host as it goes. Kept here too so a snapshot round-trips it.
	outLen int
}

// NewMachine returns a hart with the image loaded at entry, pc at entry, and
// the stack pointer at the top of memory.
func NewMachine(image []byte, entry uint32) (*Machine, error) {
	if entry%4 != 0 {
		return nil, errors.New("riscv: entry point is not 4-byte aligned")
	}
	if len(image)%4 != 0 {
		return nil, errors.New("riscv: image length is not a whole number of instructions")
	}
	m := &Machine{mem: NewMemory(), pc: entry, status: vmkit.Running}
	if !m.mem.WriteImage(entry, image) {
		return nil, errors.New("riscv: image does not fit at the entry point")
	}
	m.code = predecode(entry, image)
	// x2 is sp by convention. A guest that never touches the stack does not
	// care; one compiled by rustc does, immediately.
	m.reg[2] = MemSize
	return m, nil
}

// LoadData places initialized data in memory, outside the text segment.
//
// The other half of a flat-image loader. A program with a .data section needs
// its initial bytes in memory and needs to write them back afterwards, which
// the text segment forbids: W xor X is what makes the predecode sound. So the
// linker puts data at its own address and it arrives here separately, rather
// than being concatenated onto the code and silently becoming read-only.
//
// The pages are marked dirty, so a snapshot carries the data the same way it
// carries the program.
func (m *Machine) LoadData(addr uint32, b []byte) error {
	if m.mem == nil {
		return ErrNoProgram
	}
	if len(b) > 0 && m.code != nil && m.code.words > 0 {
		lo, hi := uint64(addr), uint64(addr)+uint64(len(b))
		if lo < uint64(m.code.end) && hi > uint64(m.code.base) {
			return errors.New("riscv: data segment overlaps the text segment")
		}
	}
	if !m.mem.WriteImage(addr, b) {
		return errors.New("riscv: data does not fit at that address")
	}
	return nil
}

// Registers returns a copy of the register file, for tests and rendering.
func (m *Machine) Registers() [32]uint32 { return m.reg }

// PC returns the program counter.
func (m *Machine) PC() uint32 { return m.pc }

// Memory returns the address space.
func (m *Machine) Memory() *Memory { return m.mem }

// Status returns the machine's status.
func (m *Machine) Status() vmkit.Status { return m.status }

// Trap returns why the machine trapped, making Machine a [vmkit.Trapper].
func (m *Machine) Trap() string { return m.trap }

// Step runs until the program halts, traps, or spends `fuel` instructions.
//
// Written the way the bf ladder concluded, and for the same measured reasons:
// the hot state is in locals and written back once, and the fuel counter is two
// locals rather than a vmkit.Meter, because calling a method per instruction
// cost 86% there and would cost more here, where an instruction is cheaper.
//
// Two things in this loop look like premature optimization and are not, both
// measured in switchcost_test.gno on this VM:
//
//   - The case order is the internal opcode order from predecode.gno, which is
//     by dynamic frequency, because the GnoVM scans switch cases in source
//     order at 278 gas each. Reordering the arms below changes what the
//     interpreter costs.
//   - Everything the loop touches is a local. Reading cop[i] through m.code.op
//     instead would pay for two field lookups on every instruction.
func (m *Machine) Step(h vmkit.Host, fuel int64) (int64, vmkit.Status) {
	if m.mem == nil || m.code == nil {
		m.status, m.trap = vmkit.Trapped, "no program"
		return 0, m.status
	}
	if m.status != vmkit.Running {
		return 0, m.status
	}

	pc := m.pc
	// A misaligned pc would index the word containing it rather than trap,
	// because the index is a shift. Only a restored snapshot can get here with
	// one, since JALR is the only instruction that can produce it and it
	// checks its own target.
	if pc%4 != 0 {
		m.status, m.trap = vmkit.Trapped, "misaligned program counter"
		return 0, m.status
	}

	reg := &m.reg
	mem := m.mem

	c := m.code
	cop, crd, crs1, crs2, cimm := c.op, c.rd, c.rs1, c.rs2, c.imm
	cbase, cwords, cend := c.base, c.words, c.end
	defer func() { m.pc = pc }()

	budget := fuel
	if budget < 0 {
		budget = vmkit.Unmetered
	}
	metered := budget != vmkit.Unmetered
	var used int64

	for {
		if metered && used >= budget {
			return used, vmkit.Running
		}
		used++

		// One subtraction and one shift replace the fetch. A pc below the text
		// segment underflows to a huge index and is caught by the same
		// comparison, which is why there is no second bound here.
		i := (pc - cbase) >> 2
		if i >= cwords {
			m.status, m.trap = vmkit.Trapped, "instruction fetch out of range"
			return used, m.status
		}
		next := pc + 4

		switch cop[i] {
		case iADDI:
			reg[crd[i]] = reg[crs1[i]] + cimm[i]
		case iLW:
			v, ok := mem.Load32(reg[crs1[i]] + cimm[i])
			if !ok {
				m.status, m.trap = vmkit.Trapped, "load out of range"
				return used, m.status
			}
			reg[crd[i]] = v
		case iSW:
			addr := reg[crs1[i]] + cimm[i]
			if addr < cend && addr+4 > cbase {
				m.status, m.trap = vmkit.Trapped, "store into text segment"
				return used, m.status
			}
			if !mem.Store32(addr, reg[crs2[i]]) {
				m.status, m.trap = vmkit.Trapped, "store out of range"
				return used, m.status
			}
		case iADD:
			reg[crd[i]] = reg[crs1[i]] + reg[crs2[i]]
		case iBNE:
			if reg[crs1[i]] != reg[crs2[i]] {
				next = pc + cimm[i]
			}
		case iBEQ:
			if reg[crs1[i]] == reg[crs2[i]] {
				next = pc + cimm[i]
			}
		case iJAL:
			reg[crd[i]] = next
			next = pc + cimm[i]
		case iJALR:
			// The target is computed before rd is written, because rd and rs1
			// are allowed to be the same register and usually are: `ret` is
			// jalr x0, 0(x1).
			t := (reg[crs1[i]] + cimm[i]) &^ 1
			if t%4 != 0 {
				m.status, m.trap = vmkit.Trapped, "misaligned jump target"
				return used, m.status
			}
			reg[crd[i]] = next
			next = t
		case iLUI:
			reg[crd[i]] = cimm[i]
		case iSLLI:
			reg[crd[i]] = reg[crs1[i]] << (cimm[i] & 0x1F)
		case iSRLI:
			reg[crd[i]] = reg[crs1[i]] >> (cimm[i] & 0x1F)
		case iANDI:
			reg[crd[i]] = reg[crs1[i]] & cimm[i]
		case iSUB:
			reg[crd[i]] = reg[crs1[i]] - reg[crs2[i]]
		case iORI:
			reg[crd[i]] = reg[crs1[i]] | cimm[i]
		case iXORI:
			reg[crd[i]] = reg[crs1[i]] ^ cimm[i]
		case iBLT:
			if int32(reg[crs1[i]]) < int32(reg[crs2[i]]) {
				next = pc + cimm[i]
			}
		case iBGE:
			if int32(reg[crs1[i]]) >= int32(reg[crs2[i]]) {
				next = pc + cimm[i]
			}
		case iBLTU:
			if reg[crs1[i]] < reg[crs2[i]] {
				next = pc + cimm[i]
			}
		case iBGEU:
			if reg[crs1[i]] >= reg[crs2[i]] {
				next = pc + cimm[i]
			}
		case iSRAI:
			reg[crd[i]] = uint32(int32(reg[crs1[i]]) >> (cimm[i] & 0x1F))
		case iSLL:
			reg[crd[i]] = reg[crs1[i]] << (reg[crs2[i]] & 0x1F)
		case iSRL:
			reg[crd[i]] = reg[crs1[i]] >> (reg[crs2[i]] & 0x1F)
		case iSRA:
			reg[crd[i]] = uint32(int32(reg[crs1[i]]) >> (reg[crs2[i]] & 0x1F))
		case iAND:
			reg[crd[i]] = reg[crs1[i]] & reg[crs2[i]]
		case iOR:
			reg[crd[i]] = reg[crs1[i]] | reg[crs2[i]]
		case iXOR:
			reg[crd[i]] = reg[crs1[i]] ^ reg[crs2[i]]
		case iLBU:
			v, ok := mem.Load8(reg[crs1[i]] + cimm[i])
			if !ok {
				m.status, m.trap = vmkit.Trapped, "load out of range"
				return used, m.status
			}
			reg[crd[i]] = uint32(v)
		case iLB:
			v, ok := mem.Load8(reg[crs1[i]] + cimm[i])
			if !ok {
				m.status, m.trap = vmkit.Trapped, "load out of range"
				return used, m.status
			}
			reg[crd[i]] = uint32(int32(int8(v)))
		case iLH:
			v, ok := mem.Load16(reg[crs1[i]] + cimm[i])
			if !ok {
				m.status, m.trap = vmkit.Trapped, "load out of range"
				return used, m.status
			}
			reg[crd[i]] = uint32(int32(int16(v)))
		case iLHU:
			v, ok := mem.Load16(reg[crs1[i]] + cimm[i])
			if !ok {
				m.status, m.trap = vmkit.Trapped, "load out of range"
				return used, m.status
			}
			reg[crd[i]] = uint32(v)
		case iSB:
			addr := reg[crs1[i]] + cimm[i]
			if addr < cend && addr+4 > cbase {
				m.status, m.trap = vmkit.Trapped, "store into text segment"
				return used, m.status
			}
			if !mem.Store8(addr, uint8(reg[crs2[i]])) {
				m.status, m.trap = vmkit.Trapped, "store out of range"
				return used, m.status
			}
		case iSH:
			addr := reg[crs1[i]] + cimm[i]
			if addr < cend && addr+4 > cbase {
				m.status, m.trap = vmkit.Trapped, "store into text segment"
				return used, m.status
			}
			if !mem.Store16(addr, uint16(reg[crs2[i]])) {
				m.status, m.trap = vmkit.Trapped, "store out of range"
				return used, m.status
			}
		case iAUIPC:
			reg[crd[i]] = pc + cimm[i]
		case iSLT:
			reg[crd[i]] = b2u(int32(reg[crs1[i]]) < int32(reg[crs2[i]]))
		case iSLTU:
			reg[crd[i]] = b2u(reg[crs1[i]] < reg[crs2[i]])
		case iSLTI:
			reg[crd[i]] = b2u(int32(reg[crs1[i]]) < int32(cimm[i]))
		case iSLTIU:
			reg[crd[i]] = b2u(reg[crs1[i]] < cimm[i])
		case iMUL:
			reg[crd[i]] = reg[crs1[i]] * reg[crs2[i]]
		case iMULH:
			reg[crd[i]] = uint32((int64(int32(reg[crs1[i]])) * int64(int32(reg[crs2[i]]))) >> 32)
		case iMULHSU:
			reg[crd[i]] = uint32((int64(int32(reg[crs1[i]])) * int64(uint64(reg[crs2[i]]))) >> 32)
		case iMULHU:
			reg[crd[i]] = uint32((uint64(reg[crs1[i]]) * uint64(reg[crs2[i]])) >> 32)
		case iDIV:
			// The M extension defines divide by zero and the one signed
			// overflow case to RETURN a value rather than trap. That is what
			// makes it safe on a chain: there is no host arithmetic exception
			// to differ between nodes.
			reg[crd[i]] = divS(int32(reg[crs1[i]]), int32(reg[crs2[i]]))
		case iDIVU:
			if reg[crs2[i]] == 0 {
				reg[crd[i]] = ^uint32(0)
			} else {
				reg[crd[i]] = reg[crs1[i]] / reg[crs2[i]]
			}
		case iREM:
			reg[crd[i]] = remS(int32(reg[crs1[i]]), int32(reg[crs2[i]]))
		case iREMU:
			if reg[crs2[i]] == 0 {
				reg[crd[i]] = reg[crs1[i]]
			} else {
				reg[crd[i]] = reg[crs1[i]] % reg[crs2[i]]
			}
		case iECALL:
			st, halt := m.ecall(h)
			if halt {
				// pc advances past the ecall before returning, so a halted
				// hart points at what it would run next rather than at the
				// syscall it already made. The deferred write-back is the only
				// thing that sets m.pc, so assigning the local is how this is
				// said.
				m.status = st
				pc = next
				return used, m.status
			}
		case iEBREAK:
			m.status, m.trap = vmkit.Trapped, "ebreak"
			pc = next
			return used, m.status
		case iFENCE:
			// FENCE orders memory for a hart that has neighbours. There is
			// exactly one here, so it is architecturally a no-op rather than
			// an unimplemented instruction.
		default:
			m.status, m.trap = vmkit.Trapped, "illegal instruction"
			return used, m.status
		}

		// x0 is hardwired to zero. Writing it is legal and discarded, and
		// clearing after the fact is cheaper than branching on rd in every
		// arm above.
		reg[0] = 0
		pc = next
	}
}

// b2u is the spec's "set if" result: 1 or 0, never a Go bool.
func b2u(b bool) uint32 {
	if b {
		return 1
	}
	return 0
}

// divS is DIV with the two cases the spec pins down: division by zero yields
// all ones, and the most negative value divided by -1 overflows to itself.
func divS(a, b int32) uint32 {
	if b == 0 {
		return ^uint32(0)
	}
	if a == -2147483648 && b == -1 {
		return uint32(a)
	}
	return uint32(a / b)
}

// remS is REM, with the matching pair: remainder by zero is the dividend, and
// the overflow case is zero.
func remS(a, b int32) uint32 {
	if b == 0 {
		return uint32(a)
	}
	if a == -2147483648 && b == -1 {
		return 0
	}
	return uint32(a % b)
}
