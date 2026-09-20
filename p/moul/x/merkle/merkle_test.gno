package merkle

import (
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"testing"
)

// leaves returns n deterministic leaves, "leaf-0" … "leaf-n-1". The golden
// vectors below were produced from these exact inputs by tm2's own
// merkle.SimpleProofsFromByteSlices, so a mismatch means this package has
// diverged from Tendermint, not that the expectation is stale.
func leaves(n int) [][]byte {
	out := make([][]byte, n)
	for i := 0; i < n; i++ {
		out[i] = []byte("leaf-" + strconv.Itoa(i))
	}
	return out
}

var goldenRoots = map[int]string{
	1: "305df59f9590c3c9ac63d2b2743c388e3792449078cebf7fb3dbe6471643b2b7",
	2: "60a53eed0de87a90c8e59427c59c46253c33a76a09502a51801300927b7e6bdc",
	3: "cf763a041c81ceef1578a6083f75c61bef2e0014f2a3e683a97fcfca5be7f19a",
	4: "bdd1c5ff55b19cb6b0e7c761bf9a6ccaa27fbbfc07b74f1fabb6e911a0bd2ab3",
	5: "00d21829a5503145348abcf712513eacf2a274211ad83e970202bb5b6d80b286",
	7: "0b007fb915eb9b2a146f54b1c86ec53b664f8e455b7660b0b6ee13edc0d921c0",
}

// goldenAunts[n][i] is the comma-separated hex sibling list tm2 produces for
// leaf i of an n-leaf tree.
var goldenAunts = map[int][]string{
	1: {""},
	2: {
		"3145c409f259b7c53e32036090ff76751025a2498ba9823ef718cac50b4e616f",
		"305df59f9590c3c9ac63d2b2743c388e3792449078cebf7fb3dbe6471643b2b7",
	},
	3: {
		"3145c409f259b7c53e32036090ff76751025a2498ba9823ef718cac50b4e616f,fca89f57c9f8c8eb4047a7ff9d333acf9e0f3384b20b255bceab0f216dcca267",
		"305df59f9590c3c9ac63d2b2743c388e3792449078cebf7fb3dbe6471643b2b7,fca89f57c9f8c8eb4047a7ff9d333acf9e0f3384b20b255bceab0f216dcca267",
		"60a53eed0de87a90c8e59427c59c46253c33a76a09502a51801300927b7e6bdc",
	},
	4: {
		"3145c409f259b7c53e32036090ff76751025a2498ba9823ef718cac50b4e616f,bd45ff28796704d88bdac51b1df553fda59837b616d6d1cb2114dbc3b087ff69",
		"305df59f9590c3c9ac63d2b2743c388e3792449078cebf7fb3dbe6471643b2b7,bd45ff28796704d88bdac51b1df553fda59837b616d6d1cb2114dbc3b087ff69",
		"f76836325aec5699d8d71f8e42e9d47c5c29b08059ba296384f7ca40ad3a40ae,60a53eed0de87a90c8e59427c59c46253c33a76a09502a51801300927b7e6bdc",
		"fca89f57c9f8c8eb4047a7ff9d333acf9e0f3384b20b255bceab0f216dcca267,60a53eed0de87a90c8e59427c59c46253c33a76a09502a51801300927b7e6bdc",
	},
	7: {
		"3145c409f259b7c53e32036090ff76751025a2498ba9823ef718cac50b4e616f,bd45ff28796704d88bdac51b1df553fda59837b616d6d1cb2114dbc3b087ff69,8eae6bd3b3a07f1f75ee72a531629e6eb31e42e62f760e47de52a53c3641ef23",
		"305df59f9590c3c9ac63d2b2743c388e3792449078cebf7fb3dbe6471643b2b7,bd45ff28796704d88bdac51b1df553fda59837b616d6d1cb2114dbc3b087ff69,8eae6bd3b3a07f1f75ee72a531629e6eb31e42e62f760e47de52a53c3641ef23",
		"f76836325aec5699d8d71f8e42e9d47c5c29b08059ba296384f7ca40ad3a40ae,60a53eed0de87a90c8e59427c59c46253c33a76a09502a51801300927b7e6bdc,8eae6bd3b3a07f1f75ee72a531629e6eb31e42e62f760e47de52a53c3641ef23",
		"fca89f57c9f8c8eb4047a7ff9d333acf9e0f3384b20b255bceab0f216dcca267,60a53eed0de87a90c8e59427c59c46253c33a76a09502a51801300927b7e6bdc,8eae6bd3b3a07f1f75ee72a531629e6eb31e42e62f760e47de52a53c3641ef23",
		"8f1593cb92f429d9340b9bbc1f0bb122adf8026c42a4a42142e2168931727236,676f3782f5b3a5fb4370ed49572cedc523f4a66322269c85f2af0509d17b0a4d,bdd1c5ff55b19cb6b0e7c761bf9a6ccaa27fbbfc07b74f1fabb6e911a0bd2ab3",
		"ea9fc1a1b6e191b460d0d6306e3e870c173f39330f13cda1b70cfc72bdc398ba,676f3782f5b3a5fb4370ed49572cedc523f4a66322269c85f2af0509d17b0a4d,bdd1c5ff55b19cb6b0e7c761bf9a6ccaa27fbbfc07b74f1fabb6e911a0bd2ab3",
		"985bb5d36b927800876871da925a7e82abe83a9ddba5882920a007a55ea2b376,bdd1c5ff55b19cb6b0e7c761bf9a6ccaa27fbbfc07b74f1fabb6e911a0bd2ab3",
	},
}

func TestRootMatchesTendermint(t *testing.T) {
	for _, n := range []int{1, 2, 3, 4, 5, 7} {
		got := New(leaves(n)).RootHex()
		if got != goldenRoots[n] {
			t.Errorf("n=%d: root = %s, tm2 says %s", n, got, goldenRoots[n])
		}
	}
}

func TestProofMatchesTendermint(t *testing.T) {
	for n, want := range goldenAunts {
		tree := New(leaves(n))
		for i, w := range want {
			p, err := tree.Proof(i)
			if err != nil {
				t.Fatalf("n=%d i=%d: Proof: %v", n, i, err)
			}
			if got := p.Hex(); got != w {
				t.Errorf("n=%d i=%d:\n got  %s\n want %s", n, i, got, w)
			}
		}
	}
}

// Every leaf of every tree shape up to 33 must produce a proof the native
// verifier accepts. This is the property that matters; the golden vectors only
// pin the encoding.
func TestEveryProofVerifies(t *testing.T) {
	for n := 1; n <= 33; n++ {
		ls := leaves(n)
		tree := New(ls)
		root := tree.Root()
		for i := 0; i < n; i++ {
			p, err := tree.Proof(i)
			if err != nil {
				t.Fatalf("n=%d i=%d: Proof: %v", n, i, err)
			}
			if !p.Verify(root, ls[i]) {
				t.Errorf("n=%d i=%d: valid proof rejected", n, i)
			}
		}
	}
}

func TestRejects(t *testing.T) {
	ls := leaves(8)
	tree := New(ls)
	root := tree.Root()
	p0, _ := tree.Proof(0)
	p1, _ := tree.Proof(1)

	tests := []struct {
		name  string
		proof Proof
		root  []byte
		leaf  []byte
	}{
		{"forged leaf", p0, root, []byte("not-a-leaf")},
		{"another real leaf at the wrong index", p0, root, ls[1]},
		{"proof replayed at a different index", Proof{Index: 1, Total: p0.Total, Siblings: p0.Siblings}, root, ls[1]},
		{"sibling list of another leaf", Proof{Index: 0, Total: 8, Siblings: p1.Siblings}, root, ls[0]},
		{"wrong root", p0, LeafHash([]byte("nope")), ls[0]},
		{"index beyond total", Proof{Index: 8, Total: 8, Siblings: p0.Siblings}, root, ls[0]},
		{"negative index", Proof{Index: -1, Total: 8, Siblings: p0.Siblings}, root, ls[0]},
		{"zero total", Proof{Index: 0, Total: 0, Siblings: p0.Siblings}, root, ls[0]},
		{"truncated proof", Proof{Index: 0, Total: 8, Siblings: p0.Siblings[:1]}, root, ls[0]},
		{"short root", p0, root[:31], ls[0]},
	}
	for _, tc := range tests {
		if tc.proof.Verify(tc.root, tc.leaf) {
			t.Errorf("%s: accepted, must be rejected", tc.name)
		}
	}
}

func TestMaxDepthCap(t *testing.T) {
	sibs := make([][]byte, MaxDepth+1)
	for i := range sibs {
		sibs[i] = make([]byte, HashSize)
	}
	p := Proof{Index: 0, Total: 1 << 20, Siblings: sibs}
	if p.Verify(make([]byte, HashSize), []byte("x")) {
		t.Error("proof deeper than MaxDepth accepted")
	}
	if !VerifySorted(make([]byte, HashSize), make([]byte, HashSize), sibs[:MaxDepth]) == false {
		t.Error("unreachable")
	}
	if VerifySorted(make([]byte, HashSize), make([]byte, HashSize), sibs) {
		t.Error("sorted proof deeper than MaxDepth accepted")
	}
}

func TestParseProofRoundTrip(t *testing.T) {
	tree := New(leaves(7))
	for i := 0; i < 7; i++ {
		want, _ := tree.Proof(i)
		got, err := ParseProof(i, 7, want.Hex())
		if err != nil {
			t.Fatalf("i=%d: ParseProof: %v", i, err)
		}
		if got.Hex() != want.Hex() || got.Index != want.Index || got.Total != want.Total {
			t.Errorf("i=%d: round trip lost data", i)
		}
		if !got.Verify(tree.Root(), []byte("leaf-"+strconv.Itoa(i))) {
			t.Errorf("i=%d: reparsed proof does not verify", i)
		}
	}
}

func TestParseProofErrors(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want error
	}{
		{"not hex", "zz", ErrBadHex},
		{"wrong size", "abcd", ErrBadHashSize},
		{"too deep", tooDeepHex(), ErrProofTooDeep},
	}
	for _, tc := range tests {
		if _, err := ParseProof(0, 2, tc.in); err != tc.want {
			t.Errorf("%s: err = %v, want %v", tc.name, err, tc.want)
		}
	}
	// An empty sibling list is the one-leaf proof, not an error.
	p, err := ParseProof(0, 1, "  ")
	if err != nil {
		t.Fatalf("empty siblings: %v", err)
	}
	one := New(leaves(1))
	if !p.Verify(one.Root(), []byte("leaf-0")) {
		t.Error("one-leaf proof with no siblings rejected")
	}
}

func tooDeepHex() string {
	h := hex.EncodeToString(make([]byte, HashSize))
	out := h
	for i := 0; i < MaxDepth; i++ {
		out += "," + h
	}
	return out
}

func TestTreeErrors(t *testing.T) {
	if _, err := New(nil).Proof(0); err != ErrEmptyTree {
		t.Errorf("empty tree: err = %v, want %v", err, ErrEmptyTree)
	}
	if New(nil).Root() != nil {
		t.Error("empty tree root should be nil, like Tendermint")
	}
	tree := New(leaves(3))
	for _, i := range []int{-1, 3, 99} {
		if _, err := tree.Proof(i); err != ErrIndexRange {
			t.Errorf("index %d: err = %v, want %v", i, err, ErrIndexRange)
		}
	}
}

// New must copy its input: a caller mutating the slice afterwards cannot be
// allowed to change what the tree committed to.
func TestNewCopiesLeaves(t *testing.T) {
	ls := [][]byte{[]byte("a"), []byte("b")}
	tree := New(ls)
	before := tree.RootHex()
	ls[0][0] = 'z'
	if tree.RootHex() != before {
		t.Error("mutating the caller's slice changed the committed root")
	}
}

// The reason this package exists. In a scheme without domain separation an
// INNER NODE hash is also a valid LEAF hash, so anyone who can choose a
// 64-byte leaf preimage can prove membership of a leaf that was never in the
// tree. This test performs that forgery against VerifySorted, then shows the
// Tendermint scheme refuses the same move.
func TestSecondPreimageForgery(t *testing.T) {
	// A 4-leaf commutative tree, built the OpenZeppelin way.
	h := make([][]byte, 4)
	for i := range h {
		s := sha256.Sum256([]byte("leaf-" + strconv.Itoa(i)))
		h[i] = s[:]
	}
	n01 := hashSortedPair(h[0], h[1])
	n23 := hashSortedPair(h[2], h[3])
	root := hashSortedPair(n01, n23)

	// Sanity: a real leaf really does verify.
	if !VerifySorted(root, h[0], [][]byte{h[1], n23}) {
		t.Fatal("honest sorted proof rejected")
	}

	// The forgery: present the inner node n01 as if it were a leaf hash. Its
	// preimage is the 64 bytes sorted(h0, h1), so an application whose leaves
	// can be 64 bytes long hands the attacker a membership proof for data that
	// was never committed.
	if !VerifySorted(root, n01, [][]byte{n23}) {
		t.Fatal("expected the second-preimage forgery to succeed against VerifySorted")
	}

	// Same shape, Tendermint scheme. Leaves are tagged 0x00 and inner nodes
	// 0x01, so no leaf preimage can ever hash to an inner node, and the proof
	// is bound to an index besides.
	tree := New(leaves(4))
	inner := InnerHash(LeafHash(tree.leaves[0]), LeafHash(tree.leaves[1]))
	forged := Proof{Index: 0, Total: 2, Siblings: [][]byte{InnerHash(LeafHash(tree.leaves[2]), LeafHash(tree.leaves[3]))}}
	if forged.Verify(tree.Root(), inner) {
		t.Error("domain separation failed: an inner node was accepted as a leaf")
	}
}

func TestLeafAndInnerHashAreTagged(t *testing.T) {
	leafOfEmpty := LeafHash(nil)
	taggedLeaf := sha256.Sum256([]byte{0x00})
	if hex.EncodeToString(leafOfEmpty) != hex.EncodeToString(taggedLeaf[:]) {
		t.Error("LeafHash is not SHA256(0x00 || leaf)")
	}
	l := make([]byte, 32)
	r := make([]byte, 32)
	r[0] = 1
	got := InnerHash(l, r)
	want := sha256.Sum256(append(append([]byte{0x01}, l...), r...))
	if hex.EncodeToString(got) != hex.EncodeToString(want[:]) {
		t.Error("InnerHash is not SHA256(0x01 || left || right)")
	}
}

func TestSplitPointMatchesTendermint(t *testing.T) {
	// largest power of two strictly below length
	tests := []struct{ in, want int }{
		{2, 1}, {3, 2}, {4, 2}, {5, 4}, {7, 4}, {8, 4}, {9, 8}, {16, 8}, {17, 16},
	}
	for _, tc := range tests {
		if got := splitPoint(tc.in); got != tc.want {
			t.Errorf("splitPoint(%d) = %d, want %d", tc.in, got, tc.want)
		}
	}
}
