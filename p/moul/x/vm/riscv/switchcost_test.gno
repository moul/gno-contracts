package riscv

import "testing"

// Does the GnoVM dispatch a switch by jump table or by scanning the cases in
// order? The answer decides the interpreter's shape: predecoding an image into
// (op, rd, rs1, rs2, imm) arrays deletes the fetch and the field extraction,
// but it also flattens two small nested switches into one 48-case switch. If
// cases are scanned, that trade buys nothing and costs the deeper arms.
//
// The experiment: the same 48-case switch, driven to the first case and to the
// last. Equal cycles means a jump table. A large gap means a scan, and the
// switch has to stay shallow no matter what else changes.

//go:noinline
func switch48(v uint32) uint32 {
	switch v {
	case 0:
		return 1
	case 1:
		return 2
	case 2:
		return 3
	case 3:
		return 4
	case 4:
		return 5
	case 5:
		return 6
	case 6:
		return 7
	case 7:
		return 8
	case 8:
		return 9
	case 9:
		return 10
	case 10:
		return 11
	case 11:
		return 12
	case 12:
		return 13
	case 13:
		return 14
	case 14:
		return 15
	case 15:
		return 16
	case 16:
		return 17
	case 17:
		return 18
	case 18:
		return 19
	case 19:
		return 20
	case 20:
		return 21
	case 21:
		return 22
	case 22:
		return 23
	case 23:
		return 24
	case 24:
		return 25
	case 25:
		return 26
	case 26:
		return 27
	case 27:
		return 28
	case 28:
		return 29
	case 29:
		return 30
	case 30:
		return 31
	case 31:
		return 32
	case 32:
		return 33
	case 33:
		return 34
	case 34:
		return 35
	case 35:
		return 36
	case 36:
		return 37
	case 37:
		return 38
	case 38:
		return 39
	case 39:
		return 40
	case 40:
		return 41
	case 41:
		return 42
	case 42:
		return 43
	case 43:
		return 44
	case 44:
		return 45
	case 45:
		return 46
	case 46:
		return 47
	case 47:
		return 48
	}
	return 0
}

const switchIters = 200000

func TestSwitchCostFirstCase(t *testing.T) {
	var acc uint32
	for i := 0; i < switchIters; i++ {
		acc += switch48(0)
	}
	if acc == 0 {
		t.Fatal("unreachable")
	}
}

func TestSwitchCostLastCase(t *testing.T) {
	var acc uint32
	for i := 0; i < switchIters; i++ {
		acc += switch48(47)
	}
	if acc == 0 {
		t.Fatal("unreachable")
	}
}

// The control: the same loop with no switch at all, so the two above can be
// read net of loop and call overhead.
//
//go:noinline
func switchNone(v uint32) uint32 { return v + 1 }

func TestSwitchCostNoSwitch(t *testing.T) {
	var acc uint32
	for i := 0; i < switchIters; i++ {
		acc += switchNone(0)
	}
	if acc == 0 {
		t.Fatal("unreachable")
	}
}

// A scan means the question is no longer "how few cases" but "is there a
// dispatch that does not scan at all". These three isolate the alternatives:
// the bare loop, a direct call, and a call through a table indexed by opcode.

//go:noinline
func hADDI(v uint32) uint32 { return v + 1 }

//go:noinline
func hSUB(v uint32) uint32 { return v - 1 }

//go:noinline
func hXOR(v uint32) uint32 { return v ^ 1 }

//go:noinline
func hAND(v uint32) uint32 { return v & 1 }

var dispatchTable = [4]func(uint32) uint32{hADDI, hSUB, hXOR, hAND}

func TestDispatchLoopOnly(t *testing.T) {
	var acc uint32
	for i := 0; i < switchIters; i++ {
		acc += uint32(i) & 1
	}
	if acc == 0 {
		t.Fatal("unreachable")
	}
}

func TestDispatchTableCall(t *testing.T) {
	var acc uint32
	for i := 0; i < switchIters; i++ {
		acc += dispatchTable[3](1)
	}
	if acc == 0 {
		t.Fatal("unreachable")
	}
}

// What does memory cost? Predecode allocates five arrays per load and the
// address space allocates a megabyte, so the answer decides whether the
// predecode arrays should be built eagerly or only for words actually reached.

func TestAllocBytes1000(t *testing.T) {
	b := make([]byte, 4000)
	if len(b) != 4000 {
		t.Fatal("unreachable")
	}
}

func TestAllocBytes4000(t *testing.T) {
	b := make([]byte, 16000)
	if len(b) != 16000 {
		t.Fatal("unreachable")
	}
}

// The five arrays predecode builds, at the same two sizes.
func TestAllocArrays1000(t *testing.T) {
	a, b, c := make([]uint8, 1000), make([]uint8, 1000), make([]uint8, 1000)
	d, e := make([]uint8, 1000), make([]uint32, 1000)
	if len(a)+len(b)+len(c)+len(d)+len(e) == 0 {
		t.Fatal("unreachable")
	}
}

func TestAllocArrays4000(t *testing.T) {
	a, b, c := make([]uint8, 4000), make([]uint8, 4000), make([]uint8, 4000)
	d, e := make([]uint8, 4000), make([]uint32, 4000)
	if len(a)+len(b)+len(c)+len(d)+len(e) == 0 {
		t.Fatal("unreachable")
	}
}
