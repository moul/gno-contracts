package markov

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestPrefixShiftKey(t *testing.T) {
	p := make(Prefix, prefixLen)
	uassert.Equal(t, " ", p.key(), "initial key is two empty words joined")

	p.shift("hello")
	uassert.Equal(t, " hello", p.key(), "after one shift")

	p.shift("world")
	uassert.Equal(t, "hello world", p.key(), "after two shifts window is full")

	p.shift("again")
	uassert.Equal(t, "world again", p.key(), "oldest word drops off")
}

func TestBuildCountsAndSuffixes(t *testing.T) {
	c := newChain()
	added := c.build("a b a b a b")
	uassert.Equal(t, 6, added, "six words tokenized")
	uassert.Equal(t, 6, c.words, "word counter matches")

	// prefixes seen: " "->[a], " a"->[b], "a b"->[a,a], "b a"->[b,b]
	uassert.True(t, c.table.Has("a b"), "prefix 'a b' recorded")
	ab := c.table.Get("a b").(*suffixList)
	uassert.Equal(t, 2, len(ab.words), "'a b' followed twice")
	uassert.Equal(t, "a", ab.words[0], "'a b' is always followed by 'a'")

	// whitespace-only / empty adds nothing
	uassert.Equal(t, 0, c.build("   "), "blank text adds no words")
}

func TestGenerateDeterministicAndBounded(t *testing.T) {
	c := newChain()
	c.build("one two three four one two three five one two six")

	a := strings.Join(c.generate(8, 42), " ")
	b := strings.Join(c.generate(8, 42), " ")
	uassert.Equal(t, a, b, "same seed => identical output")

	diff := strings.Join(c.generate(8, 99), " ")
	uassert.True(t, a != diff || a == "", "different seed can diverge")

	// non-positive n and empty corpus both yield nothing
	uassert.Equal(t, 0, len(c.generate(0, 1)), "n<=0 yields no words")
	empty := newChain()
	uassert.Equal(t, 0, len(empty.generate(10, 1)), "empty corpus yields no words")
}

func TestParseN(t *testing.T) {
	uassert.Equal(t, 40, parseN("/40"), "trailing number")
	uassert.Equal(t, 60, parseN("gen/60"), "number after slash")
	uassert.Equal(t, 0, parseN("/"), "no number")
	uassert.Equal(t, 0, parseN("abc"), "non-numeric")
}
