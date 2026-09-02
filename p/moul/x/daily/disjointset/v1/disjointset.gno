// Package disjointset is union-find (a disjoint-set forest) as a pure,
// reusable package: it tracks a partition of [0, n) into disjoint groups and
// answers "are these two in the same group?" in near-constant time.
//
// Both classic optimisations are implemented, and they matter together: path
// compression flattens a tree on every Find, union by rank keeps the shallower
// tree under the deeper one. With both, operations are O(α(n)) — inverse
// Ackermann, effectively constant. With neither, a chain of unions degrades to
// O(n) per query, which on chain is the difference between a cheap call and an
// out-of-gas one.
//
// A live demo of this package is at
// [r/moul/x/daily/disjointsetdemo](/r/moul/x/daily/disjointsetdemo/v1).
package disjointset

// MaxN bounds a set so allocation stays predictable.
const MaxN = 1 << 16

// DisjointSet is a partition of [0, n) into disjoint groups.
type DisjointSet struct {
	parent []int
	rank   []int
	groups int
}

// New returns n singleton groups. n is clamped to [0, MaxN].
func New(n int) *DisjointSet {
	if n < 0 {
		n = 0
	}
	if n > MaxN {
		n = MaxN
	}
	d := &DisjointSet{parent: make([]int, n), rank: make([]int, n), groups: n}
	for i := 0; i < n; i++ {
		d.parent[i] = i // every element starts as its own root
	}
	return d
}

// Len returns the number of elements.
func (d *DisjointSet) Len() int { return len(d.parent) }

// Groups returns how many disjoint groups remain.
func (d *DisjointSet) Groups() int { return d.groups }

// InRange reports whether i is a valid element.
func (d *DisjointSet) InRange(i int) bool { return i >= 0 && i < len(d.parent) }

// Find returns the representative of i's group, or -1 when i is out of range.
//
// Path compression: every node visited is re-pointed straight at the root, so
// the next Find on any of them is O(1). Done iteratively rather than
// recursively — a deep chain would otherwise risk the call stack.
func (d *DisjointSet) Find(i int) int {
	if !d.InRange(i) {
		return -1
	}
	root := i
	for d.parent[root] != root {
		root = d.parent[root]
	}
	for d.parent[i] != root { // second pass: re-point everything at the root
		next := d.parent[i]
		d.parent[i] = root
		i = next
	}
	return root
}

// Union merges the groups of a and b and reports whether they were merged.
// False means they were already together, or an index was out of range.
func (d *DisjointSet) Union(a, b int) bool {
	ra, rb := d.Find(a), d.Find(b)
	if ra < 0 || rb < 0 || ra == rb {
		return false
	}
	// Union by rank: hang the shallower tree off the deeper one so depth only
	// grows when both sides are equally deep.
	if d.rank[ra] < d.rank[rb] {
		ra, rb = rb, ra
	}
	d.parent[rb] = ra
	if d.rank[ra] == d.rank[rb] {
		d.rank[ra]++
	}
	d.groups--
	return true
}

// Connected reports whether a and b are in the same group. Out-of-range
// indices are not connected to anything, including themselves.
func (d *DisjointSet) Connected(a, b int) bool {
	ra, rb := d.Find(a), d.Find(b)
	return ra >= 0 && ra == rb
}

// Size returns how many elements share i's group, or 0 when out of range.
func (d *DisjointSet) Size(i int) int {
	r := d.Find(i)
	if r < 0 {
		return 0
	}
	n := 0
	for j := 0; j < len(d.parent); j++ {
		if d.Find(j) == r {
			n++
		}
	}
	return n
}

// Partition returns the groups, each sorted ascending, ordered by their
// smallest member — deterministic regardless of the union order, which is what
// makes it safe to render.
func (d *DisjointSet) Partition() [][]int {
	byRoot := map[int][]int{}
	order := []int{}
	for i := 0; i < len(d.parent); i++ {
		r := d.Find(i)
		if _, seen := byRoot[r]; !seen {
			order = append(order, r) // first sighting is the smallest member
		}
		byRoot[r] = append(byRoot[r], i)
	}
	out := [][]int{}
	for _, r := range order { // iterate the slice, never the map
		out = append(out, byRoot[r])
	}
	return out
}
