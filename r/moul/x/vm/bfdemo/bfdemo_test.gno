package bfdemo

import (
	"strings"
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

const hello = "++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------."

// resetState puts the realm globals back where init() left them. Realm state
// persists for the whole test binary, so every test that asserts on ids or on
// the rendered instance list has to start from here.
func resetState() {
	store = vmkit.NewStore()
	inputs = avl.NewTree()
	idgen = seqid.ID(0)
	count = 0
}

func TestUploadAndRunToCompletion(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	id := Upload(cross(cur), hello, "", 0)
	uassert.Equal(t, "halted", Step(cross(cur), id, 0))

	inst := store.Get(id)
	uassert.Equal(t, "Hello World", string(inst.Output))
	uassert.Equal(t, int64(1), inst.Slices)
	uassert.Equal(t, alice, inst.Owner)
}

// TestOneProgramAcrossManyTransactions is what the realm exists to
// demonstrate: the same computation, finished over several calls, each paying
// for its own slice.
func TestOneProgramAcrossManyTransactions(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	id := Upload(cross(cur), hello, "", 0)
	status := ""
	slices := 0
	for slices < 500 {
		status = Step(cross(cur), id, 7)
		slices++
		if status != "running" {
			break
		}
	}

	inst := store.Get(id)
	uassert.Equal(t, "halted", status)
	uassert.Equal(t, "Hello World", string(inst.Output))
	uassert.True(t, inst.Slices > 1, "took more than one slice")
}

func TestInputIsReadThroughTheHost(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	// ",[.,]" echoes its input back.
	id := Upload(cross(cur), ",[.,]", "gno.land", 0)
	uassert.Equal(t, "halted", Step(cross(cur), id, 0))
	uassert.Equal(t, "gno.land", string(store.Get(id).Output))
}

func TestBudgetStopsAProgram(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	id := Upload(cross(cur), hello, "", 12)
	uassert.Equal(t, "out of fuel", Step(cross(cur), id, 0))
	uassert.Equal(t, int64(12), store.Get(id).FuelUsed)

	// And it stays stopped rather than quietly continuing.
	uassert.AbortsContains(t, cur, "instance is out of fuel", func() {
		Step(cross(cur), id, 0)
	})
}

func TestUploadRejectsAMalformedProgram(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	// Rejected by the transaction that submitted it, not by whoever pays
	// for the first slice later.
	uassert.AbortsContains(t, cur, "unmatched", func() {
		Upload(cross(cur), "+++[", "", 0)
	})
	uassert.Equal(t, 0, count)
}

func TestRemoveIsOwnerOnly(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Upload(cross(cur), hello, "", 0)

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not your instance", func() {
		Remove(cross(cur), id)
	})

	// Anyone may pay for a slice, though: the program and its budget were
	// both fixed at upload.
	uassert.Equal(t, "halted", Step(cross(cur), id, 0))

	testing.SetRealm(testing.NewUserRealm(alice))
	Remove(cross(cur), id)
	uassert.Equal(t, 0, count)
	uassert.True(t, store.Get(id) == nil)
}

func TestOutputIsCappedAndTrapped(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	// A cell set to 1 and printed forever: an infinite writer.
	id := Upload(cross(cur), "+[.]", "", 0)
	status := Step(cross(cur), id, 0)

	inst := store.Get(id)
	uassert.Equal(t, "trapped", status)
	uassert.Equal(t, "output limit reached", inst.Trap)
	uassert.Equal(t, MaxOutput, len(inst.Output))
}

func TestRenderUnknownInstance(t *testing.T) {
	resetState()
	uassert.True(t, strings.Contains(Render("/nope"), "No such instance"))
}

// TestRenderEscapesGuestOutput pins the rule that a realm cannot be fixed in
// place once it is live: everything a caller controls is escaped before it
// reaches the page.
func TestRenderEscapesGuestOutput(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	// Print a backtick (96), which would otherwise close the code fence.
	src := strings.Repeat("+", 96) + "."
	id := Upload(cross(cur), src, "", 0)
	Step(cross(cur), id, 0)

	page := Render("/" + id)
	uassert.Equal(t, "`", string(store.Get(id).Output))
	uassert.True(t, strings.Contains(page, "\\x60"), "the backtick is escaped")

	// The comment text in a program never reaches the page at all: only
	// the eight operators do.
	uassert.Equal(t, "+++[-]<>", operatorsOnly("+++ this is a comment [-] </script>"))
}

// Output sits in a code span, where markdown escapes show verbatim: only the
// pipe is escaped there, and nothing else.
func TestCodeCell(t *testing.T) {
	uassert.Equal(t, "`Hello, gno.land\\n`", codeCell("Hello, gno.land\\n"))
	uassert.Equal(t, "`a\\|b`", codeCell("a|b"))
}

// emit returns a program that prints s, one byte at a time, so a test can put
// any text in the output column without hand-writing Brainfuck.
func emit(s string) string {
	var sb strings.Builder
	for i := 0; i < len(s); i++ {
		sb.WriteString("[-]" + strings.Repeat("+", int(s[i])) + ".")
	}
	return sb.String()
}

// instanceRow returns the first instance row of the home page.
func instanceRow(t *testing.T) string {
	for _, line := range strings.Split(Render(""), "\n") {
		if strings.HasPrefix(line, "| [") {
			return line
		}
	}
	t.Fatalf("no instance row on the home page")
	return ""
}

// The output column is pinned on the rendered page, not only through the
// helper, so the call site cannot drift back to ui.Cell inside backticks
// (which would show `a\.b`) with the suite green.
func TestRenderOutputCell(cur realm, t *testing.T) {
	cases := []struct {
		name, out, cell string
	}{
		{"an escapable character shows as written", "a.b", "| `a.b` |"},
		{"no output is an empty cell, not two backticks", "", "| 0 |  |"},
		{"a space at each end is padded in the markdown, past CommonMark's strip", " a ", "| `  a  ` |"},
		{"a guest pipe stays inside its cell", "a|b", "| `a\\|b` |"},
	}
	for _, c := range cases {
		resetState()
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))
		id := Upload(cross(cur), emit(c.out), "", 0)
		if c.out != "" {
			Step(cross(cur), id, 0)
			uassert.Equal(t, c.out, string(store.Get(id).Output))
		}
		row := instanceRow(t)
		uassert.True(t, strings.HasSuffix(row, c.cell), c.name+": "+row)
	}
}

// codeCell follows the three rules of a code span, not only the pipe: empty
// content is not a span, a space at either end needs a pad, and the fence
// outscans any backtick run in the content.
func TestCodeCellRules(t *testing.T) {
	cases := []struct{ in, want string }{
		{"", ""},
		{"Hello World", "`Hello World`"},
		{"a|b", "`a\\|b`"},
		{" hi ", "`  hi  `"},
		{" hi", "`  hi `"},
		{"hi ", "` hi  `"},
		{"a`b", "``a`b``"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, codeCell(c.in), "codeCell("+c.in+")")
	}
}
