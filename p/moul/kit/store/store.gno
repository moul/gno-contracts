// Package store is the auto-id ordered collection every r/moul realm was
// building by hand: an avl.Tree, an int counter, and a private function that
// zero-pads the counter into a key so the tree iterates in the order a human
// expects.
//
// Sixteen realm files in this repo carry that third piece. They do not agree:
//
//	padID  width 6   for len(s) < 6 { s = "0" + s }            asciiart
//	pad    width 12  for len(s) < 12 { s = "0" + s }           tictactoe
//	key    width 12  the same loop, a different name           blog, crowdfund,
//	                                                           englishauction,
//	                                                           erc721, splitter
//	idKey  width 12  the same loop, a third name               connect4
//	idKey  width 12  strings.Repeat, guarded by len(s) >= 12   governor, todos
//	idKey  width 12  strings.Repeat, UNGUARDED                 timecapsule
//	seqKey width 16  strings.Repeat, guarded                   guestbook
//
// Every one of them is a silent ceiling. Past the width, the padding stops and
// the tree starts ordering "1000000000000" before "999999999999", so the list
// a realm renders is simply wrong from that entry on. The unguarded variant is
// worse: strings.Repeat panics on a negative count, so the realm stops
// accepting writes rather than merely mis-sorting them. asciiart's width of 6
// puts that ceiling at one million entries.
//
// The ceiling exists because the key is a decimal string, and decimal strings
// do not sort numerically. This package removes the ceiling by removing the
// decision: keys are the big-endian bytes of a [gno.land/p/nt/seqid/v0] ID, a
// fixed 8 bytes whose lexicographic order IS numeric order, for every value a
// uint64 can hold. There is no width to pick and no width to outgrow.
//
// # Usage
//
//	var games store.Store             // the zero value is an empty store
//
//	func NewGame(cur realm) int64 {
//		id := games.Add(&Game{...})
//		return int64(id)
//	}
//
//	func Move(cur realm, gameID int64, cell int) {
//		g := games.MustGet(store.ID(gameID)).(*Game)
//		...
//	}
//
//	func Render(path string) string {
//		for _, e := range games.PageReverse(1, 20) {   // newest first
//			g := e.Value.(*Game)
//			... e.ID ...
//		}
//	}
//
// # Identifiers
//
// An ID is a uint64 that renders as a plain decimal number, so a realm ported
// to this package keeps showing "#7" exactly as it did before. Only the avl
// key changes, and the key was never user-visible.
//
// IDs start at 1. The zero ID is never assigned, so it is usable as "absent",
// and [Store.Get] on it always misses.
//
// Removing an entry does not free its ID. IDs are a history, not a dense
// index: reusing one would silently repoint an old link at a new object.
package store

import (
	"strconv"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/seqid/v0"
)

// ID identifies one entry. It is a plain integer to the outside world and an
// ordered fixed-width key inside the tree.
type ID uint64

// String renders the ID in decimal, which is how realms show it and how it
// arrives back in a Render path.
func (id ID) String() string { return strconv.FormatUint(uint64(id), 10) }

// Key is the avl key for the ID: the 8 big-endian bytes of the underlying
// seqid, whose byte order is its numeric order.
//
// Exposed because a realm that keeps a secondary index keyed by the same ID
// needs the identical key, and because it is the one place the encoding is
// decided.
func (id ID) Key() string { return seqid.ID(id).Binary() }

// ParseID reads an ID from its decimal form, the shape it has in a Render
// path or a function argument.
//
// It returns false for anything that is not a plain unsigned decimal, which
// includes "", "-1", "1.0", a value past uint64, and the zero ID (never
// assigned, so accepting it would only produce a lookup that cannot hit).
// Leading zeros are accepted: "007" is the ID 7.
func ParseID(s string) (ID, bool) {
	n, err := strconv.ParseUint(s, 10, 64)
	if err != nil || n == 0 {
		return 0, false
	}
	return ID(n), true
}

// Entry is one ID/value pair, as returned by the paging methods.
type Entry struct {
	ID    ID
	Value any
}

// Store is an ordered collection of values under auto-assigned IDs.
//
// The zero Store is an empty store and is ready to use, so a realm can declare
// one as a package-level var without an initializer. [New] exists for the
// pointer form.
type Store struct {
	tree  avl.Tree
	last  seqid.ID
	label string
}

// New returns an empty store.
func New() *Store { return &Store{} }

// Named is [New] with a noun for what the store holds, used in the panic
// [Store.MustGet] raises: store.Named("game") makes it "game #7 not found"
// instead of "store: no entry #7".
//
// It exists so porting a realm to this package does not have to trade its own
// error wording for one shared implementation. The realms being replaced here
// panic "game not found", "proposal not found", "capsule not found"; the label
// keeps that and adds the id they all omitted.
func Named(label string) *Store { return &Store{label: label} }

// Add stores v under the next ID and returns it.
//
// It panics if the ID space is exhausted, which is [seqid.ID.Next]'s behaviour
// and requires 2^64 insertions to reach.
func (s *Store) Add(v any) ID {
	id := ID(s.last.Next())
	s.tree.Set(id.Key(), v)
	return id
}

// Set writes v at an existing or explicit ID, and reports whether it replaced
// a value.
//
// Use it to update an entry in place. It does not move the ID counter, so
// setting an ID above [Store.LastID] leaves a gap that [Store.Add] will later
// walk into and overwrite. Prefer [Store.Add] to create.
func (s *Store) Set(id ID, v any) (replaced bool) {
	return s.tree.Set(id.Key(), v)
}

// Get returns the value at id, and whether it was there.
//
// Unlike avl.Tree.Get, a nil value stored at a live ID is distinguishable from
// an absent one, because the second result comes from Has rather than from the
// value being nil.
func (s *Store) Get(id ID) (any, bool) {
	k := id.Key()
	if !s.tree.Has(k) {
		return nil, false
	}
	return s.tree.Get(k), true
}

// MustGet returns the value at id, or panics.
//
// This is the "get or panic" the realms wrote eighteen times, with one
// implementation instead of eighteen. The panic names the id, which none of
// them did: "store: no entry #7", or "game #7 not found" for a store built
// with [Named].
func (s *Store) MustGet(id ID) any {
	v, ok := s.Get(id)
	if !ok {
		panic(s.missing(id))
	}
	return v
}

func (s *Store) missing(id ID) string {
	if s.label == "" {
		return "store: no entry #" + id.String()
	}
	return s.label + " #" + id.String() + " not found"
}

// Has reports whether id is present.
func (s *Store) Has(id ID) bool { return s.tree.Has(id.Key()) }

// Remove deletes the entry at id and returns the value it held.
//
// The ID is not recycled: see the package doc.
func (s *Store) Remove(id ID) (any, bool) { return s.tree.Remove(id.Key()) }

// Len reports how many entries are present. Removals lower it; [Store.LastID]
// does not move.
func (s *Store) Len() int { return s.tree.Size() }

// LastID is the highest ID ever assigned, or 0 when nothing has been added.
// It is the count of insertions, not of live entries.
func (s *Store) LastID() ID { return ID(s.last) }

// Each visits every entry in ascending ID order.
//
// It takes no stop signal on purpose: this is the common case, and a callback
// whose bool means "stop" reads identically to one whose bool means
// "continue". When iteration has to end early, say so in the name and use
// [Store.EachUntil].
func (s *Store) Each(fn func(id ID, v any)) {
	s.tree.Iterate("", "", func(k string, v any) bool {
		fn(keyID(k), v)
		return false
	})
}

// EachReverse is [Store.Each] in descending ID order, which is what a
// newest-first list wants.
func (s *Store) EachReverse(fn func(id ID, v any)) {
	s.tree.ReverseIterate("", "", func(k string, v any) bool {
		fn(keyID(k), v)
		return false
	})
}

// EachUntil visits entries in ascending ID order and stops when fn returns
// true. It reports whether it stopped early.
//
// True means stop, matching avl.IterCbFn exactly, so a callback moved between
// this package and a raw tree keeps its meaning.
func (s *Store) EachUntil(fn func(id ID, v any) bool) bool {
	return s.tree.Iterate("", "", func(k string, v any) bool {
		return fn(keyID(k), v)
	})
}

// EachReverseUntil is [Store.EachUntil] in descending ID order.
func (s *Store) EachReverseUntil(fn func(id ID, v any) bool) bool {
	return s.tree.ReverseIterate("", "", func(k string, v any) bool {
		return fn(keyID(k), v)
	})
}

// Page returns page number page of size entries, in ascending ID order.
//
// Pages are 1-based, because they are shown to a reader ("page 1 of 4") and an
// off-by-one between the URL and the label is the bug this saves. A page past
// the end, or a page or size below 1, returns an empty slice rather than
// panicking: the page number usually comes from a Render path, which is user
// input.
//
// It walks only the requested window, not the whole tree.
func (s *Store) Page(page, size int) []Entry {
	return s.slice(page, size, false)
}

// PageReverse is [Store.Page] in descending ID order: page 1 holds the newest
// entries.
func (s *Store) PageReverse(page, size int) []Entry {
	return s.slice(page, size, true)
}

func (s *Store) slice(page, size int, reverse bool) []Entry {
	if page < 1 || size < 1 {
		return nil
	}
	offset := (page - 1) * size
	out := make([]Entry, 0, size)
	cb := func(k string, v any) bool {
		out = append(out, Entry{ID: keyID(k), Value: v})
		return false
	}
	if reverse {
		s.tree.ReverseIterateByOffset(offset, size, cb)
	} else {
		s.tree.IterateByOffset(offset, size, cb)
	}
	return out
}

// Pages reports how many pages of the given size the store holds, which is
// what a pager footer needs. A size below 1 gives 0.
func (s *Store) Pages(size int) int {
	if size < 1 {
		return 0
	}
	n := s.Len()
	return (n + size - 1) / size
}

// keyID decodes an avl key back to its ID. The keys in this tree are always
// written by ID.Key, so a short or malformed key means the tree was written by
// something other than this package.
func keyID(k string) ID {
	if len(k) != 8 {
		panic("store: foreign key in tree")
	}
	var n uint64
	for i := 0; i < 8; i++ {
		n = n<<8 | uint64(k[i])
	}
	return ID(n)
}
