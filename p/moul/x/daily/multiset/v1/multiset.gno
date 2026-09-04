// Package multiset is a bag / frequency counter — a set that allows duplicates
// and remembers how many — as a pure, reusable package.
//
// It is the STL multiset and Python's collections.Counter in one type: Add an
// element several times and the count rises; the distinct elements stay sorted
// so iteration and rendering are deterministic.
//
// The interesting operation is MostCommon(n), and the interesting problem with
// it is ties. Sorting by count alone leaves elements with equal counts in
// whatever order the underlying storage happened to yield — which, if that is a
// built-in map, is unspecified in gno and can differ between nodes. Here the
// order is total: count descending, then element ascending. Two multisets built
// from the same elements always produce the same ranking.
//
// A live demo of this package is at
// [r/moul/x/daily/multisetdemo](/r/moul/x/daily/multisetdemo/v1).
package multiset

import "sort"

// MaxDistinct bounds the number of DISTINCT elements so gas stays predictable.
// Counts themselves are unbounded.
const MaxDistinct = 4096

// MultiSet counts occurrences of string elements.
type MultiSet struct {
	counts map[string]int
	total  int
}

// New returns an empty MultiSet.
func New() *MultiSet { return &MultiSet{counts: map[string]int{}} }

// FromSlice builds a MultiSet from elements, counting duplicates.
func FromSlice(elems []string) *MultiSet {
	m := New()
	for _, e := range elems {
		m.Add(e)
	}
	return m
}

// Add records one occurrence of e. Returns false when e is new and the set
// already holds MaxDistinct distinct elements.
func (m *MultiSet) Add(e string) bool { return m.AddN(e, 1) }

// AddN records n occurrences of e. A non-positive n is a no-op returning true.
func (m *MultiSet) AddN(e string, n int) bool {
	if n <= 0 {
		return true
	}
	if _, seen := m.counts[e]; !seen && len(m.counts) >= MaxDistinct {
		return false
	}
	m.counts[e] += n
	m.total += n
	return true
}

// Count returns how many times e occurs; zero when absent.
func (m *MultiSet) Count(e string) int { return m.counts[e] }

// Has reports whether e occurs at least once.
func (m *MultiSet) Has(e string) bool { return m.counts[e] > 0 }

// Remove drops one occurrence of e, deleting it entirely when the count hits
// zero. Returns false when e was not present.
func (m *MultiSet) Remove(e string) bool { return m.RemoveN(e, 1) }

// RemoveN drops up to n occurrences of e. Returns false when e was absent.
// Removing more than are present clears the element rather than going negative.
func (m *MultiSet) RemoveN(e string, n int) bool {
	have, ok := m.counts[e]
	if !ok || n <= 0 {
		return false
	}
	if n >= have {
		delete(m.counts, e)
		m.total -= have
		return true
	}
	m.counts[e] = have - n
	m.total -= n
	return true
}

// RemoveAll drops every occurrence of e. Returns false when e was absent.
func (m *MultiSet) RemoveAll(e string) bool {
	have, ok := m.counts[e]
	if !ok {
		return false
	}
	delete(m.counts, e)
	m.total -= have
	return true
}

// Distinct returns the number of distinct elements.
func (m *MultiSet) Distinct() int { return len(m.counts) }

// Total returns the sum of every count.
func (m *MultiSet) Total() int { return m.total }

// IsEmpty reports whether the set holds nothing.
func (m *MultiSet) IsEmpty() bool { return len(m.counts) == 0 }

// Elements returns the distinct elements, sorted.
func (m *MultiSet) Elements() []string {
	out := make([]string, 0, len(m.counts))
	for e := range m.counts {
		out = append(out, e)
	}
	sort.Strings(out)
	return out
}

// Expand returns every occurrence, sorted — a multiset flattened back to a
// slice. Length equals Total.
func (m *MultiSet) Expand() []string {
	out := make([]string, 0, m.total)
	for _, e := range m.Elements() {
		for i := 0; i < m.counts[e]; i++ {
			out = append(out, e)
		}
	}
	return out
}

// Entry pairs an element with its count.
type Entry struct {
	Elem  string
	Count int
}

// byRank orders entries by count descending, then element ascending — a TOTAL
// order, so ranking never depends on map iteration.
type byRank []Entry

func (r byRank) Len() int      { return len(r) }
func (r byRank) Swap(i, j int) { r[i], r[j] = r[j], r[i] }
func (r byRank) Less(i, j int) bool {
	if r[i].Count != r[j].Count {
		return r[i].Count > r[j].Count
	}
	return r[i].Elem < r[j].Elem
}

// MostCommon returns the n most frequent entries, ranked by count descending
// then element ascending. n <= 0, or larger than the number of distinct
// elements, returns them all.
func (m *MultiSet) MostCommon(n int) []Entry {
	all := make([]Entry, 0, len(m.counts))
	for e, c := range m.counts {
		all = append(all, Entry{Elem: e, Count: c})
	}
	sort.Sort(byRank(all))
	if n <= 0 || n > len(all) {
		return all
	}
	return all[:n]
}

// Union returns a set where each element's count is the MAXIMUM of the two —
// the standard multiset union.
func (m *MultiSet) Union(other *MultiSet) *MultiSet {
	out := m.Clone()
	for e, c := range other.counts {
		if c > out.counts[e] {
			out.setCount(e, c)
		}
	}
	return out
}

// Intersect returns a set where each element's count is the MINIMUM of the two,
// keeping only elements present in both.
func (m *MultiSet) Intersect(other *MultiSet) *MultiSet {
	out := New()
	for e, c := range m.counts {
		if oc, ok := other.counts[e]; ok {
			if oc < c {
				c = oc
			}
			out.AddN(e, c)
		}
	}
	return out
}

// Sum returns a set where each element's count is the SUM of the two.
func (m *MultiSet) Sum(other *MultiSet) *MultiSet {
	out := m.Clone()
	for e, c := range other.counts {
		out.AddN(e, c)
	}
	return out
}

// Clone returns an independent copy.
func (m *MultiSet) Clone() *MultiSet {
	out := New()
	for e, c := range m.counts {
		out.counts[e] = c
	}
	out.total = m.total
	return out
}

// setCount overwrites an element's count, keeping total in step.
func (m *MultiSet) setCount(e string, c int) {
	m.total += c - m.counts[e]
	m.counts[e] = c
}
