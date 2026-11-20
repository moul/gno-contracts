// Package hashring implements consistent hashing with virtual nodes as a
// pure, reusable package.
//
// The obvious way to spread K keys over N servers is hash(key) % N. It is
// balanced, it is one instruction, and it is wrong the moment N changes:
// going from 4 shards to 5 moves roughly 80% of the keys, because the modulus
// moved under every one of them at once. Everything that was cached is cold,
// everything that was local is remote, and the cost of adding a machine is a
// full reshuffle.
//
// Consistent hashing fixes the thing that is actually broken, which is that
// the mapping depends on N at all. Hash the nodes into the same 64-bit space
// as the keys and arrange that space in a circle; a key belongs to the first
// node clockwise of it. Removing a node hands its arc to its clockwise
// neighbour and touches nothing else, so the keys that move are exactly the
// keys that have to, K/N of them rather than K.
//
// A plain circle is badly balanced, though: N nodes are N random cuts of the
// space, and random cuts are far more uneven than an even split. So each node
// is hashed onto the circle Replicas times rather than once, under "node#0",
// "node#1" and so on. The arcs interleave and the law of large numbers does
// the rest.
//
// Measured over 200 four-node memberships of 6,000 keys, taking the gap
// between the largest and smallest share as a percentage of an even split:
//
//	replicas    1      8     16     32     64    128
//	mean     183%    72%    50%    36%    28%    19%
//	worst    355%   158%   110%    77%    64%    41%
//
// That is close to the 1/sqrt(Replicas) falloff theory predicts: 64 times the
// points should cut the imbalance by 8 and measured 6.5. DefaultReplicas is
// 64 because the curve is flat enough past it that the next halving costs
// another 4x in points, and points are what every Add hashes and every Get
// binary-searches.
//
// The hash is SHA-256 truncated to its first eight bytes, big-endian. It is
// part of the API, not an implementation detail: changing it would move every
// key on every chain that already deployed this package, which is why
// TestHashIsStable pins three values and no test asserts a placement in terms
// of the hash.
//
// Nothing here touches the chain. The ring is a value: build it, place keys
// with it, throw it away. A realm that wants to keep one across calls stores
// the membership (a handful of strings) and rebuilds, which costs a few
// hundred hashes, rather than persisting a few thousand ring points it would
// then have to keep sorted on chain.
//
// A live demo of this package is at
// [r/moul/x/daily/hashringdemo](/r/moul/x/daily/hashringdemo/v0).
package hashring

import (
	"crypto/sha256"
	"sort"
	"strconv"
)

// Bounds on what a Ring will hold, so an on-chain caller cannot be handed one
// whose size it did not choose: a ring costs MaxNodes*MaxReplicas points at
// the very most, and every Get is a binary search over them.
const (
	// MaxNodes is the largest membership a Ring accepts. Add refuses past it.
	MaxNodes = 256
	// MaxReplicas is the largest number of virtual points per node. New
	// clamps to it.
	MaxReplicas = 512
	// DefaultReplicas is the point count that balances well without making
	// the ring expensive to rebuild. Below about 16 the spread is visible.
	DefaultReplicas = 64
)

// Point is one virtual node: a position on the circle and the node that owns
// the arc ending there. Exported so a caller can draw the ring; Points hands
// out a copy.
type Point struct {
	Hash uint64
	Node string
}

// Ring is a consistent hashing ring. The zero value is not usable; call New.
//
// All of a ring's state sits behind one pointer, so a copy of a Ring value is
// the same ring and not half of one: copying three slice headers would let an
// Add through the copy grow a shared backing array that the original's
// shorter headers never see, and the two would disagree about the membership.
type Ring struct {
	st *ringState
}

// ringState is the ring itself. points is kept strictly increasing by Hash at
// all times, which is what makes Get a binary search rather than a scan, and
// nodes is kept sorted so that two rings built from the same membership in
// different orders are the same ring.
type ringState struct {
	replicas int
	points   []Point
	nodes    []string
}

// New returns an empty ring whose nodes each occupy replicas points on the
// circle. replicas is clamped into [1, MaxReplicas] rather than rejected: a
// ring is a data structure, not a transaction, and there is no sensible
// partially built one to hand back.
func New(replicas int) *Ring {
	if replicas < 1 {
		replicas = 1
	}
	if replicas > MaxReplicas {
		replicas = MaxReplicas
	}
	return &Ring{st: &ringState{replicas: replicas}}
}

// Replicas is the per-node point count this ring was built with.
func (r *Ring) Replicas() int { return r.st.replicas }

// Len is the number of points on the circle, which is Replicas times the
// membership. For the membership itself, use Nodes.
func (r *Ring) Len() int { return len(r.st.points) }

// Nodes returns the membership, sorted, as a copy.
func (r *Ring) Nodes() []string {
	out := make([]string, len(r.st.nodes))
	copy(out, r.st.nodes)
	return out
}

// Has reports whether node is in the ring.
func (r *Ring) Has(node string) bool {
	i := sort.SearchStrings(r.st.nodes, node)
	return i < len(r.st.nodes) && r.st.nodes[i] == node
}

// Points returns the circle, ordered, as a copy. The copy is the point: the
// live slice is what Get binary-searches, and a caller that sorted or trimmed
// it would silently corrupt every later placement.
func (r *Ring) Points() []Point {
	out := make([]Point, len(r.st.points))
	copy(out, r.st.points)
	return out
}

// Add puts node on the ring and reports whether that changed anything. It
// returns false for a node already present, for one that would push the
// membership past MaxNodes, and for the empty name: "" is what Get answers on
// an empty ring, so a node called "" would make "no owner" and "owned by the
// empty name" the same answer.
//
// The node's points are hashed, sorted among themselves and merged into the
// circle in one pass, into a fresh array: one O(len) merge rather than one
// O(len) shift per virtual point.
func (r *Ring) Add(node string) bool {
	st := r.st
	if node == "" || r.Has(node) || len(st.nodes) >= MaxNodes {
		return false
	}
	i := sort.SearchStrings(st.nodes, node)
	st.nodes = append(st.nodes, "")
	copy(st.nodes[i+1:], st.nodes[i:])
	st.nodes[i] = node

	fresh := make([]Point, 0, st.replicas)
	for v := 0; v < st.replicas; v++ {
		fresh = append(fresh, Point{Hash: pointHash(node, v), Node: node})
	}
	sort.Sort(byPosition(fresh))
	st.points = mergePoints(st.points, fresh)
	return true
}

// Remove takes node off the ring and reports whether it was there. Its arcs
// pass to their clockwise neighbours; no other key moves.
func (r *Ring) Remove(node string) bool {
	if !r.Has(node) {
		return false
	}
	// Both slices are rebuilt into fresh arrays rather than shortened in
	// place: a slice is one persisted object and the deposit only comes back
	// when that object is dropped, so a ring that shrank in place would keep
	// paying for the membership it used to have.
	st := r.st
	i := sort.SearchStrings(st.nodes, node)
	nodes := make([]string, 0, len(st.nodes)-1)
	nodes = append(nodes, st.nodes[:i]...)
	nodes = append(nodes, st.nodes[i+1:]...)
	st.nodes = nodes

	points := make([]Point, 0, len(st.points))
	for _, p := range st.points {
		if p.Node != node {
			points = append(points, p)
		}
	}
	st.points = points
	return true
}

// Get returns the node owning key, or "" when the ring is empty.
func (r *Ring) Get(key string) string {
	return r.owner(Hash(key))
}

// GetN returns the first n distinct nodes clockwise from key, head first, so
// GetN(key, 1)[0] is Get(key). It is the preference list a replicated store
// writes down: the owner, then where the copies go.
//
// n is clamped to the membership. Asking for more replicas than there are
// nodes is a caller's miscount and padding the list with repeats would turn it
// into one that looks like it has n distinct homes and does not.
func (r *Ring) GetN(key string, n int) []string {
	if n < 1 || len(r.st.points) == 0 {
		return nil
	}
	if n > len(r.st.nodes) {
		n = len(r.st.nodes)
	}

	out := make([]string, 0, n)
	seen := make(map[string]bool, n)
	start := r.search(Hash(key))
	for i := 0; i < len(r.st.points) && len(out) < n; i++ {
		node := r.st.points[(start+i)%len(r.st.points)].Node
		if seen[node] {
			continue
		}
		seen[node] = true
		out = append(out, node)
	}
	return out
}

// owner resolves an already-hashed key. Split out from Get so the wrap-around
// case can be tested at a hash the test chose rather than at whatever string
// happens to hash past the last point.
func (r *Ring) owner(h uint64) string {
	if len(r.st.points) == 0 {
		return ""
	}
	return r.st.points[r.search(h)].Node
}

// search returns the index of the first point at or clockwise of h, wrapping
// to 0 when h is past the last point. That wrap is the only place the circle
// is a circle rather than a sorted slice.
func (r *Ring) search(h uint64) int {
	i := sort.Search(len(r.st.points), func(i int) bool { return r.st.points[i].Hash >= h })
	if i == len(r.st.points) {
		return 0
	}
	return i
}

// mergePoints merges two circles, each ordered by Hash, into a fresh one that
// is strictly increasing. Where both hold a point at the same position only
// one survives: two points at one position would make the arc between them
// empty, so the loser of a collision owns nothing and is only a slower binary
// search.
//
// The winner is the point whose node name sorts first, never the one that was
// there first. Keeping the incumbent would make the ring depend on the order
// the membership arrived in, which is a ring two chains with the same
// membership disagree about. At 64-bit hashes and a 131,072-point ceiling the
// odds of ever seeing a collision are about 2^-31, which is why the rule has
// to be right without real data ever exercising it.
func mergePoints(a, b []Point) []Point {
	out := make([]Point, 0, len(a)+len(b))
	i, j := 0, 0
	for i < len(a) || j < len(b) {
		var p Point
		switch {
		case j == len(b):
			p, i = a[i], i+1
		case i == len(a):
			p, j = b[j], j+1
		case a[i].Hash < b[j].Hash:
			p, i = a[i], i+1
		case a[i].Hash > b[j].Hash:
			p, j = b[j], j+1
		default:
			p = a[i]
			if b[j].Node < p.Node {
				p = b[j]
			}
			i, j = i+1, j+1
		}
		if n := len(out); n > 0 && out[n-1].Hash == p.Hash {
			// A collision inside one side, a node against its own points:
			// byPosition already put the winner first.
			continue
		}
		out = append(out, p)
	}
	return out
}

// byPosition orders points by Hash, then by Node, so that among points at one
// position the collision winner comes first.
type byPosition []Point

func (s byPosition) Len() int      { return len(s) }
func (s byPosition) Swap(i, j int) { s[i], s[j] = s[j], s[i] }
func (s byPosition) Less(i, j int) bool {
	if s[i].Hash != s[j].Hash {
		return s[i].Hash < s[j].Hash
	}
	return s[i].Node < s[j].Node
}

// pointHash is where a node's v-th virtual point lands. The separator keeps
// "node#1" + "1" and "node#" + "11" apart, which a plain concatenation of a
// node name ending in a digit would not.
func pointHash(node string, v int) uint64 {
	return Hash(node + "#" + strconv.Itoa(v))
}

// Hash maps a string onto the circle: SHA-256, first eight bytes, big-endian.
//
// It is part of this package's API and not an implementation detail. Every
// placement a caller has ever made is a function of it, so changing it is not
// a refactor, it is a migration of everything that was ever stored by the
// result.
func Hash(s string) uint64 {
	sum := sha256.Sum256([]byte(s))
	var h uint64
	for i := 0; i < 8; i++ {
		h = h<<8 | uint64(sum[i])
	}
	return h
}
