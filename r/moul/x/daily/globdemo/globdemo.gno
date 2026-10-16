// Package globdemo is a gnoweb demo of the shell-pattern matcher provided by
// the [p/moul/x/daily/glob](/p/moul/x/daily/glob/v0) library: the grammar, the
// two matching modes, and the allowlist the package exists for.
//
// It contains no matching logic of its own. Stateless, so Render is
// deterministic: every verdict below is computed by the library from the fixed
// tables at the top of this file, never from chain state, which is what lets
// an example test pin the page.
package globdemo

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/glob/v0"
)

// grammar is the token table, each row paired with a subject that exercises it.
var grammar = []struct {
	token   string
	meaning string
	pattern string
	subject string
}{
	{"`?`", "any single byte", "a?c", "abc"},
	{"`*`", "any run of bytes, including none", "a*c", "abbbc"},
	{"`[abc]`", "any one of the listed bytes", "[abc]x", "bx"},
	{"`[a-z]`", "any byte in the range, ends included", "[a-z]1", "q1"},
	{"`[!a-z]`", "any byte NOT listed", "[!a-z]1", "Q1"},
	{"`\\*`", "the literal byte after the backslash", `a\*c`, "a*c"},
}

// modes is the pair of subjects that separate the two modes. Each row is run
// through both matchers, and the two columns disagree on purpose.
var modes = []struct {
	pattern string
	subject string
}{
	{"gno.land/*", "gno.land/home"},
	{"gno.land/*", "gno.land/r/moul/home"},
	{"gno.land/**", "gno.land/r/moul/home"},
	{"*/home", "gno.land/r/moul/home"},
	{"**/home", "gno.land/r/moul/home"},
}

// allow is the worked allowlist: what a realm would store to decide which
// package paths a delegated key may call.
var allow = []string{
	"gno.land/r/moul/home",
	"gno.land/r/moul/x/daily/**",
}

// subjects are the paths the allowlist is asked about. The last two are the
// point of the whole table: both pass a naive strings.HasPrefix check against
// the rules above, and neither is inside them.
var subjects = []string{
	"gno.land/r/moul/home",
	"gno.land/r/moul/x/daily/globdemo",
	"gno.land/r/moul/x/daily/glob/deeper",
	"gno.land/r/moul/blog",
	"gno.land/r/moul/homeless",
	"gno.land/r/moul/x/dailyevil/drain",
}

// patterns is the validity table: three well-formed, three typos.
var patterns = []string{
	"gno.land/r/moul/**",
	"[a-z0-9]*",
	`a\*b`,
	"[a-z",
	"[]",
	`abc\`,
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Glob\n\n")
	b.WriteString("Shell-style pattern matching, demoing the ")
	b.WriteString("[`p/moul/x/daily/glob`](/p/moul/x/daily/glob/v0) library. ")
	b.WriteString("Two modes: `Match`, where `*` crosses everything, and ")
	b.WriteString("`MatchPath`, where `/` is a boundary only `**` crosses.\n\n")

	b.WriteString("## The grammar\n\n")
	gt := ui.NewTable("token", "matches", "pattern", "subject", "Match")
	for _, g := range grammar {
		gt.Row(g.token, g.meaning, code(g.pattern), code(g.subject),
			verdict(glob.Match(g.pattern, g.subject)))
	}
	b.WriteString(gt.String() + "\n")
	b.WriteString("Matching is by byte, not by rune. `?` matches one byte, so ")
	b.WriteString("it takes two of them to cover a single `é`, and a class ")
	b.WriteString("range compares byte values. The subjects this package is ")
	b.WriteString("for, package paths and bech32 addresses, are ASCII.\n\n")

	b.WriteString("## The two modes\n\n")
	mt := ui.NewTable("pattern", "subject", "Match", "MatchPath")
	for _, m := range modes {
		mt.Row(code(m.pattern), code(m.subject),
			verdict(glob.Match(m.pattern, m.subject)),
			verdict(glob.MatchPath(m.pattern, m.subject)))
	}
	b.WriteString(mt.String() + "\n")
	b.WriteString("`*` and `?` and a class stay inside one segment under ")
	b.WriteString("`MatchPath`. A `**` that is a whole segment crosses as many ")
	b.WriteString("segments as it needs, including none, so `a/**/b` matches ")
	b.WriteString("`a/b`.\n\n")

	b.WriteString("## The allowlist\n\n")
	b.WriteString("The reason the package exists. Two rules, six candidate ")
	b.WriteString("paths, one boolean each:\n\n")
	at := ui.NewTable("rule", "kind")
	at.Row(code(allow[0]), "one exact path")
	at.Row(code(allow[1]), "that subtree, any depth")
	b.WriteString(at.String() + "\n")
	st := ui.NewTable("candidate path", "AnyPath", "HasPrefix")
	for _, s := range subjects {
		st.Row(code(s), verdict(glob.AnyPath(allow, s)), verdict(naivePrefix(s)))
	}
	b.WriteString(st.String() + "\n")
	b.WriteString("The last two rows are the whole argument. ")
	b.WriteString("`gno.land/r/moul/homeless` and ")
	b.WriteString("`gno.land/r/moul/x/dailyevil/drain` both pass a ")
	b.WriteString("`strings.HasPrefix` check against those rules, and neither ")
	b.WriteString("is inside them: a prefix has no idea where a path segment ")
	b.WriteString("ends. Registering a sibling name one byte longer than an ")
	b.WriteString("allowed one is a cheap attack, and the only fix is a ")
	b.WriteString("matcher that knows the separator.\n\n")

	b.WriteString("## Valid, and what happens when it is not\n\n")
	vt := ui.NewTable("pattern", "Valid", "Match against `gno.land/r/moul/home`")
	for _, p := range patterns {
		vt.Row(code(p), verdict(glob.Valid(p)), verdict(glob.MatchPath(p, allow[0])))
	}
	b.WriteString(vt.String() + "\n")
	b.WriteString("`Match` has no error return, so a malformed pattern has to ")
	b.WriteString("be either inert or permissive. It is inert: an allowlist ")
	b.WriteString("entry with a typo grants nothing instead of granting ")
	b.WriteString("everything. `Any` skips a bad entry and keeps evaluating ")
	b.WriteString("the good ones, so one typo costs one rule.\n\n")

	b.WriteString("## Why the matcher is a loop\n\n")
	b.WriteString("The recursive matcher every glob tutorial shows branches at ")
	b.WriteString("each `*` and is exponential in the number of them. This one ")
	b.WriteString("walks forward and remembers a single backtrack point, the ")
	b.WriteString("most recent star, which is `O(len(pattern) * len(name))` in ")
	b.WriteString("time and constant in space.\n\n")
	bt := ui.NewTable("pattern", "subject", "MatchPath")
	for _, s := range []string{
		"aaaaaaaaaaaaaaaaaaaaaaaa",
		"aaaaaaaaaaaaaaaaaaaaaaab",
	} {
		bt.Row(code(bomb), code(s), verdict(glob.MatchPath(bomb, s)))
	}
	b.WriteString(bt.String() + "\n")
	b.WriteString("Six stars against twenty-four bytes is where the recursive ")
	b.WriteString("version stops returning. On chain that is not a slow page, ")
	b.WriteString("it is a gas bomb a caller gets to aim, because the pattern ")
	b.WriteString("is usually the thing stored and the subject is usually the ")
	b.WriteString("thing supplied.\n")

	return b.String()
}

// bomb is the pattern that makes a recursive matcher blow up. Kept as a
// constant so the two rows of the last table cannot drift apart.
const bomb = "a*a*a*a*a*a*b"

// naivePrefix is the wrong implementation, kept so the page can show it being
// wrong rather than assert it. It is what an allowlist looks like before
// somebody notices that a prefix does not know where a segment ends.
func naivePrefix(path string) bool {
	for _, rule := range allow {
		if strings.HasPrefix(path, strings.TrimSuffix(rule, "/**")) {
			return true
		}
	}
	return false
}

// verdict renders a boolean as a symbol, so a column of them reads at a glance.
func verdict(ok bool) string {
	if ok {
		return "yes"
	}
	return "no"
}

// code wraps s in a markdown code span.
//
// A pipe is escaped rather than passed to ui.Cell: inside a code span
// CommonMark performs no backslash escapes, so ui.Cell's output would render
// its own backslashes literally. Nothing on this page contains a pipe today,
// and the escape is here so that adding a pattern with one does not silently
// open a column.
func code(s string) string {
	return "`" + strings.ReplaceAll(s, "|", `\|`) + "`"
}
