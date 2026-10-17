package globdemo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand
// typed: every verdict in it is computed by the library under test, so a
// change in the matcher shows up here as a diff rather than as prose.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Glob
	//
	// Shell-style pattern matching, demoing the [`p/moul/x/daily/glob`](/p/moul/x/daily/glob/v0) library. Two modes: `Match`, where `*` crosses everything, and `MatchPath`, where `/` is a boundary only `**` crosses.
	//
	// ## The grammar
	//
	// | token | matches | pattern | subject | Match |
	// | --- | --- | --- | --- | --- |
	// | `?` | any single byte | `a?c` | `abc` | yes |
	// | `*` | any run of bytes, including none | `a*c` | `abbbc` | yes |
	// | `[abc]` | any one of the listed bytes | `[abc]x` | `bx` | yes |
	// | `[a-z]` | any byte in the range, ends included | `[a-z]1` | `q1` | yes |
	// | `[!a-z]` | any byte NOT listed | `[!a-z]1` | `Q1` | yes |
	// | `\*` | the literal byte after the backslash | `a\*c` | `a*c` | yes |
	//
	// Matching is by byte, not by rune. `?` matches one byte, so it takes two of them to cover a single `é`, and a class range compares byte values. The subjects this package is for, package paths and bech32 addresses, are ASCII.
	//
	// ## The two modes
	//
	// | pattern | subject | Match | MatchPath |
	// | --- | --- | --- | --- |
	// | `gno.land/*` | `gno.land/home` | yes | yes |
	// | `gno.land/*` | `gno.land/r/moul/home` | yes | no |
	// | `gno.land/**` | `gno.land/r/moul/home` | yes | yes |
	// | `*/home` | `gno.land/r/moul/home` | yes | no |
	// | `**/home` | `gno.land/r/moul/home` | yes | yes |
	//
	// `*` and `?` and a class stay inside one segment under `MatchPath`. A `**` that is a whole segment crosses as many segments as it needs, including none, so `a/**/b` matches `a/b`.
	//
	// ## The allowlist
	//
	// The reason the package exists. Two rules, six candidate paths, one boolean each:
	//
	// | rule | kind |
	// | --- | --- |
	// | `gno.land/r/moul/home` | one exact path |
	// | `gno.land/r/moul/x/daily/**` | that subtree, any depth |
	//
	// | candidate path | AnyPath | HasPrefix |
	// | --- | --- | --- |
	// | `gno.land/r/moul/home` | yes | yes |
	// | `gno.land/r/moul/x/daily/globdemo` | yes | yes |
	// | `gno.land/r/moul/x/daily/glob/deeper` | yes | yes |
	// | `gno.land/r/moul/blog` | no | no |
	// | `gno.land/r/moul/homeless` | no | yes |
	// | `gno.land/r/moul/x/dailyevil/drain` | no | yes |
	//
	// The last two rows are the whole argument. `gno.land/r/moul/homeless` and `gno.land/r/moul/x/dailyevil/drain` both pass a `strings.HasPrefix` check against those rules, and neither is inside them: a prefix has no idea where a path segment ends. Registering a sibling name one byte longer than an allowed one is a cheap attack, and the only fix is a matcher that knows the separator.
	//
	// ## Valid, and what happens when it is not
	//
	// | pattern | Valid | Match against `gno.land/r/moul/home` |
	// | --- | --- | --- |
	// | `gno.land/r/moul/**` | yes | yes |
	// | `[a-z0-9]*` | yes | no |
	// | `a\*b` | yes | no |
	// | `[a-z` | no | no |
	// | `[]` | no | no |
	// | `abc\` | no | no |
	//
	// `Match` has no error return, so a malformed pattern has to be either inert or permissive. It is inert: an allowlist entry with a typo grants nothing instead of granting everything. `Any` skips a bad entry and keeps evaluating the good ones, so one typo costs one rule.
	//
	// ## Why the matcher is a loop
	//
	// The recursive matcher every glob tutorial shows branches at each `*` and is exponential in the number of them. This one walks forward and remembers a single backtrack point, the most recent star, which is `O(len(pattern) * len(name))` in time and constant in space.
	//
	// | pattern | subject | MatchPath |
	// | --- | --- | --- |
	// | `a*a*a*a*a*a*b` | `aaaaaaaaaaaaaaaaaaaaaaaa` | no |
	// | `a*a*a*a*a*a*b` | `aaaaaaaaaaaaaaaaaaaaaaab` | yes |
	//
	// Six stars against twenty-four bytes is where the recursive version stops returning. On chain that is not a slow page, it is a gas bomb a caller gets to aim, because the pattern is usually the thing stored and the subject is usually the thing supplied.
}
