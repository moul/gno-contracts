package markov

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestPrefixShiftKey(t *testing.T) {
	p := make(Prefix, PrefixLen)
	uassert.Equal(t, " ", p.key(), "initial key is two empty words joined")

	p.shift("hello")
	uassert.Equal(t, " hello", p.key(), "after one shift")

	p.shift("world")
	uassert.Equal(t, "hello world", p.key(), "after two shifts window is full")

	p.shift("again")
	uassert.Equal(t, "world again", p.key(), "oldest word drops off")
}

func TestBuildCountsAndSuffixes(t *testing.T) {
	c := New()
	added := c.Build("a b a b a b")
	uassert.Equal(t, 6, added, "six words tokenized")

	words, _ := c.Stats()
	uassert.Equal(t, 6, words, "word counter matches")

	// prefixes seen: " "->[a], " a"->[b], "a b"->[a,a], "b a"->[b,b]
	uassert.True(t, c.table.Has("a b"), "prefix 'a b' recorded")
	ab := c.table.Get("a b").(*suffixList)
	uassert.Equal(t, 2, len(ab.words), "'a b' followed twice")
	uassert.Equal(t, "a", ab.words[0], "'a b' is always followed by 'a'")

	// whitespace-only / empty adds nothing
	uassert.Equal(t, 0, c.Build("   "), "blank text adds no words")
}

func TestGenerateDeterministicAndBounded(t *testing.T) {
	c := New()
	c.Build("one two three four one two three five one two six")

	a := strings.Join(c.Generate(8, 42), " ")
	b := strings.Join(c.Generate(8, 42), " ")
	uassert.Equal(t, a, b, "same seed => identical output")

	// the walk is seed-sensitive: across a spread of seeds at least one
	// diverges from the seed-42 output (some seeds may coincidentally match).
	sensitive := false
	for _, s := range []uint64{1, 7, 13, 12345, 8675309} {
		if strings.Join(c.Generate(8, s), " ") != a {
			sensitive = true
			break
		}
	}
	uassert.True(t, sensitive, "output varies with the seed")

	// non-positive n and empty corpus both yield nothing
	uassert.Equal(t, 0, len(c.Generate(0, 1)), "n<=0 yields no words")
	empty := New()
	uassert.Equal(t, 0, len(empty.Generate(10, 1)), "empty corpus yields no words")
}

func TestStatsAndIterate(t *testing.T) {
	c := New()
	c.Build("a b a b a b")

	words, prefixes := c.Stats()
	uassert.Equal(t, 6, words, "total words")
	uassert.Equal(t, 4, prefixes, "distinct prefixes")

	seen := 0
	stopped := c.Iterate(func(prefix string, suffixes []string) bool {
		uassert.True(t, len(suffixes) > 0, "each prefix has suffixes")
		seen++
		return false
	})
	uassert.Equal(t, 4, seen, "iterated over every prefix")
	uassert.False(t, stopped, "ran to completion")
}
