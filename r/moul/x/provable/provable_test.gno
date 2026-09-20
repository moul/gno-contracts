package provable

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/moul/x/merkle/v0"
)

func TestAppendAndVerify(cur realm, t *testing.T) {
	seed()
	i := Append(cross(cur), "a fourth commitment")
	if i != 3 || Size() != 4 {
		t.Fatalf("Append returned %d with Size %d, want 3 and 4", i, Size())
	}
	if Entry(i) != "a fourth commitment" {
		t.Errorf("Entry(%d) = %q", i, Entry(i))
	}

	root := Root()
	for j := 0; j < Size(); j++ {
		path, before, after := ProofOf(j)
		if !Verify(root, j, Size(), Entry(j), path, before, after) {
			t.Errorf("entry %d: its own proof does not verify", j)
		}
	}
}

// Append trims, so the proof must be over the trimmed entry.
func TestAppendTrims(cur realm, t *testing.T) {
	seed()
	i := Append(cross(cur), "  padded  ")
	if Entry(i) != "padded" {
		t.Fatalf("Entry = %q, want %q", Entry(i), "padded")
	}
	path, before, after := ProofOf(i)
	if !Verify(Root(), i, Size(), "padded", path, before, after) {
		t.Error("trimmed entry does not verify")
	}
	if Verify(Root(), i, Size(), "  padded  ", path, before, after) {
		t.Error("the untrimmed string verified, so the leaf is not what is stored")
	}
}

func TestVerifyRejects(cur realm, t *testing.T) {
	seed()
	root := Root()
	path, before, after := ProofOf(1)
	other := "0000000000000000000000000000000000000000000000000000000000000000"

	tests := []struct {
		name                       string
		root                       string
		index, total               int
		entry, path, before, after string
	}{
		{"wrong entry", root, 1, 3, "not in the log", path, before, after},
		{"another real entry", root, 1, 3, Entry(0), path, before, after},
		{"wrong index", root, 0, 3, Entry(1), path, before, after},
		{"wrong total", root, 1, 4, Entry(1), path, before, after},
		{"wrong root", other, 1, 3, Entry(1), path, before, after},
		{"root not hex", "zz", 1, 3, Entry(1), path, before, after},
		{"root wrong length", "abcd", 1, 3, Entry(1), path, before, after},
		{"empty path", root, 1, 3, Entry(1), "", before, after},
		{"peaks swapped", root, 1, 3, Entry(1), path, after, before},
		{"garbage path", root, 1, 3, Entry(1), "zz", before, after},
	}
	for _, tc := range tests {
		if Verify(tc.root, tc.index, tc.total, tc.entry, tc.path, tc.before, tc.after) {
			t.Errorf("%s: accepted, must be rejected", tc.name)
		}
	}
}

// The log root is also the Tendermint simple-tree root over the same entries,
// so the fixed-leaf-set proof encoding verifies against it too. This is the
// claim the realm makes in Render; it is tested, not asserted.
func TestVerifyFixedAcceptsTendermintProof(cur realm, t *testing.T) {
	seed()
	Append(cross(cur), "a fourth commitment")
	Append(cross(cur), "a fifth commitment")

	leaves := make([][]byte, Size())
	for i := range leaves {
		leaves[i] = []byte(Entry(i))
	}
	tree := merkle.New(leaves)
	if tree.RootHex() != Root() {
		t.Fatalf("tree root %s, log root %s", tree.RootHex(), Root())
	}
	for i := 0; i < Size(); i++ {
		p, err := tree.Proof(i)
		if err != nil {
			t.Fatalf("i=%d: %v", i, err)
		}
		if !VerifyFixed(Root(), i, Size(), Entry(i), p.Hex()) {
			t.Errorf("i=%d: Tendermint proof rejected by the realm", i)
		}
		if VerifyFixed(Root(), i, Size(), "forged", p.Hex()) {
			t.Errorf("i=%d: forged leaf accepted", i)
		}
	}
}

func TestCaps(t *testing.T) {
	seed()
	tests := []struct {
		name  string
		entry string
	}{
		{"empty", ""},
		{"whitespace only", "   "},
		{"too long", strings.Repeat("x", MaxEntryLen+1)},
	}
	for _, tc := range tests {
		if got := panicked(func() { appendEntry(tc.entry) }); got == "" {
			t.Errorf("%s: accepted, must panic", tc.name)
		}
	}
	// A note of exactly MaxEntryLen is fine.
	if got := panicked(func() { appendEntry(strings.Repeat("x", MaxEntryLen)) }); got != "" {
		t.Errorf("entry of exactly MaxEntryLen panicked: %s", got)
	}
}

func TestLogIsBounded(t *testing.T) {
	seed()
	for Size() < MaxEntries {
		appendEntry("filler-" + strconv.Itoa(Size()))
	}
	if got := panicked(func() { appendEntry("one too many") }); got == "" {
		t.Error("appending past MaxEntries was accepted")
	}
	seed()
}

func TestEntryRangeChecked(t *testing.T) {
	seed()
	for _, i := range []int{-1, 3, 999} {
		if got := panicked(func() { Entry(i) }); got == "" {
			t.Errorf("Entry(%d) did not panic", i)
		}
		if got := panicked(func() { ProofOf(i) }); got == "" {
			t.Errorf("ProofOf(%d) did not panic", i)
		}
	}
}

// panicked runs f and returns the panic message, or "" if it returned
// normally. Safe here because these calls are in-package and do not cross a
// realm boundary, where a panic would be an unrecoverable abort instead.
func panicked(f func()) (msg string) {
	defer func() {
		if r := recover(); r != nil {
			if s, ok := r.(string); ok {
				msg = s
			} else {
				msg = "panic"
			}
		}
	}()
	f()
	return ""
}
