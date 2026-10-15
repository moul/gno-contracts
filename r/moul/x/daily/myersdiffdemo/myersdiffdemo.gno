// Package myersdiffdemo is a small gnoweb demo of the
// [p/moul/x/daily/myersdiff](/p/moul/x/daily/myersdiff/v0) library: four fixed
// document pairs, each showing one behaviour worth knowing before using it in a
// realm.
//
// It contains no diff logic of its own. Every line of every diff below is
// computed by the library at render time, so a change in the algorithm shows up
// here as a diff rather than as prose.
//
// Stateless and fixed-input, so Render is deterministic and pinnable.
//
// untrusted-render: no caller string reaches the page. The path selects a
// scenario by exact match against the table below, and the only other segment
// is parsed as an integer and clamped, so an unknown path renders the index
// instead of echoing anything.
package myersdiffdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/myersdiff/v0"
)

// scenario is one fixed pair of documents, chosen to show one property.
type scenario struct {
	key    string
	title  string
	note   string
	a      string
	b      string
	budget int
}

// scenarios are deliberately fixed rather than caller-supplied: output that
// moves with the caller or the block height cannot be pinned by an example
// test, and this realm's whole job is to be comparable from one render to the
// next.
var scenarios = []scenario{
	{
		key:   "patch",
		title: "A small patch in a large file",
		note: "The ordinary case, and the one Myers is fast at: most of the file is " +
			"untouched. The search ends after as many rounds as there are edits, not as " +
			"there are lines, which is the whole reason to prefer it to an edit matrix.",
		a: "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"hello\")\n}\n\n// TODO: say who\n",
		b: "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tname := \"world\"\n\tfmt.Println(\"hello\", name)\n}\n",
	},
	{
		key:   "insert",
		title: "Appending to an empty document",
		note: "Every line is new, and the header says so: the left side contributes no " +
			"lines, so its start is 0 and its length is 0.",
		a:    "",
		b:    "one\ntwo\nthree",
	},
	{
		key:   "move",
		title: "A moved line is a delete and an insert",
		note: "Myers compares sequences, not contents: moving a line is the cheapest pair " +
			"of edits that explains the new order, never a single move operation.",
		a:    "alpha\nbravo\ncharlie\ndelta",
		b:    "bravo\ncharlie\ndelta\nalpha",
	},
	{
		key:   "starved",
		title: "A budget too small for the answer",
		note: "Two unrelated documents cost O((n+m)*d) to compare, and on chain the caller " +
			"picks d. With the budget set to 2 the search gives up and returns a correct " +
			"non-minimal script instead of burning the gas or panicking.",
		a:      "red\norange\nyellow\ngreen\nblue",
		b:      "one\ntwo\nthree\nfour\nfive",
		budget: 2,
	},
}

const (
	defaultContext = 2
	maxContext     = 6
	realmPath      = "/r/moul/x/daily/myersdiffdemo/v0"
)

// Render implements the gnoweb view.
//
//   - "" or "/"              : the index, with every scenario summarized.
//   - "/<key>"               : one scenario at the default context width.
//   - "/<key>/<context>"     : the same, with 0 to 6 lines of context.
func Render(path string) string {
	key, context := parsePath(path)
	if key == "" {
		return renderIndex()
	}
	for _, sc := range scenarios {
		if sc.key == key {
			return renderScenario(sc, context)
		}
	}
	return renderIndex()
}

// parsePath returns the scenario key and the context width. It never returns
// anything it was handed: the key is matched against the table by the caller
// and the width is an integer, clamped.
func parsePath(path string) (string, int) {
	path = strings.TrimPrefix(path, "/")
	if path == "" {
		return "", defaultContext
	}
	parts := strings.SplitN(path, "/", 2)
	context := defaultContext
	if len(parts) == 2 {
		if n, err := strconv.Atoi(parts[1]); err == nil {
			context = n
		}
	}
	if context < 0 {
		context = 0
	}
	if context > maxContext {
		context = maxContext
	}
	return parts[0], context
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString("# Myers diff\n\n")
	sb.WriteString("Demo of the [`p/moul/x/daily/myersdiff`](/p/moul/x/daily/myersdiff/v0) library: ")
	sb.WriteString("the shortest edit script between two documents, the algorithm behind `git diff`.\n\n")
	sb.WriteString("It walks a grid whose diagonals are matching lines, taking the furthest-reaching ")
	sb.WriteString("path at each round, and stops the first time a path reaches the far corner. ")
	sb.WriteString("That round number is the number of edits, and it is minimal because no shorter ")
	sb.WriteString("path was available at any earlier round.\n\n")

	sb.WriteString("## The scenarios\n\n")
	t := ui.NewTable("scenario", "edits", "minimal", "what it shows")
	for _, sc := range scenarios {
		s := diffOf(sc)
		t.Row(
			md.Link(sc.key, realmPath+":"+sc.key),
			strconv.Itoa(s.Added()+s.Deleted()),
			yesNo(s.Minimal),
			sc.title,
		)
	}
	sb.WriteString(t.String())

	sb.WriteString("\n## Context width\n\n")
	sb.WriteString("Append a number to widen or narrow the unchanged lines printed around each change: ")
	sb.WriteString("[`patch/0`](" + realmPath + ":patch/0) shows the changes alone, ")
	sb.WriteString("[`patch/6`](" + realmPath + ":patch/6) shows the whole file as one hunk. ")
	sb.WriteString("Anything out of range is clamped to 0..6.\n\n")

	sb.WriteString("## API\n\n")
	sb.WriteString("- `Lines(a, b string) Script` is the whole surface for text.\n")
	sb.WriteString("- `Script.Apply(a []string) ([]string, bool)` replays the script and says whether it describes that document.\n")
	sb.WriteString("- `Hunks(s Script, context int) []Hunk` groups the script the way a review tool prints it.\n")
	sb.WriteString("- `Unified(a, b string, context int) string` is the two above, as text.\n")
	return sb.String()
}

func renderScenario(sc scenario, context int) string {
	s := diffOf(sc)

	var sb strings.Builder
	sb.WriteString("# ")
	sb.WriteString(sc.title)
	sb.WriteString("\n\n")
	sb.WriteString(sc.note)
	sb.WriteString("\n\n")

	sb.WriteString("## The diff\n\n")
	sb.WriteString("Context: ")
	sb.WriteString(strconv.Itoa(context))
	sb.WriteString(" line(s).\n\n")
	body := myersdiff.UnifiedScript(s, context)
	if body == "" {
		body = "(the two documents are identical)\n"
	}
	sb.WriteString("```diff\n")
	sb.WriteString(body)
	sb.WriteString("```\n\n")

	sb.WriteString("## The script\n\n")
	t := ui.NewTable("property", "value")
	t.Row("inserted lines", strconv.Itoa(s.Added()))
	t.Row("deleted lines", strconv.Itoa(s.Deleted()))
	t.Row("unchanged lines", strconv.Itoa(s.Unchanged()))
	t.Row("minimal", yesNo(s.Minimal))
	sb.WriteString(t.String())
	sb.WriteString("\n")

	sb.WriteString("Replaying it on the left document reproduces the right one ")
	sb.WriteString("**")
	sb.WriteString(yesNo(applies(sc, s)))
	sb.WriteString("**, which is the property that holds even when the script is not minimal.\n\n")

	sb.WriteString("[back](")
	sb.WriteString(realmPath)
	sb.WriteString(")\n")
	return sb.String()
}

func diffOf(sc scenario) myersdiff.Script {
	return myersdiff.Budget(lines(sc.a), lines(sc.b), sc.budget)
}

// applies is the demo asserting the library's own claim rather than repeating
// it: the rendered answer comes from running Apply, not from a constant.
func applies(sc scenario, s myersdiff.Script) bool {
	got, ok := s.Apply(lines(sc.a))
	if !ok {
		return false
	}
	want := lines(sc.b)
	if len(got) != len(want) {
		return false
	}
	for i := range got {
		if got[i] != want[i] {
			return false
		}
	}
	return true
}

func lines(s string) []string {
	if s == "" {
		return []string{}
	}
	return strings.Split(s, "\n")
}

func yesNo(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
