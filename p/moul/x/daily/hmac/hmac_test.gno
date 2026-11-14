package hmac

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

// rep returns n copies of b. RFC 4231's keys and messages are mostly runs of
// one byte, and writing them out as literals hides their length, which is the
// property half of these cases exist to exercise.
func rep(b byte, n int) []byte {
	out := make([]byte, n)
	for i := range out {
		out[i] = b
	}
	return out
}

func mustHex(t *testing.T, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex fixture %q: %v", s, err)
	}
	return b
}

// TestRFC4231Vectors runs the five HMAC-SHA-256 test cases of RFC 4231 that
// apply here (cases 1 to 7, minus the two that only differ in truncation),
// plus the empty-key empty-message case. These are published constants: an
// implementation that disagrees with them is wrong, not merely different.
func TestRFC4231Vectors(t *testing.T) {
	cases := []struct {
		name string
		key  []byte
		msg  []byte
		want string
	}{
		{"case1-20B key", rep(0x0b, 20), []byte("Hi There"), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"},
		{"case2-short key", []byte("Jefe"), []byte("what do ya want for nothing?"), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"},
		{"case3-repeated data", rep(0xaa, 20), rep(0xdd, 50), "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"},
		{"case5-truncation input", rep(0x0c, 20), []byte("Test With Truncation"), "a3b6167473100ee06e0c796c2955552bfa6f7c0a6a8aef8b93f860aab0cd20c5"},
		{"case6-131B key", rep(0xaa, 131), []byte("Test Using Larger Than Block-Size Key - Hash Key First"), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"},
		{"case7-131B key, long data", rep(0xaa, 131), []byte("This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm."), "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"},
		{"empty key, empty message", []byte{}, []byte{}, "b613679a0814d9ec772f95d778c35fc5ff1697c493715653c6c712144292c5ad"},
	}
	for _, tc := range cases {
		got := hex.EncodeToString(SumSHA256(tc.key, tc.msg))
		if got != tc.want {
			t.Errorf("%s: SumSHA256 = %s, want %s", tc.name, got, tc.want)
		}
	}
}

// TestCase4IsTheOneWithANonRepeatingKey keeps RFC 4231 case 4 separate because
// its key is a hex literal rather than a run, and a fixture that is wrong in
// the same way as the code it tests is the failure mode a run cannot catch.
func TestCase4IsTheOneWithANonRepeatingKey(t *testing.T) {
	key := mustHex(t, "0102030405060708090a0b0c0d0e0f10111213141516171819")
	got := hex.EncodeToString(SumSHA256(key, rep(0xcd, 50)))
	want := "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"
	if got != want {
		t.Errorf("SumSHA256 = %s, want %s", got, want)
	}
}

// TestLongKeyIsHashedFirst pins the identity that makes HMAC's key handling
// observable: once a key is longer than the block size it is replaced by its
// own digest, so a 131-byte key and its 32-byte SHA-256 produce the SAME tag.
// Two distinct keys, one tag. An implementation that simply truncates or pads
// a long key passes every other test in this file and fails this one.
func TestLongKeyIsHashedFirst(t *testing.T) {
	long := rep(0xaa, 131)
	msg := []byte("Test Using Larger Than Block-Size Key - Hash Key First")

	folded := SHA256(long)
	if a, b := hex.EncodeToString(SumSHA256(long, msg)), hex.EncodeToString(SumSHA256(folded, msg)); a != b {
		t.Errorf("HMAC(K,m) = %s, HMAC(SHA256(K),m) = %s, want them equal", a, b)
	}

	// ...and not the same as using the first 64 bytes of the key, which is
	// what a truncating implementation would do.
	truncated := long[:64]
	if a, b := hex.EncodeToString(SumSHA256(long, msg)), hex.EncodeToString(SumSHA256(truncated, msg)); a == b {
		t.Errorf("a 131-byte key and its first 64 bytes produced the same tag %s: the key is not being hashed", a)
	}
}

// TestShortKeyIsZeroPaddedNotRejected pins the other half of the same rule and
// the footgun that comes with it: a short key is padded with zero bytes to the
// block size, so a key and that key followed by zeros are indistinguishable.
func TestShortKeyIsZeroPaddedNotRejected(t *testing.T) {
	key := []byte("moul")
	padded := make([]byte, BlockSizeSHA256)
	copy(padded, key)

	a := hex.EncodeToString(SumSHA256(key, []byte("gno.land")))
	b := hex.EncodeToString(SumSHA256(padded, []byte("gno.land")))
	if a != b {
		t.Errorf("key and zero-padded key gave %s and %s, want them equal", a, b)
	}
}

// TestBlockSizeBoundary pins the two keys either side of the block size, which
// is where the hash-the-key branch turns on. 64 bytes is used as-is, 65 is
// hashed, and nothing in the output says which path ran.
func TestBlockSizeBoundary(t *testing.T) {
	msgA := []byte("exactly one block of key")
	msgB := []byte("one byte past a block")
	if got, want := hex.EncodeToString(SumSHA256(rep(0x61, 64), msgA)), "2f5d927e25c3dcd398d3e8e87507bd760f432038bceae01811ac20220fa2c2cc"; got != want {
		t.Errorf("64-byte key: got %s, want %s", got, want)
	}
	if got, want := hex.EncodeToString(SumSHA256(rep(0x61, 65), msgB)), "d7500b6eb487f9c7e791c4683a3dc34d9d0ad2739cfc9f55b4f2be71ada92960"; got != want {
		t.Errorf("65-byte key: got %s, want %s", got, want)
	}
}

// TestNotAPrefixMAC is the test that refuses the implementation everybody
// writes first. sha256(key || message) is a plausible-looking MAC, it produces
// a 32-byte tag that changes with both inputs, and it is forgeable by length
// extension. It is also not HMAC, and this is the assertion that says so.
func TestNotAPrefixMAC(t *testing.T) {
	key, msg := []byte("moul"), []byte("gno.land")

	naive := sha256.Sum256(append(append([]byte{}, key...), msg...))
	if got, want := hex.EncodeToString(naive[:]), "c8af45c152186266cc24b0285bc5d00c05a90c39058b807db308369c4740b5b6"; got != want {
		t.Fatalf("the prefix-MAC fixture itself is wrong: got %s, want %s", got, want)
	}
	if got := hex.EncodeToString(SumSHA256(key, msg)); got == hex.EncodeToString(naive[:]) {
		t.Errorf("SumSHA256 returned the prefix MAC %s: this is sha256(key||message), not HMAC", got)
	}
	if got, want := hex.EncodeToString(SumSHA256(key, msg)), "185144fe6ab8ff4ee0118a1441c2d7911a80f07607ec968a2abee25c2df6e7c1"; got != want {
		t.Errorf("SumSHA256 = %s, want %s", got, want)
	}
}

// TestTagDependsOnBothInputs is the weakest property here and the one a broken
// implementation is most likely to satisfy anyway. It is kept because its
// absence would be worse, not because its presence proves much.
func TestTagDependsOnBothInputs(t *testing.T) {
	base := hex.EncodeToString(SumSHA256([]byte("k"), []byte("m")))
	if other := hex.EncodeToString(SumSHA256([]byte("l"), []byte("m"))); other == base {
		t.Error("changing the key did not change the tag")
	}
	if other := hex.EncodeToString(SumSHA256([]byte("k"), []byte("n"))); other == base {
		t.Error("changing the message did not change the tag")
	}
}

// TestSumIsGenericOverTheHash pins that the SHA-256 helper is a thin wrapper
// and nothing more, so a caller with another one-shot hash gets the same
// construction rather than a second code path.
func TestSumIsGenericOverTheHash(t *testing.T) {
	key, msg := []byte("Jefe"), []byte("what do ya want for nothing?")
	a := hex.EncodeToString(Sum(SHA256, BlockSizeSHA256, key, msg))
	b := hex.EncodeToString(SumSHA256(key, msg))
	if a != b {
		t.Errorf("Sum = %s, SumSHA256 = %s, want them equal", a, b)
	}
}

// TestSumRejectsAnUnusableBlockSize covers the two panics, including the one
// that matters: a block size smaller than the digest leaves nowhere to put the
// hashed key, and silently producing a tag there would be worse than aborting.
func TestSumRejectsAnUnusableBlockSize(t *testing.T) {
	assertPanics(t, "non-positive block size", func() { Sum(SHA256, 0, []byte("k"), []byte("m")) })
	assertPanics(t, "digest longer than block", func() { Sum(SHA256, 16, rep(0x61, 100), []byte("m")) })
	assertPanics(t, "nil hash", func() { Sum(nil, BlockSizeSHA256, []byte("k"), []byte("m")) })
}

func assertPanics(t *testing.T, what string, fn func()) {
	t.Helper()
	defer func() {
		if recover() == nil {
			t.Errorf("%s: expected a panic, got none", what)
		}
	}()
	fn()
}

// TestSumDoesNotMutateItsInputs is here because the construction is built out
// of appends and a careless one would write through the caller's key.
func TestSumDoesNotMutateItsInputs(t *testing.T) {
	key := []byte("a key with spare capacity")
	msg := []byte("a message")
	keyCopy := string(key)
	msgCopy := string(msg)
	SumSHA256(key, msg)
	if string(key) != keyCopy {
		t.Errorf("key mutated: %q became %q", keyCopy, string(key))
	}
	if string(msg) != msgCopy {
		t.Errorf("message mutated: %q became %q", msgCopy, string(msg))
	}
}

// TestEqualComparesWithoutEarlyExit checks what Equal can actually be tested
// for: the answer. The timing claim in its doc comment is not observable from
// inside the VM and this test does not pretend to check it.
func TestEqualComparesWithoutEarlyExit(t *testing.T) {
	cases := []struct {
		name string
		a, b []byte
		want bool
	}{
		{"identical", []byte{1, 2, 3}, []byte{1, 2, 3}, true},
		{"first byte differs", []byte{9, 2, 3}, []byte{1, 2, 3}, false},
		{"last byte differs", []byte{1, 2, 9}, []byte{1, 2, 3}, false},
		{"b is a prefix of a", []byte{1, 2, 3}, []byte{1, 2}, false},
		{"both empty", []byte{}, []byte{}, true},
		{"one empty", []byte{}, []byte{0}, false},
	}
	for _, tc := range cases {
		if got := Equal(tc.a, tc.b); got != tc.want {
			t.Errorf("%s: Equal = %t, want %t", tc.name, got, tc.want)
		}
	}
}

// TestVerifySHA256 pins the whole point of the package: a verifier that says
// yes to the right tag and no to a tag one bit away from it.
func TestVerifySHA256(t *testing.T) {
	key, msg := []byte("moul"), []byte("gno.land")
	tag := SumSHA256(key, msg)
	if !VerifySHA256(key, msg, tag) {
		t.Error("the tag this package just produced did not verify")
	}

	flipped := append([]byte{}, tag...)
	flipped[len(flipped)-1] ^= 0x01
	if VerifySHA256(key, msg, flipped) {
		t.Error("a tag with one bit flipped verified")
	}
	if VerifySHA256([]byte("moUl"), msg, tag) {
		t.Error("a different key verified")
	}
	if VerifySHA256(key, []byte("gno.lanD"), tag) {
		t.Error("a different message verified")
	}
	if VerifySHA256(key, msg, tag[:16]) {
		t.Error("a truncated tag verified against a full-length one")
	}
}

// TestHexSHA256 pins the string-in, string-out helper against the same vector
// the byte API is pinned against, so the two cannot drift.
func TestHexSHA256(t *testing.T) {
	got := HexSHA256("Jefe", "what do ya want for nothing?")
	want := "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
	if got != want {
		t.Errorf("HexSHA256 = %s, want %s", got, want)
	}
	if strings.ToLower(got) != got {
		t.Error("HexSHA256 should return lowercase hex")
	}
}

// TestTruncate covers RFC 2104 section 5's truncated tag, and the two edges
// that a careless implementation gets wrong: n at or past the full length.
func TestTruncate(t *testing.T) {
	tag := SumSHA256([]byte("moul"), []byte("gno.land"))
	if got, want := hex.EncodeToString(Truncate(tag, 16)), "185144fe6ab8ff4ee0118a1441c2d791"; got != want {
		t.Errorf("Truncate(tag, 16) = %s, want %s", got, want)
	}
	if got := len(Truncate(tag, 32)); got != 32 {
		t.Errorf("Truncate(tag, 32) length = %d, want 32", got)
	}
	if got := len(Truncate(tag, 99)); got != 32 {
		t.Errorf("Truncate(tag, 99) length = %d, want the full 32", got)
	}
	assertPanics(t, "negative n", func() { Truncate(tag, -1) })

	// The returned slice must not alias the tag: a caller that truncates and
	// then zeroes would otherwise clear the original.
	short := Truncate(tag, 16)
	short[0] ^= 0xff
	if tag[0] == short[0] {
		t.Error("Truncate aliases its input")
	}
}
