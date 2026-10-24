// Package ahocorasick implements Aho-Corasick multi-pattern search as a pure,
// reusable package.
//
// Searching for k patterns by running a single-pattern scan k times costs
// O(k*n): every extra word in the dictionary is another full pass over the
// text. Aho-Corasick builds one automaton from the whole set, a trie of the
// patterns plus a failure link on every node pointing at the longest proper
// suffix that is also a prefix of some pattern, and then reads the text once.
// Building the trie and the failure links costs O(total pattern length) and
// scanning costs O(n + matches), whatever k is, and the text cursor never moves
// backwards.
//
// One deliberate departure from the paper: each node stores the full list of
// patterns matching there, merged from its failure target at build time, rather
// than a link to be walked at every offset. That makes a reported match O(1)
// instead of a walk up the failure chain, and it costs build memory in exactly
// one shape, a set whose patterns nest ("a", "aa", "aaa", ...), where the
// merged lists are quadratic in k rather than linear. MaxPatterns is what
// bounds that, and nothing else does.
//
// That last property is why it is worth having on chain: the worst case equals
// the best case, so a dictionary and a text chosen by an attacker cost the same
// as a friendly pair. A naive k-pass scan is an input away from quadratic.
//
// It is [p/moul/x/daily/kmp](/p/moul/x/daily/kmp/v0) generalised: KMP's failure
// table is this automaton for a one-pattern set.
//
// Operates on BYTES, not runes. gno strings are UTF-8 and a match offset is a
// byte offset, which is the right unit for slicing. UTF-8 is self-synchronizing,
// so a pattern that is itself valid UTF-8 can only match on a rune boundary of
// valid UTF-8 text; a pattern that is a bare continuation byte can and will
// match inside a rune, and slicing on that offset splits it.
//
// A live demo of this package is at
// [r/moul/x/daily/ahocorasickdemo](/r/moul/x/daily/ahocorasickdemo/v0).
package ahocorasick

// Bounds on what New will build, so an on-chain caller cannot be handed an
// automaton whose size it did not choose. At most MaxPatterns*MaxPatternLen+1
// nodes exist, and the build is linear in the total pattern length.
const (
	MaxPatterns   = 256
	MaxPatternLen = 256
)

// Match is one occurrence of one pattern. Start and End are byte offsets into
// the text, half-open, so text[Start:End] is the matched run. Index is the
// pattern's slot in the slice given to New, which is how a caller maps a match
// back to whatever it stored alongside the pattern.
type Match struct {
	Start   int
	End     int
	Index   int
	Pattern string
}

// edge is one labelled transition. A node keeps its edges sorted by label so a
// lookup is a binary search over the alphabet actually used, not a 256-entry
// row per node: a dictionary of words touches a few dozen distinct bytes and
// paying 1 KiB a node for the rest is how this structure gets expensive.
type edge struct {
	label byte
	next  int
}

type node struct {
	edges []edge
	fail  int
	out   []int // pattern slots matching here, longest first
}

// Matcher is a built automaton. It is immutable once New returns, so one
// Matcher can serve any number of scans.
type Matcher struct {
	patterns []string
	nodes    []node
}

// New builds the automaton for patterns. Empty patterns are dropped: the empty
// string matches at every offset, which is a different question from the one
// this package answers.
//
// Returns nil when there is nothing to build (no pattern survives the drop) or
// when the set exceeds the bounds above. A nil Matcher answers every method,
// so a caller may hand the result straight to a scan without a check.
func New(patterns []string) *Matcher {
	accepted := make([]string, 0, len(patterns))
	for _, p := range patterns {
		if p == "" {
			continue
		}
		if len(p) > MaxPatternLen {
			return nil
		}
		accepted = append(accepted, p)
	}
	if len(accepted) == 0 || len(accepted) > MaxPatterns {
		return nil
	}

	m := &Matcher{patterns: accepted, nodes: []node{{fail: 0}}}
	for i, p := range accepted {
		cur := 0
		for j := 0; j < len(p); j++ {
			next, ok := m.child(cur, p[j])
			if !ok {
				m.nodes = append(m.nodes, node{fail: 0})
				next = len(m.nodes) - 1
				m.addEdge(cur, p[j], next)
			}
			cur = next
		}
		// Same depth, so same length: ordering by slot keeps a duplicated
		// pattern reporting in the caller's order.
		m.nodes[cur].out = append(m.nodes[cur].out, i)
	}
	m.link()
	return m
}

// link computes every failure link, then merges each node's outputs with its
// failure target's. The merge is what makes a scan O(1) per reported match
// instead of a walk up the failure chain at every offset, and the breadth-first
// order is what makes it correct: a node's failure target is always shallower,
// so it has already been merged.
//
// It is also where the memory goes: a nested set makes the merged lists
// quadratic in the number of patterns. See the package doc.
func (m *Matcher) link() {
	queue := make([]int, 0, len(m.nodes))
	for _, e := range m.nodes[0].edges {
		m.nodes[e.next].fail = 0
		queue = append(queue, e.next)
	}
	for len(queue) > 0 {
		u := queue[0]
		queue = queue[1:]
		for _, e := range m.nodes[u].edges {
			v := e.next
			f := m.nodes[u].fail
			for {
				if w, ok := m.child(f, e.label); ok {
					m.nodes[v].fail = w
					break
				}
				if f == 0 {
					m.nodes[v].fail = 0
					break
				}
				f = m.nodes[f].fail
			}
			inherited := m.nodes[m.nodes[v].fail].out
			if len(inherited) > 0 {
				merged := make([]int, 0, len(m.nodes[v].out)+len(inherited))
				merged = append(merged, m.nodes[v].out...)
				merged = append(merged, inherited...)
				m.nodes[v].out = merged
			}
			queue = append(queue, v)
		}
	}
}

// child returns the node reached from n by label, if there is one.
func (m *Matcher) child(n int, label byte) (int, bool) {
	edges := m.nodes[n].edges
	lo, hi := 0, len(edges)
	for lo < hi {
		mid := (lo + hi) / 2
		if edges[mid].label < label {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < len(edges) && edges[lo].label == label {
		return edges[lo].next, true
	}
	return 0, false
}

// addEdge inserts a transition, keeping the edge list sorted by label.
func (m *Matcher) addEdge(n int, label byte, next int) {
	edges := m.nodes[n].edges
	pos := len(edges)
	for i, e := range edges {
		if e.label > label {
			pos = i
			break
		}
	}
	edges = append(edges, edge{})
	copy(edges[pos+1:], edges[pos:])
	edges[pos] = edge{label: label, next: next}
	m.nodes[n].edges = edges
}

// step advances the automaton one byte, following failure links until the byte
// is consumed or the root refuses it. This is the whole scan: the text index
// only ever moves forward.
func (m *Matcher) step(cur int, c byte) int {
	for {
		if w, ok := m.child(cur, c); ok {
			return w
		}
		if cur == 0 {
			return 0
		}
		cur = m.nodes[cur].fail
	}
}

// FindAll returns every occurrence of every pattern, including overlapping and
// nested ones, ordered by end offset. At one end offset the longest match comes
// first, because the scan reports the node it reached before the shorter
// suffixes hanging off its failure chain, so a caller taking the first match at
// each offset gets the greedy one.
func (m *Matcher) FindAll(text string) []Match {
	if m == nil {
		return nil
	}
	var out []Match
	cur := 0
	for i := 0; i < len(text); i++ {
		cur = m.step(cur, text[i])
		for _, slot := range m.nodes[cur].out {
			p := m.patterns[slot]
			out = append(out, Match{Start: i + 1 - len(p), End: i + 1, Index: slot, Pattern: p})
		}
	}
	return out
}

// FindFirst returns the first match FindAll would return, and stops the scan
// there. The one to reach for when the question is "does this text contain
// anything from the list, and where".
func (m *Matcher) FindFirst(text string) (Match, bool) {
	if m == nil {
		return Match{}, false
	}
	cur := 0
	for i := 0; i < len(text); i++ {
		cur = m.step(cur, text[i])
		if out := m.nodes[cur].out; len(out) > 0 {
			p := m.patterns[out[0]]
			return Match{Start: i + 1 - len(p), End: i + 1, Index: out[0], Pattern: p}, true
		}
	}
	return Match{}, false
}

// Contains reports whether any pattern occurs in text.
func (m *Matcher) Contains(text string) bool {
	_, ok := m.FindFirst(text)
	return ok
}

// Patterns returns the accepted patterns, in the caller's order, as a copy.
func (m *Matcher) Patterns() []string {
	if m == nil {
		return nil
	}
	out := make([]string, len(m.patterns))
	copy(out, m.patterns)
	return out
}

// Nodes returns the size of the automaton: one node per distinct pattern
// prefix, plus the root. The number a caller sizing a dictionary wants, since
// it is what the build actually costs.
func (m *Matcher) Nodes() int {
	if m == nil {
		return 0
	}
	return len(m.nodes)
}
