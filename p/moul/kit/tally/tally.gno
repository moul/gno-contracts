// Package tally orders a scoreboard: highest score first, ties broken by key.
//
// Sixteen realms in this repo carry their own sort.Interface triple, because
// gno has no sort.Slice and every leaderboard therefore needs a named type
// with Len, Less and Swap. Eight of them rank on ONE score and then break the
// tie, which is what this package is; the rest rank on two scores and keep
// their own comparator. They do not agree on what happens at a tie, and one of
// them does not break ties at all.
//
// # The tie-break is the point
//
// A Render that reshuffles between identical calls is a bug, so the final
// comparison must be a total order. Comparing the score again (as
// r/moul/x/daily/rpgroom's third clause does) is not one: two rows with equal
// scores compare false in both directions, and their order then falls out of
// whatever the sort algorithm did with the input, which is reproducible but
// nobody chose it. [Sort] always ends on the key, so equal scores render in a
// stable, explicable order.
//
// # What is not here
//
// Storage: the caller keeps its own avl tree and maps it to [Entry]. That is
// what makes this adoptable by realms that already have their state, and
// [Board] is for new ones that do not.
//
// Rendering: a podium and a table already have an owner in
// [p/moul/kit/ui](/p/moul/kit/ui/v0).
package tally

import (
	"sort"

	"gno.land/p/nt/avl/v0"
)

// Entry is one row of a scoreboard: an opaque key and its score.
//
// Key is whatever the caller ranks by, usually an address in its String form.
// It is the tie-break, so it must be unique within one board.
type Entry struct {
	Key   string
	Score int64
}

type byScore []Entry

func (e byScore) Len() int      { return len(e) }
func (e byScore) Swap(i, j int) { e[i], e[j] = e[j], e[i] }
func (e byScore) Less(i, j int) bool {
	if e[i].Score != e[j].Score {
		return e[i].Score > e[j].Score
	}
	return e[i].Key < e[j].Key
}

// Sort orders entries in place: highest score first, ties by key ascending.
func Sort(entries []Entry) { sort.Sort(byScore(entries)) }

// Top returns the n highest entries, sorted. A n at or below zero returns
// nothing; a n past the end returns everything. The input is not modified.
func Top(entries []Entry, n int) []Entry {
	if n <= 0 || len(entries) == 0 {
		return nil
	}
	out := make([]Entry, len(entries))
	copy(out, entries)
	Sort(out)
	if n > len(out) {
		n = len(out)
	}
	return out[:n]
}

// Rank returns the 1-based position of key once entries are sorted, or 0 if
// the key is absent. Equal scores still get distinct ranks, decided by the
// same key tie-break Sort uses, so no two rows ever claim the same place.
func Rank(entries []Entry, key string) int {
	sorted := make([]Entry, len(entries))
	copy(sorted, entries)
	Sort(sorted)
	for i, e := range sorted {
		if e.Key == key {
			return i + 1
		}
	}
	return 0
}

// Board is a scoreboard that owns its storage, for a realm that does not
// already have one. It is backed by a tree rather than a map: gno map
// iteration order is unspecified, and a Render built on one is not
// reproducible.
type Board struct {
	scores *avl.Tree // key -> int64
}

// NewBoard returns an empty Board.
func NewBoard() *Board { return &Board{scores: avl.NewTree()} }

// Add increases key's score by delta, which may be negative, and returns the
// new score. A key that was absent starts at zero.
func (b *Board) Add(key string, delta int64) int64 {
	n := b.Score(key) + delta
	b.scores.Set(key, n)
	return n
}

// Set replaces key's score outright.
func (b *Board) Set(key string, score int64) { b.scores.Set(key, score) }

// Score returns key's score, or zero if it has none. It does not distinguish
// an absent key from one scoring zero; use [Board.Has] when that matters.
func (b *Board) Score(key string) int64 {
	v := b.scores.Get(key)
	if v == nil {
		return 0
	}
	return v.(int64)
}

// Has reports whether key has been scored at all.
func (b *Board) Has(key string) bool { return b.scores.Get(key) != nil }

// Remove drops key, reporting whether it was there.
func (b *Board) Remove(key string) bool {
	_, removed := b.scores.Remove(key)
	return removed
}

// Len is the number of scored keys.
func (b *Board) Len() int { return b.scores.Size() }

// Entries returns every row, sorted by [Sort].
func (b *Board) Entries() []Entry {
	out := make([]Entry, 0, b.scores.Size())
	b.scores.Iterate("", "", func(k string, v any) bool {
		out = append(out, Entry{Key: k, Score: v.(int64)})
		return false
	})
	Sort(out)
	return out
}

// Top returns the n highest rows, sorted.
func (b *Board) Top(n int) []Entry { return Top(b.Entries(), n) }

// Rank returns key's 1-based position, or 0 if it is not on the board.
func (b *Board) Rank(key string) int {
	if !b.Has(key) {
		return 0
	}
	return Rank(b.Entries(), key)
}
