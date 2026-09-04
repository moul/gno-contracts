package commitreveal

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

const goodSalt = "0123456789abcdef" // exactly MinSaltLen

func TestCommitAndVerify(t *testing.T) {
	c, err := Commit("rock", goodSalt)
	uassert.NoError(t, err)
	uassert.True(t, ValidCommitment(c), "a commitment is a 32-byte hex digest")
	uassert.Equal(t, 64, len(c), "32 bytes hex-encoded")

	uassert.True(t, Verify(c, "rock", goodSalt), "the correct opening verifies")
}

func TestCommitIsDeterministic(t *testing.T) {
	a, _ := Commit("paper", goodSalt)
	b, _ := Commit("paper", goodSalt)
	uassert.Equal(t, a, b, "same input, same commitment")
}

func TestDifferentValuesDiffer(t *testing.T) {
	a, _ := Commit("rock", goodSalt)
	b, _ := Commit("paper", goodSalt)
	uassert.False(t, a == b)
}

// TestSameValueDifferentSaltDiffers is why the salt exists: two players
// choosing the same move must not publish the same commitment.
func TestSameValueDifferentSaltDiffers(t *testing.T) {
	a, _ := Commit("rock", "salt-one-0123456789")
	b, _ := Commit("rock", "salt-two-0123456789")
	uassert.False(t, a == b, "the same move must not be recognisable across players")
}

func TestWrongOpeningFails(t *testing.T) {
	c, _ := Commit("rock", goodSalt)

	uassert.False(t, Verify(c, "paper", goodSalt), "wrong value")
	uassert.False(t, Verify(c, "rock", "a-different-salt-value"), "wrong salt")
	uassert.False(t, Verify(c, "", goodSalt), "empty value")
}

// TestShortSaltRefused is the enforced-not-advised part: a three-move game with
// a short salt is brute-forceable, so the package will not produce one.
func TestShortSaltRefused(t *testing.T) {
	_, err := Commit("rock", "tooshort")
	uassert.ErrorIs(t, err, ErrShortSalt)

	_, err = Commit("rock", strings.Repeat("x", MinSaltLen-1))
	uassert.ErrorIs(t, err, ErrShortSalt, "one byte under the minimum is still refused")

	_, err = Commit("rock", strings.Repeat("x", MinSaltLen))
	uassert.NoError(t, err, "exactly MinSaltLen is accepted")
}

func TestShortSaltNeverVerifies(t *testing.T) {
	// Even a digest that would match cannot be opened with a short salt.
	uassert.False(t, Verify(MustCommit("rock", goodSalt), "rock", "short"),
		"Verify enforces the salt floor too")
}

func TestLongValueRefused(t *testing.T) {
	_, err := Commit(strings.Repeat("x", MaxValueLen+1), goodSalt)
	uassert.ErrorIs(t, err, ErrLongValue)

	_, err = Commit(strings.Repeat("x", MaxValueLen), goodSalt)
	uassert.NoError(t, err, "exactly MaxValueLen is accepted")
}

// TestLengthPrefixPreventsAmbiguity is the subtle one: with plain
// concatenation, ("ab","cdefghijklmnopq") and ("abc","defghijklmnopq") produce
// the same bytes, so one commitment could be opened two ways.
func TestLengthPrefixPreventsAmbiguity(t *testing.T) {
	a, err := Commit("ab", "cdefghijklmnopqr")
	uassert.NoError(t, err)
	b, err := Commit("abc", "defghijklmnopqr0")
	uassert.NoError(t, err)

	uassert.False(t, a == b, "a split ambiguity must not collide")
	uassert.False(t, Verify(a, "abc", "defghijklmnopqr0"), "and must not cross-verify")
}

func TestOpenReportsReasons(t *testing.T) {
	c := MustCommit("rock", goodSalt)

	uassert.NoError(t, Open(c, "rock", goodSalt))
	uassert.ErrorIs(t, Open(c, "paper", goodSalt), ErrMismatch)
	uassert.ErrorIs(t, Open(c, "rock", "short"), ErrShortSalt)
	uassert.ErrorIs(t, Open(c, strings.Repeat("x", MaxValueLen+1), goodSalt), ErrLongValue)
	uassert.ErrorIs(t, Open("not-hex!!", "rock", goodSalt), ErrBadHexDigest)
	uassert.ErrorIs(t, Open("abcd", "rock", goodSalt), ErrBadHexDigest, "right charset, wrong length")
}

func TestMalformedCommitments(t *testing.T) {
	uassert.False(t, Verify("", "rock", goodSalt))
	uassert.False(t, Verify("zz", "rock", goodSalt), "not hex")
	uassert.False(t, Verify(strings.Repeat("ab", 16), "rock", goodSalt), "16 bytes, not 32")
}

func TestValidCommitment(t *testing.T) {
	uassert.True(t, ValidCommitment(MustCommit("x", goodSalt)))
	uassert.False(t, ValidCommitment(""))
	uassert.False(t, ValidCommitment("nothex"))
	uassert.False(t, ValidCommitment(strings.Repeat("a", 63)), "odd length")
	uassert.False(t, ValidCommitment(strings.Repeat("a", 66)), "too long")
	uassert.True(t, ValidCommitment(strings.Repeat("A", 64)), "uppercase hex is fine")
}

func TestMustCommitPanicsOnBadInput(t *testing.T) {
	defer func() {
		r := recover()
		uassert.True(t, r != nil, "MustCommit must panic on a short salt")
	}()
	MustCommit("rock", "short")
}

func TestEqualConstantTime(t *testing.T) {
	a := []byte{1, 2, 3}
	uassert.True(t, equalConstantTime(a, []byte{1, 2, 3}))
	uassert.False(t, equalConstantTime(a, []byte{1, 2, 4}), "differs in the last byte")
	uassert.False(t, equalConstantTime(a, []byte{9, 2, 3}), "differs in the first byte")
	uassert.False(t, equalConstantTime(a, []byte{1, 2}), "different lengths")
	uassert.True(t, equalConstantTime(nil, nil))
}

// TestFullRoundTrip walks the two phases the scheme is made of.
func TestFullRoundTrip(t *testing.T) {
	// Phase 1: both players publish only a commitment.
	aliceSalt := "alice-secret-salt-1"
	bobSalt := "bob-secret-salt-0001"
	aliceCommit := MustCommit("rock", aliceSalt)
	bobCommit := MustCommit("paper", bobSalt)

	uassert.False(t, aliceCommit == bobCommit)
	uassert.True(t, ValidCommitment(aliceCommit))

	// Phase 2: reveals are checked against the earlier commitments.
	uassert.NoError(t, Open(aliceCommit, "rock", aliceSalt))
	uassert.NoError(t, Open(bobCommit, "paper", bobSalt))

	// Bob cannot change his move after seeing Alice's.
	uassert.ErrorIs(t, Open(bobCommit, "scissors", bobSalt), ErrMismatch)
	// Nor can he claim Alice's commitment as his own.
	uassert.ErrorIs(t, Open(aliceCommit, "rock", bobSalt), ErrMismatch)
}
