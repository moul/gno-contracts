package hashring

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// keys is the fixed workload every placement test maps. Fixed, because the
// claim under test is about which keys MOVE, and a workload that changed
// between the two halves of that comparison would prove nothing.
func keys(n int) []string {
	out := make([]string, 0, n)
	for i := 0; i < n; i++ {
		out = append(out, "key-"+strconv.Itoa(i))
	}
	return out
}

// place maps every key and returns the owner slice, aligned with keys(n).
func place(r *Ring, ks []string) []string {
	out := make([]string, 0, len(ks))
	for _, k := range ks {
		out = append(out, r.Get(k))
	}
	return out
}

// moved counts the positions where two placements disagree.
func moved(before, after []string) int {
	n := 0
	for i := range before {
		if before[i] != after[i] {
			n++
		}
	}
	return n
}

// TestRemoveMovesOnlyTheDepartedNodesKeys is the property the whole structure
// exists for, and the one a modulo shard fails: taking a node out of the ring
// remaps the keys that node owned, and not one key more.
func TestRemoveMovesOnlyTheDepartedNodesKeys(t *testing.T) {
	ks := keys(2000)

	r := New(DefaultReplicas)
	for _, n := range []string{"alpha", "beta", "gamma", "delta"} {
		r.Add(n)
	}
	before := place(r, ks)

	r.Remove("gamma")
	after := place(r, ks)

	for i, k := range ks {
		if before[i] == "gamma" {
			uassert.NotEqual(t, "gamma", after[i], "key "+k+" still owned by a removed node")
			continue
		}
		uassert.Equal(t, before[i], after[i], "key "+k+" moved although its owner stayed")
	}

	// And the keys that did move are exactly gamma's, which is the number a
	// modulo shard would have to beat.
	lost := 0
	for i := range ks {
		if before[i] == "gamma" {
			lost++
		}
	}
	uassert.Equal(t, lost, moved(before, after), "more keys moved than the departed node owned")
	uassert.True(t, lost > 0, "the fixture never placed a key on the node under test")
}

// TestAddMovesOnlyOntoTheNewNode is the same property on the way in: a node
// joining steals keys for itself and never shuffles two incumbents.
func TestAddMovesOnlyOntoTheNewNode(t *testing.T) {
	ks := keys(2000)

	r := New(DefaultReplicas)
	for _, n := range []string{"alpha", "beta", "gamma"} {
		r.Add(n)
	}
	before := place(r, ks)

	r.Add("delta")
	after := place(r, ks)

	gained := 0
	for i := range ks {
		if before[i] == after[i] {
			continue
		}
		uassert.Equal(t, "delta", after[i], "a key moved between two incumbent nodes")
		gained++
	}
	uassert.True(t, gained > 0, "the new node took no keys at all")
}

// TestPlacementIsIndependentOfInsertionOrder pins determinism: two chains
// agreeing on the membership set must agree on every placement, whatever order
// the membership arrived in. A ring that sorted nothing would pass Get and
// fail here.
func TestPlacementIsIndependentOfInsertionOrder(t *testing.T) {
	ks := keys(500)

	a := New(DefaultReplicas)
	for _, n := range []string{"alpha", "beta", "gamma", "delta"} {
		a.Add(n)
	}

	b := New(DefaultReplicas)
	for _, n := range []string{"delta", "gamma", "beta", "alpha"} {
		b.Add(n)
	}

	uassert.Equal(t, strings.Join(a.Nodes(), ","), strings.Join(b.Nodes(), ","))
	uassert.Equal(t, 0, moved(place(a, ks), place(b, ks)), "insertion order changed a placement")
}

// TestEmptyRing: an empty ring owns nothing and says so, rather than dividing
// by zero somewhere inside.
func TestEmptyRing(t *testing.T) {
	r := New(DefaultReplicas)
	uassert.Equal(t, "", r.Get("anything"))
	uassert.Equal(t, 0, len(r.GetN("anything", 3)))
	uassert.Equal(t, 0, r.Len())
	uassert.Equal(t, 0, len(r.Nodes()))
	uassert.False(t, r.Has("alpha"))
}

func TestAddRemoveBookkeeping(t *testing.T) {
	r := New(8)

	uassert.True(t, r.Add("alpha"), "first Add reported no change")
	uassert.False(t, r.Add("alpha"), "duplicate Add reported a change")
	uassert.Equal(t, 8, r.Len())
	uassert.True(t, r.Has("alpha"))

	uassert.True(t, r.Add("beta"))
	uassert.Equal(t, 16, r.Len())
	uassert.Equal(t, "alpha,beta", strings.Join(r.Nodes(), ","))

	uassert.True(t, r.Remove("alpha"), "Remove of a member reported no change")
	uassert.False(t, r.Remove("alpha"), "Remove of a non-member reported a change")
	uassert.Equal(t, 8, r.Len())
	uassert.Equal(t, "beta", strings.Join(r.Nodes(), ","))

	uassert.True(t, r.Remove("beta"))
	uassert.Equal(t, 0, r.Len())
	uassert.Equal(t, "", r.Get("anything"), "ring emptied by Remove still names an owner")
}

// TestGetNIsDistinctAndOrdered: the replica list walks the ring forward from
// the key and never repeats a node, which is what makes it usable as a
// preference list.
func TestGetNIsDistinctAndOrdered(t *testing.T) {
	r := New(DefaultReplicas)
	for _, n := range []string{"alpha", "beta", "gamma", "delta", "epsilon"} {
		r.Add(n)
	}

	for _, k := range keys(200) {
		got := r.GetN(k, 3)
		uassert.Equal(t, 3, len(got), "GetN returned the wrong count for "+k)
		uassert.Equal(t, r.Get(k), got[0], "GetN's head disagrees with Get for "+k)

		seen := map[string]bool{}
		for _, n := range got {
			uassert.False(t, seen[n], "GetN repeated "+n+" for "+k)
			seen[n] = true
		}
	}

	// n beyond the membership clamps to the membership rather than padding or
	// looping: asking for more replicas than there are nodes is a caller's
	// miscount, not a reason to hand back the same node twice.
	uassert.Equal(t, 5, len(r.GetN("key-0", 99)))
	uassert.Equal(t, 0, len(r.GetN("key-0", 0)))
	uassert.Equal(t, 0, len(r.GetN("key-0", -1)))
}

// TestVirtualNodesSpreadTheLoad is why DefaultReplicas is not 1. With one
// point per node the ring is four random cuts of the key space, and on this
// fixture the largest share beats the smallest by 380 points of an even
// split; 64 points per node brings that to 37.
//
// Both numbers are exact, not sampled: the hash is fixed and so is the
// workload, so this test is deterministic. The assertions keep headroom
// anyway, because what is being pinned is the falloff and not the digits.
func TestVirtualNodesSpreadTheLoad(t *testing.T) {
	ks := keys(6000)
	nodes := []string{"alpha", "beta", "gamma", "delta"}

	spread := func(replicas int) int {
		r := New(replicas)
		for _, n := range nodes {
			r.Add(n)
		}
		counts := map[string]int{}
		for _, k := range ks {
			counts[r.Get(k)]++
		}
		lo, hi := len(ks)+1, 0
		for _, n := range nodes {
			c := counts[n]
			if c < lo {
				lo = c
			}
			if c > hi {
				hi = c
			}
		}
		// Percentage points of imbalance: 0 is a perfect split.
		return (hi - lo) * 100 / (len(ks) / len(nodes))
	}

	one := spread(1)
	many := spread(DefaultReplicas)
	// No percent sign in a uassert message: the message is concatenated into
	// a format string, so a stray verb would mangle the failure text.
	uassert.True(t, many < 50, "64 replicas still left "+strconv.Itoa(many)+" points of imbalance")
	uassert.True(t, many*5 < one, "virtual nodes barely improved on a single point per node")
}

// TestNewClampsReplicas: the bound is the structure's, not the caller's. A
// ring is sized at construction and a caller cannot be handed one whose point
// count it did not choose.
func TestNewClampsReplicas(t *testing.T) {
	uassert.Equal(t, 1, New(0).Replicas())
	uassert.Equal(t, 1, New(-7).Replicas())
	uassert.Equal(t, MaxReplicas, New(MaxReplicas+1).Replicas())
	uassert.Equal(t, 64, New(64).Replicas())
}

// TestMaxNodes: the ring refuses to grow past its bound instead of accepting
// the node and quietly costing every later Get a deeper search.
func TestMaxNodes(t *testing.T) {
	r := New(1)
	for i := 0; i < MaxNodes; i++ {
		uassert.True(t, r.Add("node-"+strconv.Itoa(i)), "Add refused below MaxNodes")
	}
	uassert.Equal(t, MaxNodes, len(r.Nodes()))
	uassert.False(t, r.Add("one-too-many"), "Add accepted a node past MaxNodes")
	uassert.False(t, r.Has("one-too-many"))
}

// TestHashIsStable pins the hash itself. Every placement above is relative,
// so a changed hash function would keep them all green while silently moving
// every key on every chain that had already deployed this package.
func TestHashIsStable(t *testing.T) {
	cases := []struct {
		in   string
		want uint64
	}{
		{"", 0xe3b0c44298fc1c14}, // the first 8 bytes of SHA-256 of nothing
		{"alpha", 0x8ed3f6ad685b959e},
		{"key-0", 0xd5ead6fdd3d16630},
	}
	for _, tc := range cases {
		uassert.Equal(t, strconv.FormatUint(tc.want, 16), strconv.FormatUint(Hash(tc.in), 16), "hash of "+tc.in)
	}
}

// TestPointsAreSortedAndOwned exposes enough of the internals for the demo to
// draw the ring, and pins the invariant that makes Get a binary search.
func TestPointsAreSortedAndOwned(t *testing.T) {
	r := New(4)
	r.Add("alpha")
	r.Add("beta")

	pts := r.Points()
	uassert.Equal(t, 8, len(pts))
	for i := 1; i < len(pts); i++ {
		uassert.True(t, pts[i-1].Hash < pts[i].Hash, "ring points are not strictly increasing")
	}
	for _, p := range pts {
		uassert.True(t, p.Node == "alpha" || p.Node == "beta", "a point names an unknown node")
	}

	// Points is a copy: handing a caller the live ring would let it reorder
	// the slice Get binary-searches.
	pts[0].Hash = 0
	uassert.True(t, r.Points()[0].Hash != 0, "Points handed out the live slice")
}

// TestWrapAround: a key hashing past the last point belongs to the first, or
// the ring is an arc and not a ring.
func TestWrapAround(t *testing.T) {
	r := New(2)
	r.Add("alpha")
	r.Add("beta")

	pts := r.Points()
	first, last := pts[0], pts[len(pts)-1]
	uassert.True(t, last.Hash > first.Hash, "fixture is not ordered")

	uassert.Equal(t, first.Node, r.owner(last.Hash+1), "a key past the last point did not wrap")
	uassert.Equal(t, first.Node, r.owner(^uint64(0)), "the largest possible hash did not wrap")
	uassert.Equal(t, first.Node, r.owner(first.Hash), "a key landing exactly on a point missed its owner")
}
