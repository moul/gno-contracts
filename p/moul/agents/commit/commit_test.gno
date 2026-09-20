package commit

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestHashDeterministicAndPrefixed(t *testing.T) {
	uassert.Equal(t, Hash("a", "bc"), Hash("a", "bc"))
	// length-prefixing prevents boundary collisions
	uassert.NotEqual(t, Hash("ab", "c"), Hash("a", "bc"))
	uassert.Equal(t, 64, len(Hash("x"))) // sha256 hex is 64 chars
}

func TestVerdictCommitReveal(t *testing.T) {
	c := Verdict(true, "salt-123")
	// reproducible from the revealed values
	uassert.Equal(t, c, Verdict(true, "salt-123"))
	// flipping the vote or the salt changes the commitment
	uassert.NotEqual(t, c, Verdict(false, "salt-123"))
	uassert.NotEqual(t, c, Verdict(true, "salt-999"))
}

func TestShort(t *testing.T) {
	uassert.Equal(t, "abc", Short("abc"))
	uassert.True(t, len(Short(Hash("x"))) < 20)
}
