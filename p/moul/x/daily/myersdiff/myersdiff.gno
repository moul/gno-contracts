// Package myersdiff computes the shortest edit script between two sequences of
// lines, using Myers' greedy algorithm: the same one git, diff and every review
// tool run to turn two documents into a list of additions and deletions.
//
// A realm that stores text and lets it be edited has two versions of it and no
// way to show what moved between them. Storing a diff instead of a snapshot is
// the usual answer, and this is the half that produces it.
//
// The cost of the search is bounded by a budget, not by the input size alone:
// see [Budget] for why a minimal diff is sometimes the wrong answer on chain.
//
// Live demo: [r/moul/x/daily/myersdiffdemo](/r/moul/x/daily/myersdiffdemo/v0).
package myersdiff

import (
	"strconv"
	"strings"
)

// Op is what happened to one line.
type Op int8

const (
	// Delete marks a line present in a and absent from b.
	Delete Op = -1
	// Equal marks a line present in both, unchanged.
	Equal Op = 0
	// Insert marks a line absent from a and present in b.
	Insert Op = 1
)

// String renders the op as the single character a unified diff uses.
func (o Op) String() string {
	switch o {
	case Delete:
		return "-"
	case Insert:
		return "+"
	default:
		return " "
	}
}

// Edit is one line of the edit script.
type Edit struct {
	Op   Op
	Line string
}

// Script is a complete edit script turning a into b.
//
// Minimal is false when the search hit its budget and the script fell back to
// deleting everything and inserting everything. That script is still correct:
// applying it to a yields b. It is simply not the shortest one.
type Script struct {
	Edits   []Edit
	Minimal bool
}

// Added counts inserted lines.
func (s Script) Added() int { return s.count(Insert) }

// Deleted counts deleted lines.
func (s Script) Deleted() int { return s.count(Delete) }

// Unchanged counts lines carried over untouched.
func (s Script) Unchanged() int { return s.count(Equal) }

func (s Script) count(op Op) int {
	n := 0
	for _, e := range s.Edits {
		if e.Op == op {
			n++
		}
	}
	return n
}

// Apply replays the script against a and returns the lines it produces, which
// is b when the script came from Slices(a, b).
//
// The second return reports whether a is the document the script describes:
// every Equal and Delete edit has to match the line it consumes, and the script
// has to consume all of a. It is false for a script built against a different
// document, which is the check that makes a stored diff verifiable rather than
// merely replayable. The lines are returned either way, because they are what
// the script says and a caller deciding what to do about a mismatch usually
// wants to see both.
func (s Script) Apply(a []string) ([]string, bool) {
	out := []string{}
	ok := true
	i := 0
	for _, e := range s.Edits {
		switch e.Op {
		case Equal:
			if i >= len(a) || a[i] != e.Line {
				ok = false
			}
			i++
			out = append(out, e.Line)
		case Delete:
			if i >= len(a) || a[i] != e.Line {
				ok = false
			}
			i++
		case Insert:
			out = append(out, e.Line)
		}
	}
	if i != len(a) {
		ok = false
	}
	return out, ok
}

// DefaultBudget caps the number of rounds the search may run before it gives up
// and returns a non-minimal script. Myers' algorithm costs O((n+m)*d) where d is
// the number of differing lines, so two similar documents are cheap at any size
// and two unrelated ones are quadratic. On chain the caller picks the input, so
// the cost has to be bounded by something the caller does not control.
//
// The threshold this sets is worth stating plainly, because it is not a size:
// the default gives up past 256 changed lines, at any file size. Two 4,000-line
// documents differing in 10 lines are diffed minimally; two 300-line documents
// sharing nothing are not. A caller whose documents are large and similar is
// well inside it; a caller diffing unrelated text is always outside it and
// should pass a small budget rather than pay for the search before the
// fallback.
//
// The cost is in gas, not just in time: a search that runs to the default
// ceiling against two MaxLines documents was measured in the billions of gas
// against a 3,000,000,000 block limit during the review of this package, before
// the frontier was resized to the round ceiling. Treat a full-ceiling search as
// something to avoid rather than something to budget for.
const DefaultBudget = 256

// MaxBudget is the hard ceiling on the rounds any caller can ask for, whatever
// budget it passes.
//
// It exists because the round count, not the input size, is what the search
// allocates against: one snapshot of the frontier is kept per round so the
// script can be walked back out of them. Without the ceiling, two documents at
// MaxLines and a large budget would permit 8,192 snapshots, and the budget
// parameter would hand a caller the memory bill as a dial. The useful direction
// for a caller is downwards.
const MaxBudget = 1024

// MaxLines caps each side of the comparison. The algorithm allocates two slices
// proportional to n+m before it compares anything, so the size is checked before
// the work starts rather than discovered during it.
const MaxLines = 4096

// Lines splits a and b on "\n" and diffs them with DefaultBudget.
//
// A trailing newline produces a trailing empty line on that side, which is what
// makes "a\n" and "a" different documents here, as they are to diff(1).
func Lines(a, b string) Script {
	checkLineCap(a)
	checkLineCap(b)
	return Slices(split(a), split(b))
}

// checkLineCap refuses an oversized document before strings.Split allocates a
// slice for it. MaxLines is checked again in Budget, for a caller that supplies
// its own slices; this is the copy that matters, because counting newlines
// allocates nothing and splitting them allocates everything.
func checkLineCap(s string) {
	if s == "" {
		return
	}
	if strings.Count(s, "\n")+1 > MaxLines {
		panic("myersdiff: input exceeds MaxLines")
	}
}

func split(s string) []string {
	if s == "" {
		return []string{}
	}
	return strings.Split(s, "\n")
}

// Slices diffs two line sequences with DefaultBudget.
func Slices(a, b []string) Script {
	return Budget(a, b, DefaultBudget)
}

// Budget diffs two line sequences, stopping the search after at most budget
// rounds. A budget of zero or less means DefaultBudget; a budget larger than
// len(a)+len(b) is capped at it, since no minimal script is longer than that.
//
// It panics when either side exceeds MaxLines. Construction is a transaction,
// where aborting is the useful answer; reading is where totality matters, and
// every method on the resulting Script is total.
func Budget(a, b []string, budget int) Script {
	if len(a) > MaxLines || len(b) > MaxLines {
		panic("myersdiff: input exceeds MaxLines")
	}
	if budget <= 0 {
		budget = DefaultBudget
	}
	edits, ok := search(a, b, effectiveRounds(budget, len(a), len(b)))
	if !ok {
		return Script{Edits: replaceAll(a, b), Minimal: false}
	}
	return Script{Edits: edits, Minimal: true}
}

func replaceAll(a, b []string) []Edit {
	edits := []Edit{}
	for _, line := range a {
		edits = append(edits, Edit{Op: Delete, Line: line})
	}
	for _, line := range b {
		edits = append(edits, Edit{Op: Insert, Line: line})
	}
	return edits
}

// effectiveRounds is how many rounds the search may run: the caller's budget,
// defaulted when unset and capped by both MaxBudget and n+m, since no minimal
// script is longer than n+m.
func effectiveRounds(budget, n, m int) int {
	if budget <= 0 {
		budget = DefaultBudget
	}
	if budget > MaxBudget {
		budget = MaxBudget
	}
	if budget > n+m {
		budget = n + m
	}
	return budget
}

// search runs the greedy forward pass, recording one snapshot of the frontier
// per round, then walks the snapshots backwards into an edit script. It reports
// false when the budget ran out before the two ends met.
func search(a, b []string, budget int) ([]Edit, bool) {
	n := len(a)
	m := len(b)
	maxD := budget

	// At round d only the diagonals -d..d are live, and d never exceeds maxD,
	// so the frontier is sized by the round ceiling rather than by the input.
	// That is what keeps a snapshot small when two large documents are being
	// compared under a small budget.
	offset := maxD + 1
	v := make([]int, 2*maxD+3)
	trace := [][]int{}

	for d := 0; d <= maxD; d++ {
		snapshot := make([]int, len(v))
		copy(snapshot, v)
		trace = append(trace, snapshot)

		for k := -d; k <= d; k += 2 {
			var x int
			// Move down (an insertion) when the diagonal below reaches further,
			// or when there is no diagonal to the left to come from at all.
			if k == -d || (k != d && v[offset+k-1] < v[offset+k+1]) {
				x = v[offset+k+1]
			} else {
				x = v[offset+k-1] + 1
			}
			y := x - k
			for x < n && y < m && a[x] == b[y] {
				x++
				y++
			}
			v[offset+k] = x
			if x >= n && y >= m {
				return backtrack(a, b, trace, offset), true
			}
		}
	}
	return nil, false
}

// backtrack walks the recorded frontiers from the end back to the origin. Each
// snapshot is the state before its own round, so the same rule that chose a move
// forwards identifies the predecessor backwards.
func backtrack(a, b []string, trace [][]int, offset int) []Edit {
	x := len(a)
	y := len(b)
	rev := []Edit{}

	for d := len(trace) - 1; d >= 0; d-- {
		v := trace[d]
		k := x - y

		var prevK int
		if k == -d || (k != d && v[offset+k-1] < v[offset+k+1]) {
			prevK = k + 1
		} else {
			prevK = k - 1
		}
		prevX := v[offset+prevK]
		prevY := prevX - prevK

		for x > prevX && y > prevY {
			rev = append(rev, Edit{Op: Equal, Line: a[x-1]})
			x--
			y--
		}
		if d > 0 {
			if x == prevX {
				rev = append(rev, Edit{Op: Insert, Line: b[prevY]})
			} else {
				rev = append(rev, Edit{Op: Delete, Line: a[prevX]})
			}
		}
		x = prevX
		y = prevY
	}

	edits := make([]Edit, len(rev))
	for i, e := range rev {
		edits[len(rev)-1-i] = e
	}
	return edits
}

// Hunk is a contiguous run of the script worth printing: every change, plus up
// to context unchanged lines on each side of it.
//
// AStart and BStart are 1-based line numbers. When a side contributes no lines
// at all, its start is the number of the line before the hunk and its length is
// zero, which is what diff(1) prints for a pure insertion into an empty file.
type Hunk struct {
	AStart int
	ALines int
	BStart int
	BLines int
	Edits  []Edit
}

// Header renders the @@ line of a unified diff.
func (h Hunk) Header() string {
	return "@@ -" + rangeOf(h.AStart, h.ALines) + " +" + rangeOf(h.BStart, h.BLines) + " @@"
}

func rangeOf(start, length int) string {
	if length == 1 {
		return strconv.Itoa(start)
	}
	return strconv.Itoa(start) + "," + strconv.Itoa(length)
}

// Hunks groups a script into the runs a unified diff prints, with context
// unchanged lines around each change. A negative context is treated as zero; a
// script with no changes produces no hunks.
func Hunks(s Script, context int) []Hunk {
	if context < 0 {
		context = 0
	}
	edits := s.Edits

	// aPos[i] and bPos[i] are how many lines of each side precede edit i.
	aPos := make([]int, len(edits)+1)
	bPos := make([]int, len(edits)+1)
	for i, e := range edits {
		aPos[i+1] = aPos[i]
		bPos[i+1] = bPos[i]
		if e.Op != Insert {
			aPos[i+1]++
		}
		if e.Op != Delete {
			bPos[i+1]++
		}
	}

	hunks := []Hunk{}
	i := 0
	for i < len(edits) {
		if edits[i].Op == Equal {
			i++
			continue
		}

		start := i - context
		if start < 0 {
			start = 0
		}
		last := i

		// Extend while the next change is close enough that the context around
		// the two would overlap. A longer run of equals ends the hunk.
		j := i + 1
		for j < len(edits) {
			if edits[j].Op != Equal {
				last = j
				j++
				continue
			}
			run := 0
			for j+run < len(edits) && edits[j+run].Op == Equal {
				run++
			}
			if j+run >= len(edits) || run > 2*context {
				break
			}
			j += run
		}

		stop := last + context
		if stop > len(edits)-1 {
			stop = len(edits) - 1
		}

		h := Hunk{
			AStart: aPos[start] + 1,
			ALines: aPos[stop+1] - aPos[start],
			BStart: bPos[start] + 1,
			BLines: bPos[stop+1] - bPos[start],
			Edits:  edits[start : stop+1],
		}
		if h.ALines == 0 {
			h.AStart = aPos[start]
		}
		if h.BLines == 0 {
			h.BStart = bPos[start]
		}
		hunks = append(hunks, h)

		i = stop + 1
	}
	return hunks
}

// Unified renders the body of a unified diff: the @@ headers and their lines,
// and nothing else. The --- and +++ file headers name files, which a realm does
// not have, so they are the caller's to add.
func Unified(a, b string, context int) string {
	return UnifiedScript(Lines(a, b), context)
}

// UnifiedScript renders an already-computed script, for a caller that wants the
// counts or the Minimal flag as well as the text.
func UnifiedScript(s Script, context int) string {
	var sb strings.Builder
	for _, h := range Hunks(s, context) {
		sb.WriteString(h.Header())
		sb.WriteString("\n")
		for _, e := range h.Edits {
			sb.WriteString(e.Op.String())
			sb.WriteString(e.Line)
			sb.WriteString("\n")
		}
	}
	return sb.String()
}
