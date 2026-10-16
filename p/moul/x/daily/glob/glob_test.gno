package glob

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestMatchLiteralsAndSingles(t *testing.T) {
	cases := []struct {
		pattern string
		name    string
		want    bool
	}{
		{"", "", true},
		{"", "a", false},
		{"a", "", false},
		{"abc", "abc", true},
		{"abc", "abd", false},
		{"abc", "abcd", false},
		{"?", "a", true},
		{"?", "", false},
		{"a?c", "abc", true},
		{"a?c", "ac", false},
		{"???", "abc", true},
		{"???", "ab", false},
		// '?' is one BYTE, not one rune. Documented, and pinned here so the
		// claim in the README cannot drift away from the code.
		{"?", "é", false},
		{"??", "é", true},
	}
	for _, tc := range cases {
		got := Match(tc.pattern, tc.name)
		uassert.Equal(t, tc.want, got, "Match("+tc.pattern+", "+tc.name+")")
	}
}

func TestMatchStar(t *testing.T) {
	cases := []struct {
		pattern string
		name    string
		want    bool
	}{
		{"*", "", true},
		{"*", "anything", true},
		{"*", "with/slashes/inside", true},
		{"a*", "a", true},
		{"a*", "abc", true},
		{"a*", "b", false},
		{"*c", "abc", true},
		{"*c", "abd", false},
		{"a*c", "ac", true},
		{"a*c", "abc", true},
		{"a*c", "abbbbc", true},
		{"a*c", "abbbbd", false},
		{"**", "abc", true},
		{"a**c", "abc", true},
		// The pattern a naive recursive matcher takes exponential time on.
		// Here it is a correctness case; the cost claim is in the README.
		{"a*a*a*a*a*a*b", "aaaaaaaaaaaaaaaaaaaaaaaa", false},
		{"a*a*a*a*a*a*b", "aaaaaaaaaaaaaaaaaaaaaaab", true},
	}
	for _, tc := range cases {
		got := Match(tc.pattern, tc.name)
		uassert.Equal(t, tc.want, got, "Match("+tc.pattern+", "+tc.name+")")
	}
}

func TestMatchClass(t *testing.T) {
	cases := []struct {
		pattern string
		name    string
		want    bool
	}{
		{"[abc]", "b", true},
		{"[abc]", "d", false},
		{"[a-z]", "q", true},
		{"[a-z]", "Q", false},
		{"[a-zA-Z0-9]", "7", true},
		{"[!a-z]", "Q", true},
		{"[!a-z]", "q", false},
		{"[^a-z]", "Q", true},
		{"g1[a-z0-9]*", "g1manfred", true},
		{"g1[a-z0-9]*", "g1MANFRED", false},
		// A '-' at either end of a class is a literal, not a range.
		{"[-a]", "-", true},
		{"[a-]", "-", true},
		{"[a-]", "a", true},
		{"[a-]", "b", false},
		// A ']' inside a class has to be escaped; there is no POSIX
		// leading-']' rule here.
		{`[\]]`, "]", true},
		{`[\]]`, "x", false},
		// A class never matches an empty name: it consumes exactly one byte.
		{"[abc]", "", false},
	}
	for _, tc := range cases {
		got := Match(tc.pattern, tc.name)
		uassert.Equal(t, tc.want, got, "Match("+tc.pattern+", "+tc.name+")")
	}
}

func TestMatchEscape(t *testing.T) {
	cases := []struct {
		pattern string
		name    string
		want    bool
	}{
		{`\*`, "*", true},
		{`\*`, "abc", false},
		{`a\*b`, "a*b", true},
		{`a\*b`, "axb", false},
		{`\?`, "?", true},
		{`\?`, "a", false},
		{`\[a]`, "[a]", true},
		{`\\`, `\`, true},
	}
	for _, tc := range cases {
		got := Match(tc.pattern, tc.name)
		uassert.Equal(t, tc.want, got, "Match("+tc.pattern+", "+tc.name+")")
	}
}

func TestValid(t *testing.T) {
	cases := []struct {
		pattern string
		want    bool
	}{
		{"", true},
		{"abc", true},
		{"a*b?c", true},
		{"[a-z]", true},
		{"[!a-z]", true},
		{`[\]]`, true},
		{`a\*b`, true},
		{"**/*.gno", true},
		// Unterminated class.
		{"[a-z", false},
		{"[", false},
		// Empty class: '[]' is not a class, and '[!]' negates nothing.
		{"[]", false},
		{"[!]", false},
		// Dangling escape, including one that eats the closing bracket.
		{`abc\`, false},
		{`[a\`, false},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, Valid(tc.pattern), "Valid("+tc.pattern+")")
	}
}

// TestInvalidPatternMatchesNothing pins the decision that replaces an error
// return: Match has no way to report a bad pattern, so a bad pattern is inert
// rather than permissive. The failure mode of the alternative is an allowlist
// entry with a typo that matches everything.
func TestInvalidPatternMatchesNothing(t *testing.T) {
	for _, pattern := range []string{"[a-z", "[]", `abc\`} {
		uassert.False(t, Match(pattern, "abc"), "Match("+pattern+", abc)")
		uassert.False(t, Match(pattern, ""), "Match("+pattern+", empty)")
		uassert.False(t, MatchPath(pattern, "abc"), "MatchPath("+pattern+", abc)")
	}
}

func TestMatchPathSingleStarStopsAtSeparator(t *testing.T) {
	cases := []struct {
		pattern string
		name    string
		want    bool
	}{
		{"*", "abc", true},
		{"*", "a/b", false},
		{"?", "/", false},
		{"a/*", "a/b", true},
		{"a/*", "a/b/c", false},
		{"a/*/c", "a/b/c", true},
		{"a/*/c", "a/c", false},
		{"[a-z]/x", "q/x", true},
		{"[a-z]/x", "q/y", false},
		// The allowlist case this package exists for.
		{"gno.land/r/moul/*", "gno.land/r/moul/home", true},
		{"gno.land/r/moul/*", "gno.land/r/moul/x/daily", false},
		{"gno.land/r/moul/*", "gno.land/r/other/home", false},
	}
	for _, tc := range cases {
		got := MatchPath(tc.pattern, tc.name)
		uassert.Equal(t, tc.want, got, "MatchPath("+tc.pattern+", "+tc.name+")")
	}
}

func TestMatchPathDoubleStarCrossesSeparator(t *testing.T) {
	cases := []struct {
		pattern string
		name    string
		want    bool
	}{
		{"**", "", true},
		{"**", "a", true},
		{"**", "a/b/c", true},
		{"a/**", "a/b", true},
		{"a/**", "a/b/c/d", true},
		{"a/**", "b/c", false},
		// A '**' segment matches zero segments too, which is the case a
		// segment-by-segment walk gets wrong.
		{"a/**/b", "a/b", true},
		{"a/**/b", "a/x/b", true},
		{"a/**/b", "a/x/y/b", true},
		{"a/**/b", "a/x/y/c", false},
		{"**/c", "a/b/c", true},
		{"**/c", "c", true},
		{"**/c", "a/b/d", false},
		{"gno.land/r/moul/**", "gno.land/r/moul/x/daily/globdemo", true},
		// '**' only crosses as a whole segment. Glued to anything else it is
		// an ordinary star and stays inside its own segment.
		{"a/**x/b", "a/y/x/b", false},
		{"a/**x/b", "a/yx/b", true},
	}
	for _, tc := range cases {
		got := MatchPath(tc.pattern, tc.name)
		uassert.Equal(t, tc.want, got, "MatchPath("+tc.pattern+", "+tc.name+")")
	}
}

// TestMatchPathIsNotMatch pins the one difference a caller is most likely to
// assume away: the same pattern and name answer differently in the two modes.
func TestMatchPathIsNotMatch(t *testing.T) {
	uassert.True(t, Match("gno.land/*", "gno.land/r/moul/home"), "Match crosses")
	uassert.False(t, MatchPath("gno.land/*", "gno.land/r/moul/home"), "MatchPath does not")
}

func TestFilter(t *testing.T) {
	names := []string{"alpha.gno", "beta.gno", "alpha_test.gno", "README.md"}

	got := Filter("*.gno", names)
	uassert.Equal(t, 3, len(got))
	uassert.Equal(t, "alpha.gno", got[0])
	uassert.Equal(t, "beta.gno", got[1])
	uassert.Equal(t, "alpha_test.gno", got[2])

	got = Filter("*_test.gno", names)
	uassert.Equal(t, 1, len(got))
	uassert.Equal(t, "alpha_test.gno", got[0])

	// No match returns an empty slice, never nil, so a caller can range and
	// len it without a guard.
	got = Filter("*.txt", names)
	uassert.Equal(t, 0, len(got))
	uassert.True(t, got != nil, "Filter returns a non-nil empty slice")

	// An invalid pattern filters everything out rather than letting it through.
	uassert.Equal(t, 0, len(Filter("[a-z", names)))
}

func TestFilterPath(t *testing.T) {
	paths := []string{
		"gno.land/r/moul/home",
		"gno.land/r/moul/x/daily/globdemo",
		"gno.land/p/moul/x/daily/glob",
		"gno.land/r/other/home",
	}

	got := FilterPath("gno.land/r/moul/*", paths)
	uassert.Equal(t, 1, len(got))
	uassert.Equal(t, "gno.land/r/moul/home", got[0])

	got = FilterPath("gno.land/r/moul/**", paths)
	uassert.Equal(t, 2, len(got))
	uassert.Equal(t, "gno.land/r/moul/home", got[0])
	uassert.Equal(t, "gno.land/r/moul/x/daily/globdemo", got[1])

	got = FilterPath("gno.land/*/moul/**", paths)
	uassert.Equal(t, 3, len(got))
}

func TestAny(t *testing.T) {
	patterns := []string{"*.gno", "*.md"}
	uassert.True(t, Any(patterns, "a.gno"))
	uassert.True(t, Any(patterns, "README.md"))
	uassert.False(t, Any(patterns, "a.txt"))
	uassert.False(t, Any(nil, "a.gno"), "no pattern matches nothing")
	// One bad entry does not make the whole list permissive, and does not
	// disable the good entries either.
	uassert.True(t, Any([]string{"[a-z", "*.gno"}, "a.gno"))
	uassert.False(t, Any([]string{"[a-z"}, "a.gno"))
}

func TestAnyPath(t *testing.T) {
	allow := []string{
		"gno.land/r/moul/home",
		"gno.land/r/moul/x/daily/**",
	}
	uassert.True(t, AnyPath(allow, "gno.land/r/moul/home"))
	uassert.True(t, AnyPath(allow, "gno.land/r/moul/x/daily/globdemo"))
	uassert.False(t, AnyPath(allow, "gno.land/r/moul/blog"))
	// The prefix trap a hand-rolled HasPrefix allowlist walks into: a longer
	// sibling name is not a child path.
	uassert.False(t, AnyPath(allow, "gno.land/r/moul/homeless"))
	uassert.False(t, AnyPath(allow, "gno.land/r/moul/x/dailyevil/thing"))
}

// TestStarIsGreedyButBacktracks is the property a single-backtrack-point
// matcher has to get right: the first star takes everything it can, then gives
// bytes back one at a time until the tail fits.
func TestStarIsGreedyButBacktracks(t *testing.T) {
	uassert.True(t, Match("*.gno", "a.b.c.gno"))
	uassert.True(t, Match("*ab*", "xxabyy"))
	uassert.True(t, Match("*ab*cd", "xxabyycd"))
	uassert.False(t, Match("*ab*cd", "xxabyycde"))
	uassert.True(t, Match("a*b*c*d", "abcd"))
	uassert.True(t, Match("a*b*c*d", "a1b2c3d"))
	uassert.False(t, Match("a*b*c*d", "a1b2c3"))
}

// TestMatchPathSeparatorInsidePatternSyntax pins the one place the two layers
// of this package can disagree: a '/' that is escaped, or that sits inside a
// character class, belongs to its segment and must not split the pattern.
// Splitting there cuts an escape pair or a bracket expression in half, and the
// matcher then reads past the end of the piece it was handed.
//
// No name segment can contain a separator, so such a pattern matches nothing.
// The requirement is that it answers rather than aborts: a Render that panics
// on a stored pattern is a page that is broken for good.
func TestMatchPathSeparatorInsidePatternSyntax(t *testing.T) {
	cases := []struct {
		pattern string
		name    string
	}{
		{`a\/b`, "ax/b"},
		{`a\/b`, "a/b"},
		{`a\/b`, "ab"},
		{`a\/b`, ""},
		{"[/]", "x/y"},
		{"[/]", "x"},
		{"[a-/]", "x"},
		{`**/a\/b`, "x/y"},
		{`a\/b/c`, "a/b/c"},
	}
	for _, tc := range cases {
		uassert.False(t, MatchPath(tc.pattern, tc.name),
			"MatchPath("+tc.pattern+", "+tc.name+")")
	}

	// FilterPath and AnyPath split the same way and must be total too.
	uassert.Equal(t, 0, len(FilterPath(`a\/b`, []string{"ax/b", "a/b"})))
	uassert.Equal(t, 0, len(FilterPath("[/]", []string{"x/y", "x"})))
	uassert.False(t, AnyPath([]string{"[/]", `a\/b`}, "x/y"))

	// A separator that is neither escaped nor in a class still splits, and a
	// class holding one still works on the segment it belongs to.
	uassert.True(t, MatchPath(`a\*b/c`, "a*b/c"), `MatchPath(a\*b/c, a*b/c)`)
	uassert.True(t, MatchPath("[abc]/x", "b/x"), "MatchPath([abc]/x, b/x)")
	// A negated class holding the separator is the one shape here that does
	// match: it is a single segment meaning "any byte but a separator", which
	// is what every name segment is.
	uassert.True(t, MatchPath("[!/]", "x"), "MatchPath([!/], x)")
}
