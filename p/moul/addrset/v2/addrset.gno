// Package addrset provides a set of blockchain addresses, backed by a B+ tree.
//
// It is the B+ tree successor to [gno.land/p/moul/addrset/v1] (which is backed
// by an AVL tree): a bump to v2 because the backing data structure — and thus
// the on-chain storage layout — changed. The exported API is the same as v1
// (Add/Remove/Has/Size/IterateByOffset/ReverseIterateByOffset) EXCEPT that the
// v1 `Tree() avl.ITree` escape hatch is intentionally removed, so the backing
// store never leaks across realms.
//
// A B+ tree packs many entries per persisted node, so a stored address costs
// roughly ~0.9 KB vs the AVL backing's ~2.0 KB (and inserts spend materially
// less gas). Prefer v2 when the set is part of persisted realm state.
//
// Two behavioral differences from v1, both consequences of the in-place-
// mutating B+ tree backing:
//
//   - do NOT mutate the set (Add/Remove) from inside an iteration callback —
//     the AVL backing's copy-on-write tolerated it, this one does not;
//   - do NOT copy a non-zero Set by value — the copies would share live tree
//     nodes while their roots and sizes diverge (v1's copies were independent
//     snapshots).
//
// Example:
//
//	var set addrset.Set // the zero value is an empty, usable set
//
//	set.Add(addr)    // true (newly added)
//	set.Has(addr)    // true
//	set.Remove(addr) // true (was present)
package addrset

import "gno.land/p/nt/bptree/v0"

// Set stores a set of addresses in sorted order. The zero value is an empty,
// usable set.
type Set struct {
	tree bptree.BPTree
}

// Add inserts an address into the set.
// Returns true if the address was newly added, false if it already existed.
func (s *Set) Add(addr address) bool {
	return !s.tree.Set(string(addr), nil)
}

// Remove deletes an address from the set.
// Returns true if the address was found and removed, false if it didn't exist.
func (s *Set) Remove(addr address) bool {
	_, removed := s.tree.Remove(string(addr))
	return removed
}

// Has checks if an address exists in the set.
func (s *Set) Has(addr address) bool {
	return s.tree.Has(string(addr))
}

// Size returns the number of addresses in the set.
func (s *Set) Size() int {
	return s.tree.Size()
}

// IterateByOffset walks through addresses in sorted order, starting at the
// given offset and visiting up to count addresses. The callback returns true
// to stop iteration. The set must not be modified during iteration.
func (s *Set) IterateByOffset(offset int, count int, cb func(addr address) bool) {
	s.tree.IterateByOffset(offset, count, func(key string, _ any) bool {
		return cb(address(key))
	})
}

// ReverseIterateByOffset walks through addresses in reverse (descending) order,
// starting at the given offset (counted from the end) and visiting up to count
// addresses. The callback returns true to stop iteration. The set must not be
// modified during iteration.
func (s *Set) ReverseIterateByOffset(offset int, count int, cb func(addr address) bool) {
	s.tree.ReverseIterateByOffset(offset, count, func(key string, _ any) bool {
		return cb(address(key))
	})
}
