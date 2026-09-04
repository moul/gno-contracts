// Package bidimap is a bidirectional map — unique in both directions — as a
// pure, reusable package.
//
// A normal map answers "what is the value for this key". A bidirectional one
// also answers the reverse in O(1), by keeping a second index. The cost is an
// invariant a plain pair of maps does not give you: BOTH sides are unique, so
// inserting a pair whose value already belongs to another key must do something
// deliberate rather than silently corrupt the reverse index.
//
// This implementation makes that choice explicit. Put REPLACES: it evicts any
// existing pairing on either side first, so the two indexes can never disagree.
// PutUnique refuses instead, returning false. Pick whichever the caller wants;
// what is not on offer is a half-updated map.
//
// Iteration is over sorted keys, never a built-in map range: gno map iteration
// order is unspecified, and a Render built from one can differ between nodes,
// which is a consensus bug rather than a cosmetic one.
//
// A live demo of this package is at
// [r/moul/x/daily/bidimapdemo](/r/moul/x/daily/bidimapdemo/v1).
package bidimap

import "sort"

// MaxPairs bounds the map so gas stays predictable.
const MaxPairs = 4096

// BiMap is a string<->string map, unique in both directions.
type BiMap struct {
	fwd map[string]string
	rev map[string]string
}

// New returns an empty BiMap.
func New() *BiMap {
	return &BiMap{fwd: map[string]string{}, rev: map[string]string{}}
}

// Len returns the number of pairs.
func (m *BiMap) Len() int { return len(m.fwd) }

// Get returns the value bound to key.
func (m *BiMap) Get(key string) (string, bool) {
	v, ok := m.fwd[key]
	return v, ok
}

// GetKey returns the key bound to value — the reverse lookup, also O(1).
func (m *BiMap) GetKey(value string) (string, bool) {
	k, ok := m.rev[value]
	return k, ok
}

// Has reports whether key is present.
func (m *BiMap) Has(key string) bool { _, ok := m.fwd[key]; return ok }

// HasValue reports whether value is present.
func (m *BiMap) HasValue(value string) bool { _, ok := m.rev[value]; return ok }

// Put binds key<->value, REPLACING any existing pairing on either side. It
// returns the pairs that were evicted to make room, so the caller can see what
// it displaced rather than discovering it later.
//
// Returns ok=false only when the map is full and the pair is entirely new.
func (m *BiMap) Put(key, value string) (evicted [][2]string, ok bool) {
	oldValue, keyTaken := m.fwd[key]

	// Already exactly this pair: nothing to do.
	if keyTaken && oldValue == value {
		return nil, true
	}

	oldKey, valueTaken := m.rev[value]

	// Only a pair that is new on BOTH sides grows the map. Rebinding either
	// side reuses a slot, so it stays allowed at capacity. Checked up front:
	// evicting first and rolling back on failure would be unreachable code,
	// since any eviction frees the very slot the check is about.
	if !keyTaken && !valueTaken && len(m.fwd) >= MaxPairs {
		return nil, false
	}

	if keyTaken {
		evicted = append(evicted, [2]string{key, oldValue})
		delete(m.rev, oldValue)
		delete(m.fwd, key)
	}
	if valueTaken {
		evicted = append(evicted, [2]string{oldKey, value})
		delete(m.fwd, oldKey)
		delete(m.rev, value)
	}

	m.fwd[key] = value
	m.rev[value] = key
	return evicted, true
}

// PutUnique binds key<->value only when NEITHER side is already taken by a
// different pairing. Returns false without changing anything otherwise.
func (m *BiMap) PutUnique(key, value string) bool {
	if v, exists := m.fwd[key]; exists {
		return v == value // idempotent for the identical pair
	}
	if _, exists := m.rev[value]; exists {
		return false
	}
	if len(m.fwd) >= MaxPairs {
		return false
	}
	m.fwd[key] = value
	m.rev[value] = key
	return true
}

// Delete removes the pair for key. Returns false when key is absent.
func (m *BiMap) Delete(key string) bool {
	v, ok := m.fwd[key]
	if !ok {
		return false
	}
	delete(m.fwd, key)
	delete(m.rev, v)
	return true
}

// DeleteValue removes the pair for value. Returns false when value is absent.
func (m *BiMap) DeleteValue(value string) bool {
	k, ok := m.rev[value]
	if !ok {
		return false
	}
	delete(m.fwd, k)
	delete(m.rev, value)
	return true
}

// Keys returns every key, sorted. Sorted, not map order: a Render built from an
// unspecified order can differ between nodes.
func (m *BiMap) Keys() []string { return sortedKeys(m.fwd) }

// Values returns every value, sorted.
func (m *BiMap) Values() []string { return sortedKeys(m.rev) }

// Iterate calls fn for each pair in sorted key order. Returning true stops.
func (m *BiMap) Iterate(fn func(key, value string) bool) {
	for _, k := range m.Keys() {
		if fn(k, m.fwd[k]) {
			return
		}
	}
}

// Invert returns a new BiMap with keys and values swapped.
func (m *BiMap) Invert() *BiMap {
	out := New()
	for k, v := range m.fwd {
		out.fwd[v] = k
		out.rev[k] = v
	}
	return out
}

// Clone returns an independent copy.
func (m *BiMap) Clone() *BiMap {
	out := New()
	for k, v := range m.fwd {
		out.fwd[k] = v
		out.rev[v] = k
	}
	return out
}

// Consistent reports whether the two indexes agree. Always true through the
// public API; exported so tests and callers can assert the invariant directly.
func (m *BiMap) Consistent() bool {
	if len(m.fwd) != len(m.rev) {
		return false
	}
	for k, v := range m.fwd {
		if back, ok := m.rev[v]; !ok || back != k {
			return false
		}
	}
	return true
}

func sortedKeys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
