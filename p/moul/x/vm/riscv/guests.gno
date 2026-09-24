package riscv

// Compiled guests: programs a real compiler produced, shipped as the bytes it
// emitted.
//
// A hand-written test program proves the emulator agrees with the person who
// wrote it. A compiled one proves it agrees with LLVM, which is the only claim
// that matters for a machine whose whole premise is that every toolchain
// already targets it.
//
// The source, the linker script and the exact build command are in
// tools/riscv-guests/. `make words` there prints the image in the form below,
// so this is reproducible rather than magic.

// guestFNV is tools/riscv-guests/fnv: it reads the call input, hashes it with
// FNV-1a, and writes eight hex digits back. 49 instructions, built with clang
// 19.1.7, `-march=rv32im -mabi=ilp32 -Os`.
//
// Worth reading as output rather than as a program. LLVM opens with a real
// function prologue spilling ra and s0 to a stack the host set up, materializes
// the 2166136261 offset basis as a lui/addi pair, and addresses its globals at
// 0x40000, far above a text segment the host refuses stores into.
var guestFNV = []uint32{
	0xFF010113, 0x00112623, 0x00812423, 0x01010413,
	0x000405B7, 0x00058593, 0x03F00893, 0x10000613,
	0x00000513, 0x00000073, 0x811CA6B7, 0x02A05663,
	0x00A58633, 0xDC568513, 0x010006B7, 0x19368693,
	0x0005C703, 0x00E54533, 0x00158593, 0x02D50533,
	0xFEC598E3, 0x0080006F, 0xDC568513, 0x01C00593,
	0x00040637, 0x10060613, 0x00A00693, 0xFFC00713,
	0x00B557B3, 0x00F7F793, 0x00D7E663, 0x05778793,
	0x0080006F, 0x03078793, 0x00F60023, 0xFFC58593,
	0x00160613, 0xFCE59EE3, 0x000405B7, 0x10058593,
	0x04000893, 0x00800613, 0x00100513, 0x00000073,
	0x05D00893, 0x00000593, 0x00000613, 0x00000513,
	0x00000073,
}

// GuestFNV returns the flat text image of the compiled FNV-1a guest, ready for
// [NewMachine] at [DefaultEntry]. A fresh slice per call, so a caller cannot
// mutate the copy everyone else gets.
func GuestFNV() []byte { return Image(guestFNV) }

// Image serializes instruction words little-endian, which is what RV32 is.
// Exported because anything assembling a program has to do exactly this, and
// getting the byte order wrong produces a decoder error a long way from the
// mistake.
func Image(words []uint32) []byte {
	b := make([]byte, 0, len(words)*4)
	for _, w := range words {
		b = append(b, byte(w), byte(w>>8), byte(w>>16), byte(w>>24))
	}
	return b
}
