package riscv

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/uassert/v0"
)

// classify collapses the spec's opcode / funct3 / funct7 tree onto one byte,
// and every arm of the dispatch loop trusts it. These are the pairs that share
// a funct3 and differ only in funct7, which is where a collapse goes wrong.
func TestClassifySeparatesTheAmbiguousPairs(t *testing.T) {
	cases := []struct {
		inst uint32
		want uint8
	}{
		{add(1, 2, 3), iADD},
		{sub(1, 2, 3), iSUB},
		{mul(1, 2, 3), iMUL},
		{divi(1, 2, 3), iDIV},
		{remi(1, 2, 3), iREM},
		{addi(1, 2, 5), iADDI},
		{lw(1, 2, 0), iLW},
		{lbu(1, 2, 0), iLBU},
		{sw(1, 2, 0), iSW},
		{bne(1, 2, 4), iBNE},
		{lui(1, 0x1000), iLUI},
		{jal(1, 4), iJAL},
		{ecall(), iECALL},
		{0, iILLEGAL},
	}
	for _, c := range cases {
		op, _ := decodeWord(c.inst)
		uassert.Equal(t, uint64(c.want), uint64(op))
	}
}

// A restored hart has to predecode again, because the arrays are not in the
// snapshot: only the memory pages are. Restoring into a machine that has never
// seen the image is the path a realm actually takes between transactions, and
// it is the one the existing slice test did not cover, because it always
// restored into a machine NewMachine had already loaded.
func TestRestoreIntoABareMachine(t *testing.T) {
	prog := append([]uint32{
		addi(5, 0, 0),
		addi(6, 0, 10),
		add(5, 5, 6),
		addi(6, 6, 0xFFF), // -1
		bne(6, 0, 0x1FF8), // -8
	}, exitWith()...)
	image := asm(prog)

	one, err := NewMachine(image, entry)
	uassert.NoError(t, err)
	one.Step(vmkit.NewTestHost(), vmkit.Unmetered)

	part, err := NewMachine(image, entry)
	uassert.NoError(t, err)
	_, status := part.Step(vmkit.NewTestHost(), 7)
	uassert.Equal(t, "running", status.String())

	var bare Machine
	uassert.NoError(t, bare.Restore(part.Snapshot()))
	_, status = bare.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, uint64(one.Registers()[5]), uint64(bare.Registers()[5]))
	uassert.Equal(t, uint64(55), uint64(bare.Registers()[5]))
}

// Predecoding is only sound if the text cannot change under it, so a store
// into the text segment is a trap rather than a silent disagreement between
// the arrays and the memory. That is W xor X, which is what an ELF text
// segment is anyway, and it removes self-modifying code from the VM entirely.
func TestStoreIntoTextTraps(t *testing.T) {
	prog := append(li(5, entry), addi(6, 0, 1), sw(6, 5, 0))
	prog = append(prog, exitWith()...)
	m, err := NewMachine(asm(prog), entry)
	uassert.NoError(t, err)
	_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "trapped", status.String())
	uassert.Equal(t, "store into text segment", m.Trap())
}

// A store just below the text segment is legal, or the trap above would be
// catching the wrong thing.
func TestStoreBelowTextIsFine(t *testing.T) {
	prog := append(li(5, entry-4), addi(6, 0, 7), sw(6, 5, 0))
	prog = append(prog, exitWith()...)
	m, err := NewMachine(asm(prog), entry)
	uassert.NoError(t, err)
	_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	v, ok := m.Memory().Load32(entry - 4)
	uassert.True(t, ok)
	uassert.Equal(t, uint64(7), uint64(v))
}

// A halted hart points past the ecall it halted on, not at it. The deferred
// write-back is the only thing that sets m.pc, so an arm that assigned m.pc
// directly had its assignment silently undone on the way out.
func TestHaltedPCIsPastTheEcall(t *testing.T) {
	m, err := NewMachine(asm(exitWith()), entry)
	uassert.NoError(t, err)
	_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	// entry: addi a7, x0, 93 -- entry+4: ecall -- so the next pc is entry+8.
	uassert.Equal(t, uint64(entry+8), uint64(m.PC()))
}

// An entry point or an image that is not a whole number of instructions has no
// predecode, so it is refused at load rather than half-executed.
func TestNewMachineRefusesMisalignedImages(t *testing.T) {
	_, err := NewMachine(asm(exitWith()), entry+1)
	uassert.Error(t, err)
	_, err = NewMachine([]byte{1, 2, 3}, entry)
	uassert.Error(t, err)
}

// The index into the predecoded arrays is a shift, so a pc that is not
// 4-aligned would silently execute the word containing it. Only a snapshot can
// deliver one, because JALR checks its own target, so the guard is at entry to
// the loop rather than inside it.
func TestMisalignedPCTraps(t *testing.T) {
	m, err := NewMachine(asm(exitWith()), entry)
	uassert.NoError(t, err)
	m.pc = entry + 2
	_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "trapped", status.String())
	uassert.Equal(t, "misaligned program counter", m.Trap())
}

// JALR is the only instruction that can compute an odd target, and it clears
// only bit 0, so a target of 2 mod 4 has to be refused where it is made.
func TestJalrRefusesAMisalignedTarget(t *testing.T) {
	prog := append(li(5, entry+6), []uint32{jalr(1, 5, 0)}...)
	prog = append(prog, exitWith()...)
	m, err := NewMachine(asm(prog), entry)
	uassert.NoError(t, err)
	_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
	uassert.Equal(t, "trapped", status.String())
	uassert.Equal(t, "misaligned jump target", m.Trap())
}
