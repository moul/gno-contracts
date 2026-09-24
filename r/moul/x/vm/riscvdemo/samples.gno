package riscvdemo

import "gno.land/p/moul/x/vm/riscv/v0"

// The programs the front page offers, as the machine words a cross compiler
// would have emitted. They are assembled outside this repo and pinned here,
// and riscvdemo_test.gno runs every one of them to the expected answer, so a
// wrong word is a failing test rather than a page that traps when clicked.
type sample struct {
	slug   string // what UploadSample takes: short, no punctuation, stable
	name   string
	budget int64 // the instance's total instruction budget, not the slice

	// builtin names an image the library ships compiled, instead of the words
	// below. Empty means the words are the program.
	builtin string
	words []uint32
	input string
	note  string
	asm   string
}

var samples = []sample{
	{
		slug: "hello",
		name: "Hello, gno.land",
		words: []uint32{
			0x00100513, 0x000015B7, 0x02058593, 0x01000613,
			0x04000893, 0x00000073, 0x05D00893, 0x00000073,
			0x6C6C6548, 0x67202C6F, 0x6C2E6F6E, 0x0A646E61,
		},
		budget: 1000,
		note: "Eight instructions and a string constant. The write syscall reads " +
			"the bytes straight out of the text segment and hands them to Host.Output.",
		asm: `addi a0, zero, 1          # fd
lui  a1, 0x1000           # buf
addi a1, a1, 0x20
addi a2, zero, 16         # len
addi a7, zero, 64         # write
ecall
addi a7, zero, 93         # exit
ecall
.ascii "Hello, gno.land\n"`,
	},
	{
		slug: "sum100",
		name: "Sum 1 to 100",
		words: []uint32{
			0x06400413, 0x00000293, 0x00000313, 0x00130313,
			0x006282B3, 0xFE831CE3, 0x05D00893, 0x00000073,
		},
		budget: 1000,
		note: "A real loop, 303 instructions. Writes nothing: the answer is in t0, " +
			"and the instance page shows the register file.",
		asm: `addi s0, zero, 100
addi t0, zero, 0
addi t1, zero, 0
loop:
addi t1, t1, 1
add  t0, t0, t1
bne  t1, s0, loop
addi a7, zero, 93
ecall`,
	},
	{
		slug: "heavy",
		name: "Heavy loop",
		words: []uint32{
			0x0000C437, 0x35040413, 0x00000293, 0x00000313,
			0x00130313, 0x006282B3, 0x00000393, 0xFE831AE3,
			0x05D00893, 0x00000073,
		},
		budget: 250000,
		note: "200,006 instructions, four per iteration. At the largest slice this realm " +
			"allows it takes three transactions to finish, which is the thing it exists to show.",
		asm: `lui  s0, 0xc000           # s0 = 50000
addi s0, s0, 0x350
addi t0, zero, 0
addi t1, zero, 0
loop:
addi t1, t1, 1
add  t0, t0, t1
addi t2, zero, 0
bne  t1, s0, loop
addi a7, zero, 93
ecall`,
	},
	{
		slug: "mext",
		name: "Multiply and divide",
		words: []uint32{
			0x3B9AD2B7, 0xA0728293, 0x00300313, 0x026282B3,
			0x00700393, 0x0272D333, 0x05D00893, 0x00000073,
		},
		budget: 1000,
		note: "The M extension. t0 = 1000000007 * 3 truncated to 32 bits, then t1 = t0 / 7. " +
			"Division by zero and the one signed overflow case return values here " +
			"rather than trapping, which is what the spec says and what a chain needs.",
		asm: `lui  t0, 0x3b9ad000       # t0 = 1000000007
addi t0, t0, -1529
addi t1, zero, 3
mul  t0, t0, t1
addi t2, zero, 7
divu t1, t0, t2
addi a7, zero, 93
ecall`,
	},
	{
		slug:   "clang",
		name:   "Compiled by clang",
		input:  "gno.land",
		budget: 20000,
		note: "Not written for gno and not written by hand: a freestanding C program, " +
			"compiled by clang for riscv32im and shipped as the bytes LLVM emitted. It reads " +
			"the call input, hashes it with FNV-1a and writes eight hex digits back. " +
			"With the default input it prints fb7ffba0. Source and build command: " +
			"tools/riscv-guests/fnv.",
		builtin: "fnv",
		asm: `long n = syscall3(SYS_READ, 0, (long)in, sizeof(in));

unsigned int h = 2166136261u;
for (long i = 0; i < n; i++) {
	h ^= in[i];
	h *= 16777619u;      /* the reason this is rv32im */
}

for (int i = 0; i < 8; i++) {
	unsigned int nib = (h >> (28 - i * 4)) & 0xF;
	out[i] = nib < 10 ? '0' + nib : 'a' + (nib - 10);
}

syscall3(SYS_WRITE, 1, (long)out, 8);
syscall3(SYS_EXIT, 0, 0, 0);`,
	},
}

// image is what gets uploaded: either the words assembled here, or a program
// the library ships because a compiler produced it.
func (s *sample) image() []byte {
	if s.builtin == "fnv" {
		return riscv.GuestFNV()
	}
	return riscv.Image(s.words)
}

// lang is the fence tag for what the sample shows. The compiled guest shows
// its C, because showing a disassembly of what LLVM did with it would bury the
// only interesting fact: nobody wrote the machine code.
func (s *sample) lang() string {
	if s.builtin != "" {
		return "c"
	}
	return "asm"
}

func sampleByName(slug string) *sample {
	for i := range samples {
		if samples[i].slug == slug {
			return &samples[i]
		}
	}
	return nil
}
