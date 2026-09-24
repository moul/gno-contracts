package riscv

// Predecode: the image is turned into fields once, at load, and the dispatch
// loop only indexes arrays.
//
// Two measurements forced this shape, both in switchcost_test.gno:
//
//   - The GnoVM scans switch cases in source order. Reaching case 47 of a
//     48-case switch costs 13,358 gas against 292 for case 0, a measured 278
//     gas per case skipped. So the internal opcodes below are ordered by how
//     often compiled code actually executes them, and that ordering is a
//     performance decision, not a stylistic one. Do not sort this list.
//   - An elementary operation costs on the order of 280 gas. Fetching four
//     bytes and reassembling them is fourteen of those, on every instruction,
//     forever. Doing it once per word instead is the single largest saving
//     available to an interpreter here.
//
// The decoders in decode.gno are used verbatim below rather than inlined,
// because predecode runs once per word in the image and not once per executed
// instruction. That is the point: the expensive, readable code moved off the
// hot path instead of being duplicated onto it.

// Internal opcodes, ordered by expected dynamic frequency in compiled code.
// The first dozen are what a loop nest and a function prologue are made of.
const (
	iADDI uint8 = iota
	iLW
	iSW
	iADD
	iBNE
	iBEQ
	iJAL
	iJALR
	iLUI
	iSLLI
	iSRLI
	iANDI
	iSUB
	iORI
	iXORI
	iBLT
	iBGE
	iBLTU
	iBGEU
	iSRAI
	iSLL
	iSRL
	iSRA
	iAND
	iOR
	iXOR
	iLBU
	iLB
	iLH
	iLHU
	iSB
	iSH
	iAUIPC
	iSLT
	iSLTU
	iSLTI
	iSLTIU
	iMUL
	iMULH
	iMULHSU
	iMULHU
	iDIV
	iDIVU
	iREM
	iREMU
	iECALL
	iEBREAK
	iFENCE
	iILLEGAL
)

// code is an image with its fields already pulled apart. Parallel arrays, not
// a slice of structs: an arm reads three or four fields, and paying for the
// ones it does not read is the cost this whole file exists to avoid.
type code struct {
	base  uint32 // the address word 0 sits at
	words uint32 // how many instructions the text segment holds
	end   uint32 // base + 4*words, the first address past the text
	op    []uint8
	rd    []uint8
	rs1   []uint8
	rs2   []uint8
	imm   []uint32
}

// predecode walks an image and records, for every word, what it is and what
// its operands are. A word that is not an instruction becomes iILLEGAL and
// traps only if it is ever executed, which is what keeps a constant pool in
// the middle of a text segment legal.
func predecode(base uint32, img []byte) *code {
	n := uint32(len(img) / 4)
	c := &code{
		base:  base,
		words: n,
		end:   base + n*4,
		op:    make([]uint8, n),
		rd:    make([]uint8, n),
		rs1:   make([]uint8, n),
		rs2:   make([]uint8, n),
		imm:   make([]uint32, n),
	}
	for i := uint32(0); i < n; i++ {
		j := i * 4
		inst := uint32(img[j]) | uint32(img[j+1])<<8 |
			uint32(img[j+2])<<16 | uint32(img[j+3])<<24
		op, imm := decodeWord(inst)
		c.op[i] = op
		c.imm[i] = imm
		// The three register selectors are in the same place in every format
		// that has them, and are harmless in the formats that do not, so they
		// are taken unconditionally and spelled out: this loop already costs
		// more than executing the instruction does.
		c.rd[i] = uint8((inst >> 7) & 0x1F)
		c.rs1[i] = uint8((inst >> 15) & 0x1F)
		c.rs2[i] = uint8((inst >> 20) & 0x1F)
	}
	return c
}

// decodeWord returns both the internal opcode and the immediate, in one pass.
//
// They were two functions once, and splitting them cost 22 case labels: the
// second switch had to ask all over again which format the instruction was, and
// the GnoVM scans case labels one at a time. Deciding both in the arm that
// already knows the answer took predecode from 31.4k gas per word to 19.6k.
//
// The immediate decoders are still called rather than inlined. This runs once
// per word in the image, not once per executed instruction, and sign extension
// is the subtle part of RV32 decoding: it belongs in one place, spelled out,
// with decode_test.gno round-tripping it against the assembler.
func decodeWord(inst uint32) (uint8, uint32) {
	f3 := funct3(inst)
	switch opcode(inst) {
	case opImm:
		imm := immI(inst)
		switch f3 {
		case 0x0:
			return iADDI, imm
		case 0x1:
			return iSLLI, imm
		case 0x2:
			return iSLTI, imm
		case 0x3:
			return iSLTIU, imm
		case 0x4:
			return iXORI, imm
		case 0x5:
			if funct7(inst) == 0x20 {
				return iSRAI, imm
			}
			return iSRLI, imm
		case 0x6:
			return iORI, imm
		case 0x7:
			return iANDI, imm
		}
	case opLoad:
		imm := immI(inst)
		switch f3 {
		case 0x0:
			return iLB, imm
		case 0x1:
			return iLH, imm
		case 0x2:
			return iLW, imm
		case 0x4:
			return iLBU, imm
		case 0x5:
			return iLHU, imm
		}
	case opStore:
		imm := immS(inst)
		switch f3 {
		case 0x0:
			return iSB, imm
		case 0x1:
			return iSH, imm
		case 0x2:
			return iSW, imm
		}
	case opReg:
		f7 := funct7(inst)
		if f7 == 0x01 {
			switch f3 {
			case 0x0:
				return iMUL, 0
			case 0x1:
				return iMULH, 0
			case 0x2:
				return iMULHSU, 0
			case 0x3:
				return iMULHU, 0
			case 0x4:
				return iDIV, 0
			case 0x5:
				return iDIVU, 0
			case 0x6:
				return iREM, 0
			case 0x7:
				return iREMU, 0
			}
		}
		switch f3 {
		case 0x0:
			if f7 == 0x20 {
				return iSUB, 0
			}
			return iADD, 0
		case 0x1:
			return iSLL, 0
		case 0x2:
			return iSLT, 0
		case 0x3:
			return iSLTU, 0
		case 0x4:
			return iXOR, 0
		case 0x5:
			if f7 == 0x20 {
				return iSRA, 0
			}
			return iSRL, 0
		case 0x6:
			return iOR, 0
		case 0x7:
			return iAND, 0
		}
	case opBranch:
		imm := immB(inst)
		switch f3 {
		case 0x0:
			return iBEQ, imm
		case 0x1:
			return iBNE, imm
		case 0x4:
			return iBLT, imm
		case 0x5:
			return iBGE, imm
		case 0x6:
			return iBLTU, imm
		case 0x7:
			return iBGEU, imm
		}
	case opLUI:
		return iLUI, immU(inst)
	case opAUIPC:
		return iAUIPC, immU(inst)
	case opJAL:
		return iJAL, immJ(inst)
	case opJALR:
		if f3 == 0x0 {
			return iJALR, immI(inst)
		}
	case opFence:
		return iFENCE, 0
	case opSystem:
		if immI(inst) == 0 {
			return iECALL, 0
		}
		return iEBREAK, 0
	}
	return iILLEGAL, 0
}
