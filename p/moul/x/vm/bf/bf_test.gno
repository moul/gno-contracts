package bf

import (
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/uassert/v0"
)

// hello is the classic 106 byte hello-world. It writes "Hello World", 11
// bytes: the original run.gno comment was optimistic about the trailing "!\n".
const hello = "++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------."

// corpus is the set of programs every ladder level must agree on. Each one is
// here because it exercises a rewrite that could plausibly be wrong.
var corpus = []struct {
	name string
	src  string
	want string
}{
	{"empty", "", ""},
	{"comment only", "this is not brainfuck", ""},
	{"hello", hello, "Hello World"},
	{"clear idiom", "+++++[-]+++++++++++++++++++++++++++++++++++++++++++++++.", "/"},
	{"move idiom", "+++++++++++++++++++++++++++++++++++++++++++++++++++[->+<]>.", "3"},
	{"multiply idiom", "+++++[->++++++++++<]>++.", "4"},
	{"two targets", "+++[->+>++<<]>+++++++++++++++++++++++++++++++++++++++.>+++++++++++++++++++++++++++++++++++++++++.", "*/"},
	{"scan walks", ">+>+>+>+[<]++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++.", "H"},
	{"scan right", ">>>+++++++++<<<[>]+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++.", "?"},
	{"nested loops", "++[>++[>+<-]<-]>>+++++++++++++++++++++++++++++++++++++++++++++++++.", "5"},
	{"dead run", "+++--+++--+++++++++++++++++++++++++++++++++++++++++++.", "-"},
	{"skipped loop", "[++++++++++++++++++++]+++++++++++++++++++++++++++++++++++++++++++++++.", "/"},
	{"wraps under zero", "-[>+<-]>++++++++++.", "\t"},
}

func runLevel(t *testing.T, src string, lvl Level, input string) string {
	t.Helper()
	prog, err := Compile(src, lvl)
	uassert.NoError(t, err)
	if prog == nil {
		return ""
	}
	h := vmkit.NewTestHost().WithInput([]byte(input))
	m := NewMachine(prog)
	_, status := m.Step(h, vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	return h.OutString()
}

// TestLadderLevelsAgree is the test the whole ladder rests on: an
// optimization that changes the output is not an optimization.
func TestLadderLevelsAgree(t *testing.T) {
	for _, tc := range corpus {
		naive := Execute(tc.src)
		uassert.Equal(t, tc.want, naive)

		for _, lvl := range []Level{LevelJumps, LevelFuse, LevelIdioms} {
			got := runLevel(t, tc.src, lvl, "")
			if got != tc.want {
				t.Errorf("%s at level %s: got %q, want %q",
					tc.name, lvl.String(), got, tc.want)
			}
		}
	}
}

func TestExecuteBaseline(t *testing.T) {
	// Rung 0 is kept verbatim, so this is also a regression test on the
	// thing the published cycles-per-op number was measured against.
	uassert.Equal(t, "Hello World", Execute(hello))
	uassert.Equal(t, 11, len(Execute(hello)))
}

func TestCompileRejectsUnbalanced(t *testing.T) {
	cases := []string{"[", "]", "[[]", "+[->+<", "][", "[[[]]"}
	for _, src := range cases {
		_, err := CompileDefault(src)
		if err == nil {
			t.Errorf("Compile(%q) should have failed", src)
		}
	}
}

func TestCompileRejectsOversizeSource(t *testing.T) {
	src := "+"
	for len(src) <= MaxSource {
		src += src // doubling, not O(n^2) appending
	}
	_, err := CompileDefault(src)
	uassert.ErrorIs(t, err, ErrSourceTooLong)
}

func TestCompileRejectsUnknownLevel(t *testing.T) {
	_, err := Compile("+", Level(42))
	uassert.Error(t, err)
	_, err = Compile("+", Level(-1))
	uassert.Error(t, err)
}

// TestLadderShrinksTheOpStream is the compile-time half of the ladder: each
// rung has to produce strictly fewer ops than the one below it, or it is not
// buying anything.
func TestLadderShrinksTheOpStream(t *testing.T) {
	jumps, err := Compile(hello, LevelJumps)
	uassert.NoError(t, err)
	fuse, err := Compile(hello, LevelFuse)
	uassert.NoError(t, err)
	idioms, err := Compile(hello, LevelIdioms)
	uassert.NoError(t, err)

	uassert.True(t, jumps.Len() > fuse.Len())
	uassert.True(t, fuse.Len() > idioms.Len())
	uassert.Equal(t, "jumps", jumps.Level().String())
	uassert.Equal(t, hello, idioms.Source())
}

func TestIdiomRecognition(t *testing.T) {
	cases := []struct {
		name string
		src  string
		want int // ops, excluding the trailing halt
	}{
		{"clear", "[-]", 1},                 // opSet
		{"move", "[->+<]", 2},               // opAddMul, opSet
		{"multiply two", "[->++>+++<<]", 3}, // two opAddMul, opSet
		{"scan right", "[>]", 1},            // opScan
		{"scan left", "[<]", 1},             // opScan
	}
	for _, tc := range cases {
		prog, err := Compile(tc.src, LevelIdioms)
		uassert.NoError(t, err)
		if prog == nil {
			continue
		}
		if got := prog.Len() - 1; got != tc.want {
			t.Errorf("%s: %q compiled to %d ops, want %d",
				tc.name, tc.src, got, tc.want)
		}
	}
}

// TestPlusLoopIsNotRewritten pins the conservative half of the rewrite: a
// loop that adds one per iteration still reaches zero by wrapping, but only
// after 256 iterations, and folding it would be a different program. It has
// to stay a real loop.
func TestPlusLoopIsNotRewritten(t *testing.T) {
	prog, err := Compile("[+]", LevelIdioms)
	uassert.NoError(t, err)
	// opJmpZ, opAdd, opJmpNZ, opHalt: untouched.
	uassert.Equal(t, 4, prog.Len())
}

func TestInputThroughTheHost(t *testing.T) {
	// Read three bytes and echo them back.
	const echo3 = ",.,.,."
	h := vmkit.NewTestHost().WithInput([]byte("gno"))
	m, err := Load(echo3)
	uassert.NoError(t, err)
	_, status := m.Step(h, vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, "gno", h.OutString())
}

func TestInputEndsAsZero(t *testing.T) {
	// Past the end of input, `,` yields a zero cell. Without input at all,
	// the naive interpreter would have panicked here.
	h := vmkit.NewTestHost().WithInput([]byte("a"))
	m, err := Load(",.+++++++++++++++++++++++++++++++++++++++++++++++.,+++++++++++++++++++++++++++++++++++++++++++++++++.")
	uassert.NoError(t, err)
	_, status := m.Step(h, vmkit.Unmetered)
	uassert.Equal(t, "halted", status.String())
	uassert.Equal(t, "a\x901", h.OutString())
}

func TestExecutePanicsOnInput(cur realm, t *testing.T) {
	// Rung 0's second preserved bug, pinned so nobody "fixes" the baseline.
	uassert.PanicsWithMessage(t, cur, "unsupported", func() { Execute(",") })
}

func TestMachineWithoutProgram(t *testing.T) {
	m := &Machine{status: vmkit.Running}
	used, status := m.Step(vmkit.NewTestHost(), 10)
	uassert.Equal(t, int64(0), used)
	uassert.Equal(t, "trapped", status.String())
	uassert.Equal(t, "no program", m.Trap())
}
