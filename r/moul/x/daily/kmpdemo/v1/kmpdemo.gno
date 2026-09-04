// Package kmpdemo is a small gnoweb demo of the Knuth–Morris–Pratt substring
// search provided by the [p/moul/x/daily/kmp](/p/moul/x/daily/kmp/v1) library:
// it shows the failure table and overlapping matches.
//
// It contains no search logic of its own. Stateless, so Render is
// deterministic — which is precisely what the library is for.
package kmpdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/kmp/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Knuth–Morris–Pratt\n\n")
	b.WriteString("Linear-time substring search, demoing the ")
	b.WriteString("[`p/moul/x/daily/kmp`](/p/moul/x/daily/kmp/v1) library.\n\n")

	const text = "mississippi"
	const pattern = "issi"

	b.WriteString("## Failure table\n\n")
	b.WriteString("For each prefix of `" + pattern + "`, the length of the longest proper ")
	b.WriteString("prefix that is also a suffix. This is what lets the scan slide the ")
	b.WriteString("pattern without ever rewinding the text.\n\n")
	b.WriteString("| i | prefix | table |\n|---|---|---|\n")
	for i, v := range kmp.Table(pattern) {
		b.WriteString("| " + strconv.Itoa(i) + " | `" + pattern[:i+1] + "` | " + strconv.Itoa(v) + " |\n")
	}

	b.WriteString("\n## Searching\n\n")
	b.WriteString("`" + pattern + "` in `" + text + "`:\n\n")
	b.WriteString("```\n" + text + "\n")
	hits := kmp.FindAll(text, pattern)
	for _, at := range hits {
		b.WriteString(strings.Repeat(" ", at) + strings.Repeat("^", len(pattern)) + "\n")
	}
	b.WriteString("```\n\n")
	b.WriteString("Matches at " + offsets(hits) + " — **overlapping**, and `Count` agrees: ")
	b.WriteString(strconv.Itoa(kmp.Count(text, pattern)) + ".\n\n")

	b.WriteString("## Overlap is deliberate\n\n")
	b.WriteString("`FindAll(\"aaaa\", \"aa\")` returns " + offsets(kmp.FindAll("aaaa", "aa")))
	b.WriteString(", not just the disjoint ones — \"every occurrence\" read honestly. ")
	b.WriteString("A caller wanting disjoint matches can filter; one wanting overlap ")
	b.WriteString("could not recover it.\n\n")

	b.WriteString("## Why it belongs on chain\n\n")
	b.WriteString("The naive scan is O(n·m): `")
	b.WriteString(strings.Repeat("a", 8) + "b` inside `" + strings.Repeat("a", 16))
	b.WriteString("b` re-compares everything it already matched. KMP is O(n+m) with no ")
	b.WriteString("bad case, so a pathological input is not an attack.\n")
	return b.String()
}

func offsets(xs []int) string {
	if len(xs) == 0 {
		return "_none_"
	}
	parts := make([]string, len(xs))
	for i, x := range xs {
		parts[i] = "`" + strconv.Itoa(x) + "`"
	}
	return strings.Join(parts, ", ")
}
