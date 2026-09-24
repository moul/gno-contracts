package riscv

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/uassert/v0"
)

// The measurement the design issue set a kill criterion against: if an RV32I
// instruction costs more than roughly 15k cycles after the bf ladder's tricks,
// a RISC-V guest runs ~200k instructions per block, which is a token transfer
// and not a program a Rust programmer would write without thinking about it.
//
// The loop is arithmetic and branches only, no syscalls and no memory beyond
// the fetch, so it measures the decode-and-dispatch path rather than the host.

// li loads a full 32-bit constant, because addi cannot: its immediate is 12
// bits SIGN EXTENDED, so addi(rd, x0, 4000) loads -96 and a loop counting up to
// it never terminates. That is not hypothetical, it hung this benchmark for two
// days. The +0x800 pre-bias is the standard correction: it cancels the sign
// extension addi is about to apply to the low half.
func li(rd, v uint32) []uint32 {
	return []uint32{
		lui(rd, (v+0x800)&0xFFFFF000),
		addi(rd, rd, v&0xFFF),
	}
}

func lui(rd, imm uint32) uint32 { return uType(imm, rd, opLUI) }

// benchProg counts x6 up to x8 in a 4-instruction loop, then exits.
func benchProg(n uint32) []uint32 {
	prog := li(8, n) // x8 = n, the loop bound
	prog = append(prog,
		addi(5, 0, 0), // sum = 0
		addi(6, 0, 0), // i   = 0
		// loop:
		add(5, 5, 6),      // sum += i
		addi(6, 6, 1),     // i++
		addi(7, 0, 0),     // filler, keeps the loop a round 4 instructions
		bne(6, 8, 0x1FF4), // -12, while i != x8
	)
	return append(prog, exitWith()...)
}

// benchInstrs is how many instructions benchProg(n) executes: 4 setup (li is
// two), 4 per iteration including the branch, 2 to exit.
func benchInstrs(n int64) int64 { return 4 + 4*n + 2 }

// runBench returns the instruction count the machine charged itself. The fuel
// cap is ten times what the program should need: a mis-encoded immediate turns
// an unmetered run into an infinite loop with no test output, so the budget is
// what makes a bad encoding fail in a second instead of hanging the suite.
func runBench(t *testing.T, n uint32) int64 {
	t.Helper()
	m, err := NewMachine(asm(benchProg(n)), entry)
	uassert.NoError(t, err)
	if m == nil {
		return 0
	}
	used, status := m.Step(vmkit.NewTestHost(), benchInstrs(int64(n))*10)
	uassert.Equal(t, "halted", status.String())
	return used
}

// One test per size, so `gno test -print-runtime-metrics` prints one cycle
// count each and the slope cancels the fixed per-test overhead. The README
// quotes the result.

func TestBenchRV32I1000(t *testing.T) {
	uassert.Equal(t, benchInstrs(1000), runBench(t, 1000))
}

func TestBenchRV32I4000(t *testing.T) {
	uassert.Equal(t, benchInstrs(4000), runBench(t, 4000))
}

// li has to survive the sign-extension boundary in both directions, or the two
// sizes above are not measuring the loop counts they claim to.
func TestLoadImmediateSpansTheSignBoundary(t *testing.T) {
	for _, v := range []uint32{0, 1, 0x7FF, 0x800, 1000, 4000, 0x7FFFFFFF, 0xFFFFFFFF} {
		prog := append(li(5, v), exitWith()...)
		m, err := NewMachine(asm(prog), entry)
		uassert.NoError(t, err)
		if m == nil {
			continue
		}
		_, status := m.Step(vmkit.NewTestHost(), vmkit.Unmetered)
		uassert.Equal(t, "halted", status.String())
		uassert.Equal(t, uint64(v), uint64(m.reg[5]))
	}
}

// Predecoding is paid once per load, and a realm loads a machine on every
// transaction that resumes one. So the saving on the dispatch loop is only
// real if this side of the trade is small against the instructions the slice
// then executes. Two sizes again, so the slope is per word.
func benchImage(words int) []byte {
	img := make([]byte, words*4)
	inst := addi(5, 5, 1)
	for i := 0; i < words; i++ {
		img[i*4] = byte(inst)
		img[i*4+1] = byte(inst >> 8)
		img[i*4+2] = byte(inst >> 16)
		img[i*4+3] = byte(inst >> 24)
	}
	return img
}

func TestBenchPredecode1000(t *testing.T) {
	c := predecode(entry, benchImage(1000))
	uassert.Equal(t, uint64(1000), uint64(c.words))
}

func TestBenchPredecode4000(t *testing.T) {
	c := predecode(entry, benchImage(4000))
	uassert.Equal(t, uint64(4000), uint64(c.words))
}

// The control, so the slope above is predecode and not the loop that builds
// the image.
func TestBenchImageOnly1000(t *testing.T) {
	uassert.Equal(t, 4000, len(benchImage(1000)))
}

func TestBenchImageOnly4000(t *testing.T) {
	uassert.Equal(t, 16000, len(benchImage(4000)))
}
