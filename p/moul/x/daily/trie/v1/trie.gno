// Package trie is a prefix tree (trie) for autocomplete, as a pure, reusable
// package: insert words, then ask for every word sharing a prefix.
//
// Everything is deterministic and allocation-friendly so it runs reproducibly
// on-chain: no maps in the hot path (map iteration order is unspecified, which
// would make Render output vary), no clocks, no chain imports. Children are
// kept in a slice sorted by rune, so completions always come out in
// lexicographic order — the same input always yields the same output.
//
// A live demo of this package (a gnoweb autocomplete box) is at
// [r/moul/x/daily/triedemo](/r/moul/x/daily/triedemo/v1).
package trie

import "sort"

// MaxWordLen bounds a single word so insertion gas stays predictable.
const MaxWordLen = 64

// node is one position in the tree. Children are ordered by Key so walks are
// deterministic; `terminal` marks the end of an inserted word (so "car" can be
// a word even when "carpet" is also stored).
type node struct {
	key      rune
	terminal bool
	children []*node
}

// Trie is a prefix tree. The zero value is an empty, ready-to-use Trie.
type Trie struct {
	root  node
	count int
}

// New returns an empty Trie.
func New() *Trie { return &Trie{} }

// Len returns how many distinct words the Trie holds.
func (t *Trie) Len() int { return t.count }

// child finds n's child for rune r, or nil. The slice is sorted, so this is a
// binary search.
func (n *node) child(r rune) *node {
	i := sort.Search(len(n.children), func(i int) bool { return n.children[i].key >= r })
	if i < len(n.children) && n.children[i].key == r {
		return n.children[i]
	}
	return nil
}

// addChild inserts a child for rune r, keeping children sorted by key.
func (n *node) addChild(r rune) *node {
	i := sort.Search(len(n.children), func(i int) bool { return n.children[i].key >= r })
	if i < len(n.children) && n.children[i].key == r {
		return n.children[i]
	}
	c := &node{key: r}
	n.children = append(n.children, nil)
	copy(n.children[i+1:], n.children[i:])
	n.children[i] = c
	return c
}

// Insert adds word to the Trie and reports whether it was newly added.
// The empty string and words longer than MaxWordLen are rejected (false).
// Inserting the same word twice is a no-op.
func (t *Trie) Insert(word string) bool {
	rs := []rune(word)
	if len(rs) == 0 || len(rs) > MaxWordLen {
		return false
	}
	n := &t.root
	for _, r := range rs {
		n = n.addChild(r)
	}
	if n.terminal {
		return false
	}
	n.terminal = true
	t.count++
	return true
}

// Contains reports whether word was inserted as a complete word. A stored
// "carpet" does not make "car" Contains-true — only Insert does.
func (t *Trie) Contains(word string) bool {
	n := t.find(word)
	return n != nil && n.terminal
}

// HasPrefix reports whether any stored word starts with prefix. The empty
// prefix matches whenever the Trie is non-empty.
func (t *Trie) HasPrefix(prefix string) bool {
	if prefix == "" {
		return t.count > 0
	}
	return t.find(prefix) != nil
}

// find walks to the node for s, or returns nil when the path is absent.
func (t *Trie) find(s string) *node {
	n := &t.root
	for _, r := range s {
		n = n.child(r)
		if n == nil {
			return nil
		}
	}
	return n
}

// Complete returns up to limit words starting with prefix, in lexicographic
// order. A limit <= 0 means "no cap". An absent prefix yields an empty slice
// (never nil), so callers can range over the result unconditionally.
//
// The empty prefix lists the whole Trie, which is what makes this usable as a
// plain sorted listing too.
func (t *Trie) Complete(prefix string, limit int) []string {
	out := []string{}
	start := t.find(prefix)
	if start == nil {
		return out
	}
	collect(start, []rune(prefix), &out, limit)
	return out
}

// collect appends every word under n (depth-first, children already sorted)
// to *out, stopping once limit is reached.
func collect(n *node, path []rune, out *[]string, limit int) {
	if limit > 0 && len(*out) >= limit {
		return
	}
	if n.terminal {
		*out = append(*out, string(path))
	}
	for _, c := range n.children {
		if limit > 0 && len(*out) >= limit {
			return
		}
		collect(c, append(path, c.key), out, limit)
	}
}

// Words returns every stored word in lexicographic order.
func (t *Trie) Words() []string { return t.Complete("", 0) }

// FromWords builds a Trie from words, skipping any the Trie rejects.
func FromWords(words []string) *Trie {
	t := New()
	for _, w := range words {
		t.Insert(w)
	}
	return t
}
