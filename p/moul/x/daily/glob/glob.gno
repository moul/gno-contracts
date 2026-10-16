// Package glob matches shell-style patterns against strings, in two modes:
// plain, where `*` crosses everything, and path, where `/` is a boundary that
// only `**` crosses.
//
// The reason to have it on chain is the allowlist. A realm that decides what a
// caller may touch writes the rule as a pattern (gno.land/r/moul/**), and the
// obvious alternative, strings.HasPrefix, is wrong in a way that only shows up
// in production: the prefix gno.land/r/moul/home also matches
// gno.land/r/moul/homeless, and the prefix a caller gets by trimming /** off
// the rule above, gno.land/r/moul, also matches gno.land/r/moulier/drain, a
// different namespace owned by a different person. A separator-aware matcher
// cannot make either mistake, because a boundary is part of the grammar rather
// than something the caller remembered to append. Remembering to append it is
// no answer either: gno.land/r/moul/home with a slash on the end stops being a
// rule that matches the path it names.
//
// The matcher is iterative with a single backtrack point, so it runs in
// O(len(pattern) * len(name)) time and constant space. That is not a style
// preference. The recursive one-liner every glob tutorial shows is exponential
// on a pattern like a*a*a*a*a*a*b, and a realm that accepts a pattern from a
// caller and runs an exponential matcher on it has handed out a gas bomb.
//
// Matching is byte-oriented, deliberately: `?` matches one byte and a class
// range compares bytes, so this package is for ASCII subjects (package paths,
// bech32 addresses, handles, file names) and not for matching prose. See the
// package README for what that rules out.
//
// A live demo of this package is at
// [r/moul/x/daily/globdemo](/r/moul/x/daily/globdemo/v0).
package glob

import "strings"

// Separator is the byte [MatchPath] treats as a path boundary.
const Separator = '/'

// Match reports whether name matches pattern.
//
//	?          any single byte
//	*          any sequence of bytes, including none
//	[abc]      any one of the listed bytes
//	[a-z]      any byte in the range, ends inclusive
//	[!abc]     any byte NOT listed; [^abc] is the same thing
//	\x         the literal byte x, for any x
//	anything else  itself
//
// `*` crosses every byte, including [Separator]. Use [MatchPath] when the
// subject is a path and a wildcard must stay inside one segment.
//
// An invalid pattern matches nothing. There is no error return, so the choice
// is between inert and permissive, and a bad allowlist entry that matches
// everything is the worse of the two. Ask [Valid] when it matters.
func Match(pattern, name string) bool {
	if !Valid(pattern) {
		return false
	}
	return matchBytes(pattern, name)
}

// MatchPath reports whether name matches pattern, with [Separator] as a
// boundary neither side may cross by accident.
//
// Both are split into segments, and then:
//
//   - a segment that is exactly `**` matches zero or more whole segments
//   - every other segment is matched by [Match] against one segment, so `*`,
//     `?` and a class can never reach past the separator
//
// `**` only crosses as a whole segment. Glued to anything else, as in `a**b`,
// it is an ordinary star confined to its segment.
//
// A [Separator] that is escaped (`a\/b`) or inside a class (`[/]`) belongs to
// its segment and does not split the pattern. Such a pattern matches nothing,
// because a name segment can never contain a separator, and it says so by
// returning false rather than by aborting.
//
// An invalid pattern matches nothing, as in [Match].
func MatchPath(pattern, name string) bool {
	if !Valid(pattern) {
		return false
	}
	return matchSegments(splitPattern(pattern), splitName(name))
}

// Valid reports whether pattern is well formed.
//
// Three things make it malformed, and each of them is a typo a caller makes
// rather than a construct anyone writes on purpose: an unterminated class
// (`[a-z`), an empty one (`[]`, `[!]`), and a trailing backslash with nothing
// to escape (`abc\`).
func Valid(pattern string) bool {
	for i := 0; i < len(pattern); {
		switch pattern[i] {
		case '\\':
			if i+1 >= len(pattern) {
				return false
			}
			i += 2
		case '[':
			j := i + 1
			if j < len(pattern) && (pattern[j] == '!' || pattern[j] == '^') {
				j++
			}
			start := j
			for j < len(pattern) && pattern[j] != ']' {
				if pattern[j] == '\\' {
					j++
					if j >= len(pattern) {
						return false
					}
				}
				j++
			}
			// j == start is an empty class, which is a typo rather than a
			// class that matches nothing: nobody writes one deliberately.
			if j >= len(pattern) || j == start {
				return false
			}
			i = j + 1
		default:
			i++
		}
	}
	return true
}

// Filter returns the elements of names matching pattern, in their original
// order, using [Match].
//
// The result is never nil, so a caller can range and len it with no guard.
func Filter(pattern string, names []string) []string {
	out := []string{}
	if !Valid(pattern) {
		return out
	}
	for _, n := range names {
		if matchBytes(pattern, n) {
			out = append(out, n)
		}
	}
	return out
}

// FilterPath is [Filter] with [MatchPath] semantics.
func FilterPath(pattern string, names []string) []string {
	out := []string{}
	if !Valid(pattern) {
		return out
	}
	psegs := splitPattern(pattern)
	for _, n := range names {
		if matchSegments(psegs, splitName(n)) {
			out = append(out, n)
		}
	}
	return out
}

// Any reports whether name matches at least one of patterns, using [Match].
//
// An invalid entry is skipped rather than failing the whole list: one typo in
// an allowlist should cost that rule and no other.
func Any(patterns []string, name string) bool {
	for _, p := range patterns {
		if Match(p, name) {
			return true
		}
	}
	return false
}

// AnyPath is [Any] with [MatchPath] semantics. This is the allowlist
// primitive: a list of rules, a subject, one boolean.
func AnyPath(patterns []string, name string) bool {
	for _, p := range patterns {
		if MatchPath(p, name) {
			return true
		}
	}
	return false
}

// matchBytes is the matcher proper, over a pattern already known valid.
//
// It walks both strings forward and remembers exactly one position: the most
// recent `*` and how much of name it had consumed when it was reached. On a
// mismatch it returns there and hands that star one more byte. That single
// backtrack point is what keeps the whole thing O(len(pattern)*len(name)) in
// time and O(1) in space, where the recursive formulation branches at every
// star and goes exponential.
//
// It is correct precisely because every other pattern element consumes exactly
// one byte: a later star can always absorb whatever an earlier one gives back,
// so there is never a reason to reconsider any star but the last.
func matchBytes(pattern, name string) bool {
	px, nx := 0, 0
	starPx, starNx := -1, -1

	for nx < len(name) {
		if px < len(pattern) {
			if pattern[px] == '*' {
				// Record the star and try to match the rest with it
				// consuming nothing. Consecutive stars collapse naturally:
				// the last one simply overwrites the mark.
				starPx, starNx = px, nx
				px++
				continue
			}
			if ok, next := matchOne(pattern, px, name[nx]); ok {
				px = next
				nx++
				continue
			}
		}
		if starPx < 0 {
			return false
		}
		starNx++
		px, nx = starPx+1, starNx
	}

	// name is exhausted; the pattern may only have stars left.
	for px < len(pattern) && pattern[px] == '*' {
		px++
	}
	return px == len(pattern)
}

// matchOne reports whether the single-byte pattern element at px matches b,
// and returns the index just past that element.
//
// The pattern is already known valid, which is why this can index past px
// without checking: Valid has established that an escape has a byte after it
// and a class has its closing bracket.
func matchOne(pattern string, px int, b byte) (bool, int) {
	switch pattern[px] {
	case '?':
		return true, px + 1
	case '\\':
		return pattern[px+1] == b, px + 2
	case '[':
		return matchClass(pattern, px, b)
	default:
		return pattern[px] == b, px + 1
	}
}

// matchClass evaluates the bracket expression starting at px against b and
// returns the index just past its closing bracket.
//
// There is no POSIX leading-`]` rule: a `]` inside a class is written `\]`.
// One way to say it beats two, and the one that survives is the one that also
// works for `-` and `\`.
func matchClass(pattern string, px int, b byte) (bool, int) {
	i := px + 1
	negated := false
	if pattern[i] == '!' || pattern[i] == '^' {
		negated = true
		i++
	}

	found := false
	for pattern[i] != ']' {
		lo := pattern[i]
		if lo == '\\' {
			i++
			lo = pattern[i]
		}
		i++

		// A '-' is a range only with something other than ']' after it, which
		// is what makes [a-] and [-a] literal dashes rather than errors.
		hi := lo
		if pattern[i] == '-' && pattern[i+1] != ']' {
			i++
			hi = pattern[i]
			if hi == '\\' {
				i++
				hi = pattern[i]
			}
			i++
		}

		if lo <= b && b <= hi {
			found = true
		}
	}
	return found != negated, i + 1
}

// splitName splits a subject on [Separator]. A name carries no pattern syntax,
// so there is nothing to protect and a plain split is right.
func splitName(name string) []string {
	return strings.Split(name, string(Separator))
}

// splitPattern splits a pattern on every [Separator] that is not escaped and
// not inside a character class.
//
// A plain strings.Split is wrong here, and wrong by aborting rather than by
// answering: it cuts `a\/b` into `a\` and `b`, handing matchBytes a segment
// whose trailing backslash has nothing after it, and `[/]` into `[` and `]`,
// handing matchClass a bracket with no closing one. Both then index past the
// end of the piece they were given, out of a Render that cannot be redeployed.
// Splitting with the escape and the class in mind keeps every pattern element
// whole, so each segment is itself a valid pattern.
//
// The resulting segment can still never match, since a name segment cannot
// contain a separator. That is the correct answer and this returns it.
func splitPattern(pattern string) []string {
	segs := []string{}
	start := 0
	inClass := false
	for i := 0; i < len(pattern); i++ {
		switch pattern[i] {
		case '\\':
			// Valid has established there is a byte after it.
			i++
		case '[':
			inClass = true
		case ']':
			inClass = false
		case Separator:
			if inClass {
				continue
			}
			segs = append(segs, pattern[start:i])
			start = i + 1
		}
	}
	return append(segs, pattern[start:])
}

// matchSegments is matchBytes one level up: the same single-backtrack walk,
// with `**` for the star and a whole segment for the byte.
//
// Writing it twice rather than generalising is the cheaper of the two: the
// element test differs (a byte equality against a glob call), the alphabet
// differs, and the shared version would take a comparison function and be
// longer than both. What the duplication buys is that the zero-segment case,
// `a/**/b` matching `a/b`, falls out of the algorithm instead of needing the
// special case a segment-by-segment walk requires.
func matchSegments(psegs, nsegs []string) bool {
	pi, ni := 0, 0
	starPi, starNi := -1, -1

	for ni < len(nsegs) {
		if pi < len(psegs) {
			if psegs[pi] == "**" {
				starPi, starNi = pi, ni
				pi++
				continue
			}
			if matchBytes(psegs[pi], nsegs[ni]) {
				pi++
				ni++
				continue
			}
		}
		if starPi < 0 {
			return false
		}
		starNi++
		pi, ni = starPi+1, starNi
	}

	for pi < len(psegs) && psegs[pi] == "**" {
		pi++
	}
	return pi == len(psegs)
}
