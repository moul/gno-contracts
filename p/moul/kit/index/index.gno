// Package index is the secondary index every realm with a store was writing by
// hand: a lookup from a key a human typed to the [store.ID]s that carry it.
//
// A realm keeps its records in a [gno.land/p/moul/kit/store] and answers
// "entry 7". The moment it also has to answer "every entry tagged gno" it needs
// a second container, and the correctness of the pair is entirely in the
// discipline of writing both in the same function. This package owns the second
// container and as much of that discipline as a package can.
//
//	var notes = store.Named("note")
//	var byTag index.Index // the zero value is an empty, usable index
//
//	func Post(cur realm, tag, body string) int64 {
//		id := notes.Add(&note{Tag: tag, Body: body})
//		if err := byTag.Add(tag, id); err != nil {
//			panic(err) // the store write is not committed either: same frame
//		}
//		return int64(id)
//	}
//
// It is NOT a multi-index record store. [gno.land/p/moul/collection] is that,
// and at n = 1,000 an update there costs 964,833 gas against the 508,977 that
// created the record, because it re-indexes every index whether or not the
// indexed value changed. Two containers written side by side cost a third of
// that and the realm can see what it is paying for.
//
// Live demo: r/moul/x/kitindexdemo.
package index

import (
	"errors"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/bptree/v0"
)

// Fanout is the B+ tree fanout this package uses, and 128 is not the package
// default of 32.
//
// Measured against gno master 1fc4c140e on 2026-09-29, at n = 1,000 with string
// values: fanout 128 costs 592 bytes per entry and 152,975 gas per insert,
// against 671 and 162,161 at fanout 32, and against avl's 2,029 and 417,811.
// Raising the fanout amortises the node objects, and nothing below it can be
// recovered: the remaining cost is the B+ tree's per-entry value box.
const Fanout = 128

// Errors an Add can return. A /p/ package returns errors and lets the realm
// decide whether they are fatal; every one of these is a programming error in
// the realm rather than a value a user chose, so panicking on them is the
// normal handling.
var (
	// ErrEmptyKey is returned for "". An empty key sorts before every real one
	// and is almost always an unset field rather than a deliberate bucket, so
	// it is refused rather than silently indexed.
	ErrEmptyKey = errors.New("index: the key is empty")

	// ErrZeroID is returned for store.ID(0), which [store.Store] never assigns,
	// so indexing it can only produce a lookup that cannot hit.
	ErrZeroID = errors.New("index: the id is zero")

	// ErrDuplicateKey is returned by a [Unique] index asked to attach a second
	// id to a key that already has one.
	ErrDuplicateKey = errors.New("index: the key is already taken")
)

// Index maps a key to the ids carrying it, ordered by key.
//
// The zero value is an empty, usable, non-unique index: a realm declares
// `var byTag index.Index` and writes to it, exactly as it does with a
// [store.Store]. Use [Unique] when at most one id may carry a key.
//
// An Index is a handle, like the [store.Store] it sits next to: copies taken
// after the first write, or of anything [Unique] returned, are the same index,
// and a write through one is seen through all of them. A copy of a zero value
// that was never written is a separate empty index.
type Index struct {
	s *state
}

// state is everything an Index holds, behind one pointer so that a copy of the
// handle cannot split the tree from the counter that describes it.
type state struct {
	tree   *bptree.BPTree
	unique bool
	pairs  int
}

// New returns an empty index where a key may carry many ids. It is the zero
// value, spelled out for a caller who prefers a constructor.
func New() *Index { return &Index{} }

// Unique returns an empty index where a key carries at most one id, and a
// second [Index.Add] to the same key fails with [ErrDuplicateKey] instead of
// appending.
//
// Unique is a constructor rather than a field or a setter because flipping it
// on a populated index would have to either reject the duplicates already in it
// or silently keep them, and both are worse than not offering the operation.
func Unique() *Index {
	return &Index{s: &state{tree: bptree.NewBPTreeN(Fanout), unique: true}}
}

// entry is the value stored at a key: the ids carrying it, ascending.
//
// A struct rather than a bare []store.ID so that a later field (a count, a
// timestamp) does not change the stored shape, and so the slice itself is never
// handed out by accident.
type entry struct {
	ids []store.ID
}

// init materialises the state. Called by every mutating method, so the zero
// value works without a constructor. The tree is created with the state, so a
// non-nil state always has one.
func (ix *Index) init() {
	if ix.s == nil {
		ix.s = &state{tree: bptree.NewBPTreeN(Fanout)}
	}
}

// Add attaches id to key.
//
// Adding a pair that is already present is a no-op and returns nil, so a realm
// re-running a write is not punished for it. The ids under a key are kept
// ascending, which makes [Index.Lookup] depend on the set of ids and not on the
// order they arrived in: two realms that indexed the same records in a
// different order render identically, and a Render whose output depends on
// insertion history is the determinism bug this avoids.
func (ix *Index) Add(key string, id store.ID) error {
	if key == "" {
		return ErrEmptyKey
	}
	if id == 0 {
		return ErrZeroID
	}
	ix.init()

	e, _ := ix.s.tree.Get(key).(*entry)
	if e == nil {
		ix.s.tree.Set(key, &entry{ids: []store.ID{id}})
		ix.s.pairs++
		return nil
	}
	pos, found := e.find(id)
	if found {
		return nil
	}
	if ix.s.unique {
		return ErrDuplicateKey
	}
	e.ids = append(e.ids, 0)
	copy(e.ids[pos+1:], e.ids[pos:])
	e.ids[pos] = id
	ix.s.tree.Set(key, e)
	ix.s.pairs++
	return nil
}

// Remove detaches id from key and reports whether the pair was there. A key
// whose last id is removed is removed with it, so [Index.Keys] never counts an
// empty bucket.
func (ix *Index) Remove(key string, id store.ID) bool {
	if ix.s == nil {
		return false
	}
	e, _ := ix.s.tree.Get(key).(*entry)
	if e == nil {
		return false
	}
	pos, found := e.find(id)
	if !found {
		return false
	}
	ix.s.pairs--
	if len(e.ids) == 1 {
		ix.s.tree.Remove(key)
		return true
	}
	// A fresh slice, not append(ids[:pos], ids[pos+1:]...).
	//
	// In gno a slice is ONE persisted object and the storage deposit comes back
	// when that object is dropped, at no other time: shortening in place keeps
	// the peak allocation charged until the whole key goes, so a key that grew
	// to 1,000 ids and shrank to 1 would still be paying for 1,000. Allocating
	// the exact size drops the old array and refunds the difference. Same O(n)
	// as the memmove it replaces.
	trimmed := make([]store.ID, 0, len(e.ids)-1)
	trimmed = append(trimmed, e.ids[:pos]...)
	trimmed = append(trimmed, e.ids[pos+1:]...)
	e.ids = trimmed
	ix.s.tree.Set(key, e)
	return true
}

// RemoveKey detaches every id from key and reports how many it detached.
func (ix *Index) RemoveKey(key string) int {
	if ix.s == nil {
		return 0
	}
	v, removed := ix.s.tree.Remove(key)
	if !removed {
		return 0
	}
	n := len(v.(*entry).ids)
	ix.s.pairs -= n
	return n
}

// Lookup returns the ids carrying key, ascending, or nil.
//
// The slice is a COPY. Handing out the stored one would make every caller a
// writer: an append past its length would be invisible to the index, and an
// assignment into it would corrupt the index with no write path having been
// called. A realm that returns this value onward is returning its own data,
// not a handle to ours.
func (ix *Index) Lookup(key string) []store.ID {
	if ix.s == nil {
		return nil
	}
	e, _ := ix.s.tree.Get(key).(*entry)
	if e == nil {
		return nil
	}
	out := make([]store.ID, len(e.ids))
	copy(out, e.ids)
	return out
}

// First returns the lowest id carrying key. On a [Unique] index it is the only
// one, which is the usual reason to call it.
func (ix *Index) First(key string) (store.ID, bool) {
	if ix.s == nil {
		return 0, false
	}
	e, _ := ix.s.tree.Get(key).(*entry)
	if e == nil || len(e.ids) == 0 {
		return 0, false
	}
	return e.ids[0], true
}

// Has reports whether any id carries key.
func (ix *Index) Has(key string) bool {
	if ix.s == nil {
		return false
	}
	return ix.s.tree.Has(key)
}

// Count returns how many ids carry key.
func (ix *Index) Count(key string) int {
	if ix.s == nil {
		return 0
	}
	e, _ := ix.s.tree.Get(key).(*entry)
	if e == nil {
		return 0
	}
	return len(e.ids)
}

// Keys returns the number of distinct keys.
func (ix *Index) Keys() int {
	if ix.s == nil {
		return 0
	}
	return ix.s.tree.Size()
}

// Len returns the number of (key, id) pairs, which is what the index actually
// costs. It is NOT [Index.Keys], and the two differ by exactly the amount of
// fan-out a realm has.
func (ix *Index) Len() int {
	if ix.s == nil {
		return 0
	}
	return ix.s.pairs
}

// IsUnique reports whether this index was built by [Unique].
func (ix *Index) IsUnique() bool { return ix.s != nil && ix.s.unique }

// Each visits every key in ascending order with a copy of its ids, and stops
// when fn returns true. It reports whether it stopped early.
//
// True means stop, matching bptree.IterCbFn and kit/store's EachUntil exactly,
// so a callback moved between them keeps its meaning.
//
// fn must not call [Index.Add], [Index.Remove] or [Index.RemoveKey] on this
// index. The walk is the B+ tree's own, which holds a position inside a leaf:
// removing the key being visited shifts the next one into that slot and the
// walk steps over it, and inserting one ahead of it is visited twice. Collect
// what to change, then change it after Each returns.
func (ix *Index) Each(fn func(key string, ids []store.ID) bool) bool {
	if ix.s == nil {
		return false
	}
	return ix.s.tree.Iterate("", "", func(k string, v any) bool {
		e := v.(*entry)
		ids := make([]store.ID, len(e.ids))
		copy(ids, e.ids)
		return fn(k, ids)
	})
}

// Page returns page number page of size keys, ascending, each with a copy of
// its ids.
//
// Pages are 1-based and a page past the end returns nil rather than panicking,
// matching [store.Store.Page] exactly, because the page number usually arrives
// from a Render path and is user input.
func (ix *Index) Page(page, size int) []Entry {
	if ix.s == nil || page < 1 || size < 1 {
		return nil
	}
	// The offset is computed in a way that cannot wrap, because
	// bptree.IterateByOffset normalises a NEGATIVE offset to 0: an overflowed
	// (page-1)*size would silently hand back page 1 for a page past the end,
	// which is the opposite of this method's contract.
	//
	// page <= 1+(keys-1)/size bounds (page-1)*size by keys-1, so the product
	// cannot overflow, and it also rejects the page that starts exactly at the
	// end, which would otherwise come back as an empty non-nil slice while
	// every later page is nil.
	keys := ix.s.tree.Size()
	if keys == 0 || page > 1+(keys-1)/size {
		return nil
	}
	offset := (page - 1) * size

	// The capacity follows what exists, not what was asked for, so Page(1,
	// maxInt) over three keys reserves three slots and not two billion.
	room := keys - offset
	if room > size {
		room = size
	}
	out := make([]Entry, 0, room)
	ix.s.tree.IterateByOffset(offset, size, func(k string, v any) bool {
		e := v.(*entry)
		ids := make([]store.ID, len(e.ids))
		copy(ids, e.ids)
		out = append(out, Entry{Key: k, IDs: ids})
		return false
	})
	return out
}

// Pages returns how many pages of the given size the keys fill, at least 1 so
// a page picker always has something to render.
func (ix *Index) Pages(size int) int {
	if size < 1 {
		return 1
	}
	n := ix.Keys()
	if n == 0 {
		return 1
	}
	// 1 + (n-1)/size rather than (n+size-1)/size: the second overflows when
	// size is near the integer limit, wraps negative, and divides to 0, which
	// contradicts the "at least 1" this method promises and divides a page
	// picker by zero.
	return 1 + (n-1)/size
}

// Entry is one key and the ids carrying it, as returned by [Index.Page].
type Entry struct {
	Key string
	IDs []store.ID
}

// find returns the position id occupies, or would occupy, in the ascending ids,
// and whether it is already there. Binary search: a key with many ids is the
// case this package exists for.
func (e *entry) find(id store.ID) (int, bool) {
	lo, hi := 0, len(e.ids)
	for lo < hi {
		mid := int(uint(lo+hi) >> 1)
		switch {
		case e.ids[mid] == id:
			return mid, true
		case e.ids[mid] < id:
			lo = mid + 1
		default:
			hi = mid
		}
	}
	return lo, false
}
