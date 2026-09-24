package riscv

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/uassert/v0"
)

// A guest compiled by a real compiler, which is the only test here that was
// not written by the same person who wrote the emulator.
//
// The image is guests.gno's, built from tools/riscv-guests/fnv by clang. It
// exercises what hand-written tests do not: a real function prologue spilling
// ra and s0 to a stack the host set up, .bss addressed far above a read-only
// text segment, LLVM's constant materialization through lui/addi pairs, and
// MUL in an inner loop.

// The expected hashes come from an independent FNV-1a, not from this VM.
func TestClangCompiledGuest(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"", "811c9dc5"},
		{"a", "e40c292c"},
		{"Hello", "f55c314b"},
		{"gno.land", "fb7ffba0"},
	}
	for _, c := range cases {
		m, err := NewMachine(GuestFNV(), entry)
		uassert.NoError(t, err)
		if m == nil {
			continue
		}
		h := vmkit.NewTestHost().WithInput([]byte(c.in))
		_, status := m.Step(h, vmkit.Unmetered)
		uassert.Equal(t, "halted", status.String(), "input "+c.in+": "+m.Trap())
		uassert.Equal(t, c.want, string(h.Out()), "fnv1a of "+c.in)
	}
}

// Compiled code pauses and resumes like anything else. This is the property a
// realm depends on, run against output a compiler produced rather than against
// a loop written to be sliceable.
func TestClangGuestSurvivesSlicing(t *testing.T) {
	image := GuestFNV()
	h := vmkit.NewTestHost().WithInput([]byte("gno.land"))

	sliced, err := NewMachine(image, entry)
	uassert.NoError(t, err)
	status := vmkit.Running
	slices := 0
	for i := 0; i < 500 && status == vmkit.Running; i++ {
		var fresh Machine
		uassert.NoError(t, fresh.Restore(sliced.Snapshot()))
		_, status = fresh.Step(h, 3)
		sliced = &fresh
		slices++
	}
	uassert.Equal(t, "halted", status.String())
	uassert.True(t, slices > 10, "a sliced run must actually have been sliced")
	uassert.Equal(t, "fb7ffba0", string(h.Out()))
}

// The guest writes its globals at 0x40000, which the linker script put well
// above the text segment on purpose. If it had put them adjacent, W xor X
// would trap on the first store, so this is the test that the memory layout
// the toolchain was told to use is the one the host actually provides.
func TestClangGuestWritesAboveItsText(t *testing.T) {
	m, err := NewMachine(GuestFNV(), entry)
	uassert.NoError(t, err)
	h := vmkit.NewTestHost().WithInput([]byte("gno.land"))
	_, status := m.Step(h, vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())

	// The text pages, the .bss page at 0x40000, and the stack page at the top.
	uassert.True(t, m.Memory().DirtyPages() >= 3,
		"the guest must have written outside its text segment")
	uassert.True(t, m.Memory().DirtyPages() <= 8,
		"a 196-byte program must not have dirtied the address space")
}

// Image is what every caller uses to turn words into a program, so a byte
// order mistake here would look like a decoder bug everywhere else.
func TestImageIsLittleEndian(t *testing.T) {
	b := Image([]uint32{0x04030201, 0xFF000000})
	uassert.Equal(t, 8, len(b))
	uassert.Equal(t, uint64(0x01), uint64(b[0]))
	uassert.Equal(t, uint64(0x04), uint64(b[3]))
	uassert.Equal(t, uint64(0x00), uint64(b[4]))
	uassert.Equal(t, uint64(0xFF), uint64(b[7]))

	// And it agrees with the assembler the other tests use.
	words := []uint32{addi(5, 0, 1), ecall()}
	a, i := asm(words), Image(words)
	uassert.Equal(t, len(a), len(i))
	for k := range a {
		uassert.Equal(t, uint64(a[k]), uint64(i[k]))
	}
}

// GuestFNV must not hand out a slice a caller can scribble on, because the
// next caller gets the same program.
func TestGuestFNVIsACopy(t *testing.T) {
	a := GuestFNV()
	a[0] = 0xFF
	b := GuestFNV()
	uassert.False(t, b[0] == 0xFF, "GuestFNV must return a fresh image each call")
}
