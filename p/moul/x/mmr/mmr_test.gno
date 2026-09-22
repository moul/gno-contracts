package mmr

import (
	"strconv"
	"testing"

	"gno.land/p/moul/x/merkle/v0"
)

func leafAt(i int) []byte { return []byte("entry-" + strconv.Itoa(i)) }

func build(n int) *MMR {
	m := New()
	for i := 0; i < n; i++ {
		if got := m.Append(leafAt(i)); got != i {
			panic("Append returned the wrong index")
		}
	}
	return m
}

// The property that matters: for every log size up to 40, every leaf ever
// appended has a proof that verifies against the root at that size.
func TestEveryProofVerifies(t *testing.T) {
	for n := 1; n <= 40; n++ {
		m := build(n)
		root := m.Root()
		for i := 0; i < n; i++ {
			p, err := m.Proof(i)
			if err != nil {
				t.Fatalf("n=%d i=%d: Proof: %v", n, i, err)
			}
			if !Verify(root, leafAt(i), p) {
				t.Errorf("n=%d i=%d: valid proof rejected", n, i)
			}
		}
	}
}

// A one-leaf MMR is a single height-0 mountain, so its root is just the
// tagged leaf hash and the proof is empty.
func TestSingleLeaf(t *testing.T) {
	m := build(1)
	if string(m.Root()) != string(merkle.LeafHash(leafAt(0))) {
		t.Error("one-leaf root is not the leaf hash")
	}
	p, err := m.Proof(0)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Path) != 0 || len(p.Before) != 0 || len(p.After) != 0 {
		t.Error("one-leaf proof should be empty")
	}
}

// The Tendermint simple tree and a right-bagged MMR are the SAME tree, at
// every size and not only at powers of two. Tendermint splits an n-leaf tree
// at the largest power of two below n: that left half is exactly the first
// mountain, and the right half recurses into the remaining set bits, which is
// exactly the bagging. So an MMR is a drop-in incremental builder for
// Tendermint roots: append in O(log n) on chain, hand out a root any
// Tendermint verifier accepts.
func TestRootMatchesTendermintTreeAtEverySize(t *testing.T) {
	for n := 1; n <= 40; n++ {
		ls := make([][]byte, n)
		for i := range ls {
			ls[i] = leafAt(i)
		}
		if got, want := build(n).RootHex(), merkle.New(ls).RootHex(); got != want {
			t.Errorf("n=%d: MMR root %s, Tendermint tree root %s", n, got, want)
		}
	}
}

// The consequence of the equality above: a proof produced by the fixed-list
// Tendermint tree verifies against the root an MMR maintained incrementally,
// and both packages agree leaf by leaf.
func TestMerkleProofVerifiesAgainstMMRRoot(t *testing.T) {
	for _, n := range []int{1, 2, 3, 5, 7, 11, 16, 23} {
		ls := make([][]byte, n)
		for i := range ls {
			ls[i] = leafAt(i)
		}
		m := build(n)
		tree := merkle.New(ls)
		for i := 0; i < n; i++ {
			tp, err := tree.Proof(i)
			if err != nil {
				t.Fatalf("n=%d i=%d: %v", n, i, err)
			}
			if !tp.Verify(m.Root(), leafAt(i)) {
				t.Errorf("n=%d i=%d: Tendermint proof rejected by the MMR root", n, i)
			}
			mp, err := m.Proof(i)
			if err != nil {
				t.Fatalf("n=%d i=%d: %v", n, i, err)
			}
			if !Verify(tree.Root(), leafAt(i), mp) {
				t.Errorf("n=%d i=%d: MMR proof rejected by the tree root", n, i)
			}
		}
	}
}

func TestPeakStructure(t *testing.T) {
	tests := []struct {
		leaves int
		want   []int
	}{
		{1, []int{0}},
		{2, []int{1}},
		{3, []int{1, 0}},
		{4, []int{2}},
		{7, []int{2, 1, 0}},
		{11, []int{3, 1, 0}},
		{16, []int{4}},
	}
	for _, tc := range tests {
		if got := len(peakHeights(tc.leaves)); got != len(tc.want) {
			t.Errorf("n=%d: %d peaks, want %d", tc.leaves, got, len(tc.want))
			continue
		}
		for i, h := range peakHeights(tc.leaves) {
			if h != tc.want[i] {
				t.Errorf("n=%d: peak %d height %d, want %d", tc.leaves, i, h, tc.want[i])
			}
		}
		if got := len(build(tc.leaves).peaks); got != len(tc.want) {
			t.Errorf("n=%d: MMR built %d peaks, want %d", tc.leaves, got, len(tc.want))
		}
	}
}

func TestRejects(t *testing.T) {
	m := build(11)
	root := m.Root()
	p3, _ := m.Proof(3)
	p7, _ := m.Proof(7)

	tests := []struct {
		name  string
		root  []byte
		leaf  []byte
		proof Proof
	}{
		{"forged leaf", root, []byte("never-appended"), p3},
		{"another real leaf", root, leafAt(4), p3},
		{"proof replayed at another index", root, leafAt(3), Proof{Index: 4, Total: p3.Total, Path: p3.Path, Before: p3.Before, After: p3.After}},
		{"another leaf's proof", root, leafAt(3), p7},
		{"wrong total", root, leafAt(3), Proof{Index: 3, Total: 10, Path: p3.Path, Before: p3.Before, After: p3.After}},
		{"padded path", root, leafAt(3), Proof{Index: 3, Total: 11, Path: append(append([][]byte{}, p3.Path...), make([]byte, HashSize)), Before: p3.Before, After: p3.After}},
		{"truncated path", root, leafAt(3), Proof{Index: 3, Total: 11, Path: p3.Path[:len(p3.Path)-1], Before: p3.Before, After: p3.After}},
		{"peaks swapped", root, leafAt(3), Proof{Index: 3, Total: 11, Path: p3.Path, Before: p3.After, After: p3.Before}},
		{"index beyond total", root, leafAt(3), Proof{Index: 11, Total: 11, Path: p3.Path, Before: p3.Before, After: p3.After}},
		{"negative index", root, leafAt(3), Proof{Index: -1, Total: 11, Path: p3.Path, Before: p3.Before, After: p3.After}},
		{"zero total", root, leafAt(3), Proof{Index: 0, Total: 0}},
		{"short root", root[:31], leafAt(3), p3},
		{"short hash in path", root, leafAt(3), Proof{Index: 3, Total: 11, Path: [][]byte{{1, 2, 3}, p3.Path[1]}, Before: p3.Before, After: p3.After}},
	}
	for _, tc := range tests {
		if Verify(tc.root, tc.leaf, tc.proof) {
			t.Errorf("%s: accepted, must be rejected", tc.name)
		}
	}
}

// A proof is issued against one size. Appending moves the root, and the old
// proof must stop verifying against the new one rather than quietly pass.
func TestProofIsBoundToItsSize(t *testing.T) {
	m := build(5)
	old, _ := m.Proof(2)
	oldRoot := m.Root()
	if !Verify(oldRoot, leafAt(2), old) {
		t.Fatal("proof does not verify against its own root")
	}
	m.Append(leafAt(5))
	if Verify(m.Root(), leafAt(2), old) {
		t.Error("a stale proof verified against the new root")
	}
	fresh, _ := m.Proof(2)
	if !Verify(m.Root(), leafAt(2), fresh) {
		t.Error("a reissued proof does not verify")
	}
	if !Verify(oldRoot, leafAt(2), old) {
		t.Error("the old proof stopped verifying against the old root")
	}
}

func TestEmptyAndRange(t *testing.T) {
	m := New()
	if m.Size() != 0 || m.Root() != nil || m.Nodes() != 0 {
		t.Error("a fresh MMR is not empty")
	}
	if _, err := m.Proof(0); err != ErrEmpty {
		t.Errorf("empty Proof: err = %v, want %v", err, ErrEmpty)
	}
	m.Append(leafAt(0))
	for _, i := range []int{-1, 1, 99} {
		if _, err := m.Proof(i); err != ErrIndexRange {
			t.Errorf("index %d: err = %v, want %v", i, err, ErrIndexRange)
		}
	}
}

// Storage claim from the package doc: 2n - popcount(n) stored hashes.
func TestNodeCount(t *testing.T) {
	for n := 1; n <= 40; n++ {
		want := 2*n - popcount(n)
		if got := build(n).Nodes(); got != want {
			t.Errorf("n=%d: %d nodes, want 2n-popcount(n) = %d", n, got, want)
		}
	}
}

func popcount(n int) int {
	c := 0
	for n != 0 {
		c += n & 1
		n >>= 1
	}
	return c
}

func TestParseProofRoundTrip(t *testing.T) {
	m := build(11)
	for i := 0; i < 11; i++ {
		want, _ := m.Proof(i)
		path, before, after := want.Hex()
		got, err := ParseProof(i, 11, path, before, after)
		if err != nil {
			t.Fatalf("i=%d: ParseProof: %v", i, err)
		}
		if !Verify(m.Root(), leafAt(i), got) {
			t.Errorf("i=%d: reparsed proof does not verify", i)
		}
	}
}

func TestParseProofErrors(t *testing.T) {
	if _, err := ParseProof(0, 2, "zz", "", ""); err != ErrBadHex {
		t.Errorf("bad hex: err = %v", err)
	}
	if _, err := ParseProof(0, 2, "abcd", "", ""); err != ErrBadSize {
		t.Errorf("bad size: err = %v", err)
	}
}

// PeakHashes is the whole verifier-side state, and it must stay logarithmic.
func TestPeakCountIsLogarithmic(t *testing.T) {
	m := build(1023)
	if got := len(m.PeakHashes()); got != 10 {
		t.Errorf("1023 leaves: %d peaks, want 10", got)
	}
	if got := len(build(1024).PeakHashes()); got != 1 {
		t.Errorf("1024 leaves: %d peaks, want 1", got)
	}
}
