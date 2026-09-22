package bf

import (
	"errors"

	"gno.land/p/nt/ufmt/v0"
)

// TapeSize is the tape length of a compiled [Machine]. It matches
// [NaiveTapeSize] so that the ladder compares like with like: a rung that
// changed the semantics would not be a rung, it would be a different program.
const TapeSize = 30000

// MaxSource bounds the program a realm will accept. Compilation is linear in
// the source, but the op array and every snapshot of it are consensus state,
// so the size has to be bounded somewhere the caller can see.
const MaxSource = 64 * 1024

// ErrSourceTooLong is returned by [Compile] for a program above [MaxSource].
var ErrSourceTooLong = errors.New("bf: source too long")

// Level selects how far up the optimization ladder [Compile] goes.
//
// Every level produces the same output for the same program: the levels exist
// so the cost of each optimization can be measured in isolation, which is the
// published result this package is really for. Rung 0 of the ladder is
// [Execute] and has no compiler at all.
type Level int

const (
	// LevelJumps is rung 1: one op per source byte, with the jump targets
	// resolved at compile time. This is the rung that kills the brace
	// rescan, which in [Execute] costs O(loop body) on every iteration.
	LevelJumps Level = iota

	// LevelFuse is rung 2: runs of identical operators collapse, so
	// "+++++" is one add-5 and ">>>" is one move-3. Real programs are
	// mostly runs.
	LevelFuse

	// LevelIdioms is rung 3: a loop whose body only moves and adds, and
	// which returns to where it started while decrementing the current
	// cell by one, is replaced by the multiply-adds it performs plus a
	// clear. "[-]" becomes one op, "[->+<]" becomes two.
	LevelIdioms
)

// Default is the level [CompileDefault] uses, and the one a realm should
// want: every optimization this package knows, same semantics.
const Default = LevelIdioms

// String names the level, for the ladder table and for realm output.
func (l Level) String() string {
	switch l {
	case LevelJumps:
		return "jumps"
	case LevelFuse:
		return "fuse"
	case LevelIdioms:
		return "idioms"
	}
	return "unknown"
}

type opcode byte

const (
	opAdd    opcode = iota // tape[p] += arg           (arg normalized to 0..255)
	opMove                 // p += arg
	opOut                  // write tape[p] to the host
	opIn                   // read one input byte into tape[p]
	opJmpZ                 // if tape[p] == 0 { pc = arg }
	opJmpNZ                // if tape[p] != 0 { pc = arg }
	opSet                  // tape[p] = byte(arg)
	opAddMul               // tape[p+off] += tape[p] * byte(arg)
	opScan                 // while tape[p] != 0 { p += arg }
	opHalt                 // end of program
)

// op is one compiled instruction. It is a flat struct on purpose: the
// execution loop indexes an array of these, and an op that owned a slice
// would allocate in the hot path.
type op struct {
	code opcode
	arg  int
	off  int
}

// Program is compiled Brainfuck, ready to run on a [Machine].
type Program struct {
	ops   []op
	src   string
	level Level
}

// Source returns the program text the [Program] was compiled from.
func (p *Program) Source() string { return p.src }

// Level returns the ladder rung this program was compiled at.
func (p *Program) Level() Level { return p.level }

// Len returns the number of compiled ops, including the trailing halt. It is
// the number worth quoting next to the source length: the ratio is exactly
// what the ladder buys.
func (p *Program) Len() int { return len(p.ops) }

// CompileDefault compiles at [Default].
func CompileDefault(src string) (*Program, error) { return Compile(src, Default) }

// Compile turns Brainfuck source into a [Program] at the requested ladder
// level. Everything that is not one of the eight operators is a comment, as
// the language requires.
//
// It fails on unbalanced brackets rather than trusting the runtime to notice,
// which is the first thing that separates it from [Execute]: a malformed
// program is rejected before anybody pays to run it.
func Compile(src string, lvl Level) (*Program, error) {
	if len(src) > MaxSource {
		return nil, ErrSourceTooLong
	}
	if lvl < LevelJumps || lvl > LevelIdioms {
		return nil, ufmt.Errorf("bf: unknown level %d", int(lvl))
	}

	ops := []op{}
	opens := []int{} // pc of each unclosed opJmpZ

	for i := 0; i < len(src); i++ {
		c := src[i]
		switch c {
		case '+', '-':
			delta := 1
			if c == '-' {
				delta = -1
			}
			if lvl >= LevelFuse {
				n := 1
				for i+n < len(src) && (src[i+n] == '+' || src[i+n] == '-') {
					if src[i+n] == '+' {
						delta++
					} else {
						delta--
					}
					n++
				}
				i += n - 1
			}
			if a := normAdd(delta); a != 0 {
				ops = append(ops, op{code: opAdd, arg: a})
			}
		case '>', '<':
			delta := 1
			if c == '<' {
				delta = -1
			}
			if lvl >= LevelFuse {
				n := 1
				for i+n < len(src) && (src[i+n] == '>' || src[i+n] == '<') {
					if src[i+n] == '>' {
						delta++
					} else {
						delta--
					}
					n++
				}
				i += n - 1
			}
			if d := normMove(delta); d != 0 {
				ops = append(ops, op{code: opMove, arg: d})
			}
		case '.':
			ops = append(ops, op{code: opOut})
		case ',':
			ops = append(ops, op{code: opIn})
		case '[':
			opens = append(opens, len(ops))
			ops = append(ops, op{code: opJmpZ})
		case ']':
			if len(opens) == 0 {
				return nil, ufmt.Errorf("bf: unmatched ']' at byte %d", i)
			}
			open := opens[len(opens)-1]
			opens = opens[:len(opens)-1]

			if lvl >= LevelIdioms {
				if idiom, ok := simpleLoop(ops[open+1:]); ok {
					ops = append(ops[:open], idiom...)
					continue
				}
			}
			// pc lands on the op after the jump, so a jump target is
			// the index of the partner op itself.
			ops = append(ops, op{code: opJmpNZ, arg: open})
			ops[open].arg = len(ops) - 1
		}
	}
	if len(opens) != 0 {
		return nil, ufmt.Errorf("bf: %d unmatched '['", len(opens))
	}

	ops = append(ops, op{code: opHalt})
	return &Program{ops: ops, src: src, level: lvl}, nil
}

// normAdd folds a signed delta into the 0..255 the byte tape actually sees,
// so the execution loop never has to convert a negative int to a byte.
func normAdd(d int) int {
	d %= 256
	if d < 0 {
		d += 256
	}
	return d
}

// normMove folds a pointer delta into one lap of the tape. Moving right
// TapeSize times is a no-op on a wrapping tape, in the naive interpreter as
// much as here, so collapsing it changes nothing but the op count.
func normMove(d int) int {
	d %= TapeSize
	if d < 0 {
		d += TapeSize
	}
	if d > TapeSize/2 {
		d -= TapeSize
	}
	return d
}

// cell is one offset the body of a simple loop writes to.
type cell struct {
	off   int
	delta int
}

// simpleLoop decides whether a loop body can be replaced by straight-line
// code, and returns that code.
//
// Two shapes qualify, and they are the two that dominate real programs:
//
//   - The body only moves, and ends somewhere other than where it started:
//     that is a scan, "[>]" walking to the next zero cell.
//   - The body only moves and adds, ends where it started, and takes exactly
//     one off the current cell: that is a multiply-add. The loop runs
//     tape[p] times, so every other cell it touches gains its delta times
//     tape[p], and the current cell ends at zero. "[-]" is the degenerate
//     case with no other cells.
//
// Anything else, including any body containing I/O or a nested loop that was
// itself rewritten, is left alone. Being conservative here costs a few ops in
// rare programs and is the only reason this rewrite is safe at all: a loop
// whose current cell does not reach zero in steps of one is not guaranteed to
// terminate, and constant-folding it would change the program.
func simpleLoop(body []op) ([]op, bool) {
	cursor := 0
	cells := []cell{}
	adds := 0

	for _, o := range body {
		switch o.code {
		case opMove:
			cursor += o.arg
		case opAdd:
			adds++
			// Carry the delta as a signed value; it is normalized
			// back into 0..255 when it is emitted.
			d := o.arg
			if d > 128 {
				d -= 256
			}
			cells = addCell(cells, cursor, d)
		default:
			return nil, false
		}
	}

	if cursor != 0 {
		// Net movement: only a pure scan qualifies, and only when the
		// step is not zero (which normMove already guarantees here).
		if adds != 0 {
			return nil, false
		}
		return []op{{code: opScan, arg: cursor}}, true
	}

	// Balanced. The current cell must fall by exactly one per iteration,
	// or the loop is not a counted multiply-add.
	if delta(cells, 0) != -1 {
		return nil, false
	}

	out := []op{}
	for _, c := range cells {
		if c.off == 0 || c.delta == 0 {
			continue
		}
		out = append(out, op{code: opAddMul, arg: normAdd(c.delta), off: c.off})
	}
	out = append(out, op{code: opSet, arg: 0})
	return out, true
}

// addCell accumulates a delta at an offset, keeping cells sorted by offset so
// that the op stream a program compiles to is identical on every node.
func addCell(cells []cell, off, d int) []cell {
	for i := range cells {
		if cells[i].off == off {
			cells[i].delta += d
			return cells
		}
		if cells[i].off > off {
			cells = append(cells, cell{})
			copy(cells[i+1:], cells[i:])
			cells[i] = cell{off: off, delta: d}
			return cells
		}
	}
	return append(cells, cell{off: off, delta: d})
}

func delta(cells []cell, off int) int {
	for _, c := range cells {
		if c.off == off {
			return c.delta
		}
	}
	return 0
}
