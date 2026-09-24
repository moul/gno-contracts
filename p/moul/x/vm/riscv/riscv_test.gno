package riscv

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/uassert/v0"
)

// A tiny assembler, so the programs below read as instructions rather than as
// hex. Encoding here and decoding in decode.gno are written from the spec
// independently: if one has a field in the wrong place the tests fail, which is
// the point of not sharing a helper between them.

func rType(f7, rs2, rs1, f3, rd, op uint32) uint32 {
	return f7<<25 | rs2<<20 | rs1<<15 | f3<<12 | rd<<7 | op
}
func iType(imm, rs1, f3, rd, op uint32) uint32 {
	return (imm&0xFFF)<<20 | rs1<<15 | f3<<12 | rd<<7 | op
}
func sType(imm, rs2, rs1, f3, op uint32) uint32 {
	return (imm>>5&0x7F)<<25 | rs2<<20 | rs1<<15 | f3<<12 | (imm&0x1F)<<7 | op
}
func bType(imm, rs2, rs1, f3, op uint32) uint32 {
	return (imm>>12&0x1)<<31 | (imm>>5&0x3F)<<25 | rs2<<20 | rs1<<15 |
		f3<<12 | (imm>>1&0xF)<<8 | (imm>>11&0x1)<<7 | op
}
func uType(imm, rd, op uint32) uint32 { return imm&0xFFFFF000 | rd<<7 | op }
func jType(imm, rd, op uint32) uint32 {
	return (imm>>20&0x1)<<31 | (imm>>1&0x3FF)<<21 | (imm>>11&0x1)<<20 |
		(imm>>12&0xFF)<<12 | rd<<7 | op
}

func addi(rd, rs1, imm uint32) uint32 { return iType(imm, rs1, 0x0, rd, opImm) }
func add(rd, rs1, rs2 uint32) uint32  { return rType(0x00, rs2, rs1, 0x0, rd, opReg) }
func sub(rd, rs1, rs2 uint32) uint32  { return rType(0x20, rs2, rs1, 0x0, rd, opReg) }
func mul(rd, rs1, rs2 uint32) uint32  { return rType(0x01, rs2, rs1, 0x0, rd, opReg) }
func divi(rd, rs1, rs2 uint32) uint32 { return rType(0x01, rs2, rs1, 0x4, rd, opReg) }
func remi(rd, rs1, rs2 uint32) uint32 { return rType(0x01, rs2, rs1, 0x6, rd, opReg) }
func sw(rs2, rs1, imm uint32) uint32  { return sType(imm, rs2, rs1, 0x2, opStore) }
func lw(rd, rs1, imm uint32) uint32   { return iType(imm, rs1, 0x2, rd, opLoad) }
func lbu(rd, rs1, imm uint32) uint32  { return iType(imm, rs1, 0x4, rd, opLoad) }
func bne(rs1, rs2, imm uint32) uint32 { return bType(imm, rs2, rs1, 0x1, opBranch) }
func ecall() uint32                   { return iType(0, 0, 0, 0, opSystem) }

// exitWith is the two instructions every test program ends with: set a7 to the
// exit syscall and trap into the host.
func exitWith() []uint32 { return []uint32{addi(17, 0, sysExit), ecall()} }

func asm(words []uint32) []byte {
	out := make([]byte, 0, len(words)*4)
	for _, w := range words {
		out = append(out, byte(w), byte(w>>8), byte(w>>16), byte(w>>24))
	}
	return out
}

const entry = 0x1000

func run(t *testing.T, words []uint32, h vmkit.Host) *Machine {
	t.Helper()
	m, err := NewMachine(asm(words), entry)
	uassert.NoError(t, err)
	if m == nil {
		return nil
	}
	_, status := m.Step(h, vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	return m
}

func TestArithmetic(t *testing.T) {
	// x5 = 7 + 35; x6 = x5 - 2; x7 = x6 * 3
	prog := append([]uint32{
		addi(5, 0, 7),
		addi(5, 5, 35),
		addi(6, 0, 2),
		sub(6, 5, 6),
		addi(7, 0, 3),
		mul(7, 6, 7),
	}, exitWith()...)
	m := run(t, prog, vmkit.NewTestHost())
	r := m.Registers()
	uassert.Equal(t, uint64(42), uint64(r[5]))
	uassert.Equal(t, uint64(40), uint64(r[6]))
	uassert.Equal(t, uint64(120), uint64(r[7]))
}

// Every immediate in the base set is sign extended from its top bit. Small
// positive programs work either way, which is what makes this the classic
// decoder bug: it only shows up on a negative constant.
func TestImmediatesAreSignExtended(t *testing.T) {
	prog := append([]uint32{
		addi(5, 0, 10),
		addi(5, 5, 0xFFF), // -1
		addi(6, 0, 0x800), // -2048, the most negative 12-bit immediate
	}, exitWith()...)
	m := run(t, prog, vmkit.NewTestHost())
	r := m.Registers()
	uassert.Equal(t, uint64(9), uint64(r[5]))
	uassert.Equal(t, int64(-2048), int64(int32(r[6])))
}

// x0 reads as zero and discards every write, and the spec has no exception.
func TestRegisterZeroIsHardwired(t *testing.T) {
	prog := append([]uint32{
		addi(0, 0, 99),
		add(5, 0, 0),
	}, exitWith()...)
	m := run(t, prog, vmkit.NewTestHost())
	uassert.Equal(t, uint64(0), uint64(m.Registers()[0]))
	uassert.Equal(t, uint64(0), uint64(m.Registers()[5]))
}

func TestLoadsAndStores(t *testing.T) {
	prog := append([]uint32{
		addi(5, 0, 0x7F0), // an address well clear of the program
		addi(6, 0, 0x123),
		sw(6, 5, 0),
		lw(7, 5, 0),
		lbu(8, 5, 0), // little-endian: the low byte is 0x23
	}, exitWith()...)
	m := run(t, prog, vmkit.NewTestHost())
	r := m.Registers()
	uassert.Equal(t, uint64(0x123), uint64(r[7]))
	uassert.Equal(t, uint64(0x23), uint64(r[8]))
}

// A loop, which is the only way to know branches and the pc agree.
func TestBranchLoopSumsToTen(t *testing.T) {
	// x5 = 0; x6 = 5; do { x5 += x6; x6 -= 1 } while (x6 != 0)  => 15
	prog := append([]uint32{
		addi(5, 0, 0),
		addi(6, 0, 5),
		add(5, 5, 6),        // loop:
		addi(6, 6, 0xFFF),   // x6 -= 1
		bne(6, 0, 0x1FF8),   // -8, back to loop
	}, exitWith()...)
	m := run(t, prog, vmkit.NewTestHost())
	uassert.Equal(t, uint64(15), uint64(m.Registers()[5]))
}

// The M extension's defined answers. These are the cases a chain cares about,
// because the spec makes them RETURN rather than trap and every implementation
// therefore has to agree.
func TestDivisionEdgeCases(t *testing.T) {
	const minInt32 = 0x80000000
	prog := append([]uint32{
		addi(5, 0, 7),
		addi(6, 0, 0),
		divi(7, 5, 6), // 7 / 0 = all ones
		remi(8, 5, 6), // 7 % 0 = 7
		uType(minInt32, 9, opLUI),
		addi(10, 0, 0xFFF), // -1
		divi(11, 9, 10),    // overflow: stays minInt32
		remi(12, 9, 10),    // overflow: 0
	}, exitWith()...)
	m := run(t, prog, vmkit.NewTestHost())
	r := m.Registers()
	uassert.Equal(t, uint64(0xFFFFFFFF), uint64(r[7]))
	uassert.Equal(t, uint64(7), uint64(r[8]))
	uassert.Equal(t, uint64(minInt32), uint64(r[11]))
	uassert.Equal(t, uint64(0), uint64(r[12]))
}

// The syscall table is the whole interface between guest and chain.
func TestWriteSyscallReachesTheHost(t *testing.T) {
	// Store "hi" at 0x800, then write(1, 0x800, 2).
	prog := append([]uint32{
		addi(5, 0, 0x7F0),
		addi(6, 0, 'h'),
		sType(0, 6, 5, 0x0, opStore), // sb
		addi(6, 0, 'i'),
		sType(1, 6, 5, 0x0, opStore),
		addi(17, 0, sysWrite),
		addi(10, 0, 1),
		addi(11, 0, 0x7F0),
		addi(12, 0, 2),
		ecall(),
	}, exitWith()...)
	h := vmkit.NewTestHost()
	run(t, prog, h)
	uassert.Equal(t, "hi", h.OutString())
}

// A guest that exits non-zero has HALTED, not trapped: "your code said no" is
// not "the VM broke", and a chain should not conflate them.
func TestNonZeroExitIsStillHalted(t *testing.T) {
	prog := []uint32{addi(10, 0, 1), addi(17, 0, sysExit), ecall()}
	m, err := NewMachine(asm(prog), entry)
	uassert.NoError(t, err)
	_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, "", m.Trap())
	uassert.Equal(t, uint64(1), uint64(m.Registers()[10]))
}

func TestUnknownSyscallTraps(t *testing.T) {
	prog := []uint32{addi(17, 0, 777), ecall()}
	m, err := NewMachine(asm(prog), entry)
	uassert.NoError(t, err)
	_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "trapped", status.String())
	uassert.Equal(t, "unknown syscall", m.Trap())
}

func TestIllegalInstructionTraps(t *testing.T) {
	m, err := NewMachine(asm([]uint32{0xFFFFFFFF}), entry)
	uassert.NoError(t, err)
	_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "trapped", status.String())
}

func TestFuelStopsTheHart(t *testing.T) {
	prog := append([]uint32{
		addi(5, 0, 1), addi(5, 5, 1), addi(5, 5, 1), addi(5, 5, 1),
	}, exitWith()...)
	m, err := NewMachine(asm(prog), entry)
	uassert.NoError(t, err)
	used, status := m.Step(vmkit.NewTestHost(), 2)
	uassert.Equal(t, int64(2), used)
	uassert.Equal(t, "running", status.String())
	uassert.Equal(t, uint64(2), uint64(m.Registers()[5]))
}

// The property that makes a guest program a contract: slices must equal one go.
func TestSlicedRunEqualsOneShot(t *testing.T) {
	prog := append([]uint32{
		addi(5, 0, 0),
		addi(6, 0, 12),
		add(5, 5, 6),
		addi(6, 6, 0xFFF),
		bne(6, 0, 0x1FF8),
		addi(7, 0, 0x7F0),
		sw(5, 7, 0),
	}, exitWith()...)
	image := asm(prog)

	one, err := NewMachine(image, entry)
	uassert.NoError(t, err)
	one.Step(vmkit.NewTestHost(), vmkit.Unmetered)

	sliced, err := NewMachine(image, entry)
	uassert.NoError(t, err)
	h := vmkit.NewTestHost()
	status := vmkit.Running
	for i := 0; i < 5000 && status == vmkit.Running; i++ {
		fresh, err := NewMachine(image, entry)
		uassert.NoError(t, err)
		uassert.NoError(t, fresh.Restore(sliced.Snapshot()))
		_, status = fresh.Step(h, 3)
		sliced = fresh
	}
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, uint64(one.Registers()[5]), uint64(sliced.Registers()[5]))
	uassert.Equal(t, uint64(78), uint64(sliced.Registers()[5]))
}

// A 1 MiB address space must not cost 1 MiB to pause. This is the kill
// criterion vmkit set for continuations, measured rather than asserted.
func TestSnapshotCarriesOnlyTouchedPages(t *testing.T) {
	prog := append([]uint32{
		addi(5, 0, 0x7F0),
		addi(6, 0, 1),
		sw(6, 5, 0),
	}, exitWith()...)
	m := run(t, prog, vmkit.NewTestHost())

	// Two: the page holding the program at 0x1000, and the one holding the
	// store at 0x7F0. Two out of 256, which is the whole point.
	uassert.Equal(t, 2, m.Memory().DirtyPages())
	// The property is proportionality: a snapshot costs what the guest
	// touched plus a fixed header, not what the address space is. Two pages
	// out of 256 means about 8 KiB out of a megabyte.
	snap := m.Snapshot()
	pages := m.Memory().DirtyPages()
	uassert.True(t, len(snap) <= pages*PageSize+512,
		"a snapshot must not exceed its dirty pages plus a header")
	uassert.True(t, len(snap) < MemSize/100,
		"a snapshot of a lightly-used hart must be a rounding error against the address space")
}

func TestRestoreRejectsJunk(t *testing.T) {
	m, err := NewMachine(asm(exitWith()), entry)
	uassert.NoError(t, err)
	uassert.Error(t, m.Restore([]byte{}))
	uassert.Error(t, m.Restore([]byte{1, 2, 3, 4, 5}))

	good := m.Snapshot()
	bad := make([]byte, len(good))
	copy(bad, good)
	bad[4] = 99 // version
	uassert.ErrorIs(t, m.Restore(bad), vmkit.ErrBadSnapshot)
}

// vmkit's plumbing has to work for a second guest, which is the only way to
// know the ABI was not shaped around the first one.
func TestInstanceIntegration(t *testing.T) {
	prog := append([]uint32{addi(5, 0, 21), add(5, 5, 5)}, exitWith()...)
	image := asm(prog)

	inst := vmkit.NewInstance("001", address("g1x"), VMName, image, vmkit.Unmetered)
	h := vmkit.NewTestHost()
	for i := 0; i < 100 && inst.Status == vmkit.Running; i++ {
		m, err := NewMachine(image, entry)
		uassert.NoError(t, err)
		uassert.NoError(t, inst.Run(m, h, 2))
	}
	uassert.Equal(t, "halted", inst.Status.String())
	uassert.True(t, inst.Slices > 1)
}
