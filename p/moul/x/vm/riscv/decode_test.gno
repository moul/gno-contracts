package riscv

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// jal is only needed to exercise immJ, the one format no program in
// riscv_test.gno reaches for.
func jal(rd, imm uint32) uint32 { return jType(imm, rd, opJAL) }

// The assembler in riscv_test.gno and the decoders here were written from the
// spec independently, so encoding a known field and reading it back is a real
// cross-check rather than a tautology: a field in the wrong place fails unless
// both files put it in the same wrong place.
func TestDecodeRoundTripsTheAssembler(t *testing.T) {
	inst := add(5, 6, 7)
	uassert.Equal(t, uint64(opReg), uint64(opcode(inst)))
	uassert.Equal(t, uint64(5), uint64(rd(inst)))
	uassert.Equal(t, uint64(6), uint64(rs1(inst)))
	uassert.Equal(t, uint64(7), uint64(rs2(inst)))
	uassert.Equal(t, uint64(0), uint64(funct3(inst)))
	uassert.Equal(t, uint64(0), uint64(funct7(inst)))
	uassert.Equal(t, uint64(0x20), uint64(funct7(sub(5, 6, 7))))
	uassert.Equal(t, uint64(0x01), uint64(funct7(mul(5, 6, 7))))
}

// Every immediate in the base set is sign extended from its own top bit, and
// the top bit is in a different place in each of the five formats. These are
// the boundary values: the largest positive, the value one past it that must
// come back negative, and all-ones for minus one.
func TestImmediatesSignExtend(t *testing.T) {
	// I-type, 12 bits.
	uassert.Equal(t, uint64(0x7FF), uint64(immI(addi(1, 2, 0x7FF))))
	uassert.Equal(t, uint64(0xFFFFF800), uint64(immI(addi(1, 2, 0x800))))
	uassert.Equal(t, uint64(0xFFFFFFFF), uint64(immI(addi(1, 2, 0xFFF))))

	// S-type, 12 bits split across two fields.
	uassert.Equal(t, uint64(0x7FF), uint64(immS(sw(3, 4, 0x7FF))))
	uassert.Equal(t, uint64(0xFFFFF800), uint64(immS(sw(3, 4, 0x800))))
	uassert.Equal(t, uint64(0xFFFFFFFF), uint64(immS(sw(3, 4, 0xFFF))))

	// B-type, 13 bits with bit 0 always zero. -12 is the encoding the
	// benchmark's loop branch uses, and getting its width wrong is what makes
	// a backward branch jump forward instead.
	uassert.Equal(t, uint64(0x7FE), uint64(immB(bne(1, 2, 0x7FE))))
	uassert.Equal(t, uint64(0xFFFFF000), uint64(immB(bne(1, 2, 0x1000))))
	uassert.Equal(t, uint64(0xFFFFFFF4), uint64(immB(bne(1, 2, 0x1FF4))))

	// U-type is the only one that is not sign extended, because it is already
	// the top 20 bits.
	uassert.Equal(t, uint64(0xDEADB000), uint64(immU(lui(1, 0xDEADB000))))

	// J-type, 21 bits with bit 0 always zero.
	uassert.Equal(t, uint64(0x7FE), uint64(immJ(jal(1, 0x7FE))))
	uassert.Equal(t, uint64(0xFFF00000), uint64(immJ(jal(1, 0x100000))))
	uassert.Equal(t, uint64(0xFFFFFFFE), uint64(immJ(jal(1, 0x1FFFFE))))
}

func jalr(rd, rs1, imm uint32) uint32 { return iType(imm, rs1, 0x0, rd, opJALR) }
