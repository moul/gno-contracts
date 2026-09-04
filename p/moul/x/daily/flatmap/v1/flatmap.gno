// Package flatmap is a sorted-vector map — the STL flat_map / Abseil
// btree_map trade — as a pure, reusable package.
//
// Keys and values live in two parallel sorted slices instead of a hash table or
// a tree of nodes. Lookup is a binary search, O(log n) rather than O(1), but it
// touches contiguous memory instead of chasing pointers, iteration is already
// in key order with nothing to sort, and there is no per-entry node overhead.
// Insertion in the middle is O(n) because it shifts the tail. That is the whole
// bargain: cheap reads and cheap ordered iteration, paid for at write time.
//
// On chain the ordering is the real draw. A built-in gno map iterates in an
// unspecified order, so a Render built from one can differ between nodes — a
// consensus bug rather than a cosmetic one. A flat map is sorted by
// construction, so iteration is deterministic without a sort on every read.
//
// Appending in ascending key order is the fast path: it hits the end of the
// slice and shifts nothing.
//
// A live demo of this package is at
// [r/moul/x/daily/flatmapdemo](/r/moul/x/daily/flatmapdemo/v1).
package flatmap

import "sort"

// MaxEntries bounds the map so gas stays predictable.
const MaxEntries = 4096

// FlatMap is a string->string map backed by parallel sorted slices.
type FlatMap struct {
	keys []string
	vals []string
}

// New returns an empty FlatMap.
func New() *FlatMap { return &FlatMap{} }

// Len returns the number of entries.
func (f *FlatMap) Len() int { return len(f.keys) }

// IsEmpty reports whether the map holds nothing.
func (f *FlatMap) IsEmpty() bool { return len(f.keys) == 0 }

// search returns the index where key is, or would be inserted, plus whether it
// is actually present.
func (f *FlatMap) search(key string) (int, bool) {
	i := sort.SearchStrings(f.keys, key)
	return i, i < len(f.keys) && f.keys[i] == key
}

// Get returns the value for key.
func (f *FlatMap) Get(key string) (string, bool) {
	i, found := f.search(key)
	if !found {
		return "", false
	}
	return f.vals[i], true
}

// Has reports whether key is present.
func (f *FlatMap) Has(key string) bool { _, found := f.search(key); return found }

// Set inserts or updates key. Returns false only when the map is full and key
// is new — updating an existing key always succeeds.
func (f *FlatMap) Set(key, value string) bool {
	i, found := f.search(key)
	if found {
		f.vals[i] = value
		return true
	}
	if len(f.keys) >= MaxEntries {
		return false
	}
	// Grow by one, then shift the tail right to open a slot at i.
	f.keys = append(f.keys, "")
	f.vals = append(f.vals, "")
	copy(f.keys[i+1:], f.keys[i:])
	copy(f.vals[i+1:], f.vals[i:])
	f.keys[i] = key
	f.vals[i] = value
	return true
}

// Delete removes key. Returns false when absent.
func (f *FlatMap) Delete(key string) bool {
	i, found := f.search(key)
	if !found {
		return false
	}
	copy(f.keys[i:], f.keys[i+1:])
	copy(f.vals[i:], f.vals[i+1:])
	f.keys = f.keys[:len(f.keys)-1]
	f.vals = f.vals[:len(f.vals)-1]
	return true
}

// Keys returns the keys in sorted order, as a copy.
func (f *FlatMap) Keys() []string {
	out := make([]string, len(f.keys))
	copy(out, f.keys)
	return out
}

// Values returns the values ordered by their keys, as a copy.
func (f *FlatMap) Values() []string {
	out := make([]string, len(f.vals))
	copy(out, f.vals)
	return out
}

// At returns the i-th entry in key order — the indexed access a hash map cannot
// offer, and one reason to pay for sorted storage.
func (f *FlatMap) At(i int) (key, value string, ok bool) {
	if i < 0 || i >= len(f.keys) {
		return "", "", false
	}
	return f.keys[i], f.vals[i], true
}

// Iterate calls fn for each entry in key order. Returning true stops.
func (f *FlatMap) Iterate(fn func(key, value string) bool) {
	for i := range f.keys {
		if fn(f.keys[i], f.vals[i]) {
			return
		}
	}
}

// Range calls fn for entries with lo <= key < hi, in key order. An empty hi
// means "to the end". This is the other thing sorted storage buys: a range
// query is two binary searches and a walk.
func (f *FlatMap) Range(lo, hi string, fn func(key, value string) bool) {
	start := sort.SearchStrings(f.keys, lo)
	for i := start; i < len(f.keys); i++ {
		if hi != "" && f.keys[i] >= hi {
			return
		}
		if fn(f.keys[i], f.vals[i]) {
			return
		}
	}
}

// Clone returns an independent copy.
func (f *FlatMap) Clone() *FlatMap {
	return &FlatMap{keys: f.Keys(), vals: f.Values()}
}

// Sorted reports whether the backing slice is in strictly ascending order.
// Always true through the public API; exported so callers can assert it.
func (f *FlatMap) Sorted() bool {
	for i := 1; i < len(f.keys); i++ {
		if f.keys[i-1] >= f.keys[i] {
			return false
		}
	}
	return len(f.keys) == len(f.vals)
}
