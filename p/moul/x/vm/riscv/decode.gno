package riscv

// RV32 instruction decode: bit fields, not a parser.
//
// Every instruction is exactly 32 bits and the opcode is the low 7. The rest is
// slicing: which fields exist depends on the format, and there are six formats.
// This file is only the slicing; exec.gno decides what the fields mean.

// Instruction formats. Named as the spec names them.
const (
	opLUI    = 0x37
	opAUIPC  = 0x17
	opJAL    = 0x6F
	opJALR   = 0x67
	opBranch = 0x63
	opLoad   = 0x03
	opStore  = 0x23
	opImm    = 0x13
	opReg    = 0x33
	opSystem = 0x73
	opFence  = 0x0F
)

// opcode returns the low 7 bits.
func opcode(inst uint32) uint32 { return inst & 0x7F }

// rd, rs1 and rs2 are register selectors, 5 bits each, always in the same place
// when the format has them.
func rd(inst uint32) uint32  { return (inst >> 7) & 0x1F }
func rs1(inst uint32) uint32 { return (inst >> 15) & 0x1F }
func rs2(inst uint32) uint32 { return (inst >> 20) & 0x1F }

// funct3 and funct7 narrow an opcode to an operation.
func funct3(inst uint32) uint32 { return (inst >> 12) & 0x7 }
func funct7(inst uint32) uint32 { return inst >> 25 }

// The immediates. Each format scatters the bits differently, and every one of
// them is SIGN EXTENDED from its top bit: RISC-V has no zero-extended immediate
// in the base set, and getting that wrong is the classic decoder bug because
// small positive programs still work.
//
// The shift-right-on-int32 idiom is the sign extension: Go defines >> on a
// signed type as arithmetic.

// immI is the 12-bit immediate of I-type (loads, ALU-immediate, JALR, ECALL).
func immI(inst uint32) uint32 { return uint32(int32(inst) >> 20) }

// immS is S-type (stores), split across two fields.
func immS(inst uint32) uint32 {
	return uint32(int32(inst)>>25<<5) | ((inst >> 7) & 0x1F)
}

// immB is B-type (branches): S-type with the bits rotated, and bit 0 always
// zero because a branch target is 2-byte aligned.
func immB(inst uint32) uint32 {
	imm := uint32(int32(inst)>>31) << 12 // sign, bit 12
	imm |= ((inst >> 7) & 0x1) << 11     // bit 11
	imm |= ((inst >> 25) & 0x3F) << 5    // bits 10:5
	imm |= ((inst >> 8) & 0xF) << 1      // bits 4:1
	return imm
}

// immU is U-type (LUI, AUIPC): the top 20 bits, already in place.
func immU(inst uint32) uint32 { return inst & 0xFFFFF000 }

// immJ is J-type (JAL), the most scattered of the six.
func immJ(inst uint32) uint32 {
	imm := uint32(int32(inst)>>31) << 20 // sign, bit 20
	imm |= ((inst >> 12) & 0xFF) << 12   // bits 19:12
	imm |= ((inst >> 20) & 0x1) << 11    // bit 11
	imm |= ((inst >> 21) & 0x3FF) << 1   // bits 10:1
	return imm
}
