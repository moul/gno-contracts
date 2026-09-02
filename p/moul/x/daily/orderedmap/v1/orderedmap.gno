// Package orderedmap is a map that remembers the order its keys were inserted,
// as a pure, reusable package.
//
// This matters more on chain than off it. gno map iteration order is
// unspecified, so a realm that ranges over a built-in map to build its Render
// can emit a different page on every call — which is a consensus bug, not a
// cosmetic one. This type gives back a deterministic order without needing the
// keys to be sortable.
//
// Backed by a built-in map for O(1) lookup plus a slice holding insertion
// order. Delete is O(n) in the number of keys, because it has to close the gap
// in that slice — an honest trade for O(1) Get and an allocation-free walk.
// Re-Setting an existing key updates the value and KEEPS its original position:
// insertion order means first insertion, not last write.
//
// A live demo of this package is at
// [r/moul/x/daily/orderedmapdemo](/r/moul/x/daily/orderedmapdemo/v1).
package orderedmap

// MaxKeys bounds the map so gas stays predictable.
const MaxKeys = 4096

// OrderedMap is a string-keyed map with deterministic iteration.
type OrderedMap struct {
	m    map[string]string
	keys []string
}

// New returns an empty OrderedMap.
func New() *OrderedMap {
	return &OrderedMap{m: map[string]string{}}
}

// Len returns the number of entries.
func (o *OrderedMap) Len() int { return len(o.keys) }

// Set inserts or updates k. Updating an existing key keeps its original
// position — insertion order means FIRST insertion. Returns false when the map
// is full and k is new.
func (o *OrderedMap) Set(k, v string) bool {
	if _, ok := o.m[k]; ok {
		o.m[k] = v
		return true
	}
	if len(o.keys) >= MaxKeys {
		return false
	}
	o.m[k] = v
	o.keys = append(o.keys, k)
	return true
}

// Get returns the value for k.
func (o *OrderedMap) Get(k string) (string, bool) {
	v, ok := o.m[k]
	return v, ok
}

// Has reports whether k is present.
func (o *OrderedMap) Has(k string) bool {
	_, ok := o.m[k]
	return ok
}

// Delete removes k and reports whether it was present. O(n): the key's slot in
// the order slice has to be closed up, and the remaining keys shifted, so that
// order is preserved.
func (o *OrderedMap) Delete(k string) bool {
	if _, ok := o.m[k]; !ok {
		return false
	}
	delete(o.m, k)
	for i, kk := range o.keys {
		if kk == k {
			o.keys = append(o.keys[:i], o.keys[i+1:]...)
			break
		}
	}
	return true
}

// Keys returns the keys in insertion order, as an independent copy.
func (o *OrderedMap) Keys() []string {
	out := make([]string, len(o.keys))
	copy(out, o.keys)
	return out
}

// Values returns the values in key-insertion order.
func (o *OrderedMap) Values() []string {
	out := make([]string, 0, len(o.keys))
	for _, k := range o.keys {
		out = append(out, o.m[k])
	}
	return out
}

// Iterate calls fn for each entry in insertion order, stopping early if fn
// returns true. The map must not be mutated from inside fn — the walk is over
// a live slice.
func (o *OrderedMap) Iterate(fn func(k, v string) bool) {
	for _, k := range o.keys {
		if fn(k, o.m[k]) {
			return
		}
	}
}

// At returns the i-th entry in insertion order.
func (o *OrderedMap) At(i int) (k, v string, ok bool) {
	if i < 0 || i >= len(o.keys) {
		return "", "", false
	}
	k = o.keys[i]
	return k, o.m[k], true
}

// Clone returns an independent copy preserving order.
func (o *OrderedMap) Clone() *OrderedMap {
	c := New()
	for _, k := range o.keys {
		c.Set(k, o.m[k])
	}
	return c
}
