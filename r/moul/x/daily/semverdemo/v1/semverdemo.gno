// Package semverdemo is a small on-chain demo of the semantic-versioning
// parser/comparator provided by the
// [p/moul/x/daily/semver](/p/moul/x/daily/semver/v1) library.
//
// It holds the realm state the pure library deliberately does not: a
// "submitted versions" board (an avl tree of version string -> submitter
// address) that anyone can post to with [Submit], plus a gnoweb [Render] view
// that lists them in SemVer precedence order and compares arbitrary pairs. All
// parsing and comparison math lives in the library; this realm is just the
// on-chain wiring and the view.
package semverdemo

import (
	"sort"
	"strconv"
	"strings"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/moul/x/daily/semver/v1"
	"gno.land/p/nt/avl/v0"
)

// submitted holds versions users have posted on-chain: version string -> submitter.
var submitted = avl.NewTree()

// Submit stores a valid version on-chain, tagged with the caller's address, so
// Render("/sorted") can list everyone's submissions in precedence order. It
// validates the input with [semver.Parse] and panics on anything malformed.
func Submit(cur realm, version string) {
	if _, err := semver.Parse(version); err != nil {
		panic("invalid semantic version: " + version)
	}
	who := unsafe.PreviousRealm().Address()
	submitted.Set(version, who.String())
	chain.Emit("VersionSubmitted", "version", version, "by", who.String())
}

// ---- Render ----------------------------------------------------------------

func Render(path string) string {
	path = strings.TrimPrefix(path, "/")
	switch {
	case path == "":
		return renderHome()
	case path == "sorted":
		return renderSorted()
	default:
		parts := strings.SplitN(path, "/", 2)
		if len(parts) != 2 {
			return renderHome()
		}
		return renderCompare(parts[0], parts[1])
	}
}

func renderHome() string {
	var b strings.Builder
	b.WriteString("# semver — Semantic Versioning on-chain\n\n")
	b.WriteString("Demo of the [`p/moul/x/daily/semver`](/p/moul/x/daily/semver/v1) ")
	b.WriteString("library — a port of `golang.org/x/mod/semver`. Parse ")
	b.WriteString("`vMAJOR.MINOR.PATCH[-prerelease][+build]` and compare with ")
	b.WriteString("SemVer 2.0.0 precedence.\n\n")

	b.WriteString("## Examples\n\n")
	b.WriteString("| a | rel | b | note |\n|---|:---:|---|---|\n")
	examples := [][2]string{
		{"1.2.3", "1.2.10"},
		{"1.0.0-alpha", "1.0.0"},
		{"1.0.0-alpha.1", "1.0.0-alpha.beta"},
		{"1.0.0-rc.1", "1.0.0"},
		{"2.0.0", "2.0.0+build.5"},
	}
	notes := []string{
		"numeric patch, not lexical",
		"pre-release < release",
		"numeric id < alphanumeric id",
		"release candidate < final",
		"build metadata ignored",
	}
	for i, ex := range examples {
		b.WriteString("| `" + ex[0] + "` | " + relSym(semver.Compare(ex[0], ex[1])) +
			" | `" + ex[1] + "` | " + notes[i] + " |\n")
	}

	b.WriteString("\n## Try it\n\n")
	b.WriteString("- Compare two versions: [`/1.2.3/1.2.10`](/r/moul/x/daily/semverdemo/v1:1.2.3/1.2.10)\n")
	b.WriteString("- Submitted list: [`/sorted`](/r/moul/x/daily/semverdemo/v1:sorted)\n")
	b.WriteString("- Submit on-chain: `Submit(\"v1.4.2\")`\n")
	return b.String()
}

func renderCompare(a, b string) string {
	var sb strings.Builder
	sb.WriteString("# Compare\n\n")
	sb.WriteString(describe("A", a))
	sb.WriteString(describe("B", b))

	_, ea := semver.Parse(a)
	_, eb := semver.Parse(b)
	if ea != nil || eb != nil {
		sb.WriteString("\n> One or both inputs are not valid semver.\n")
		return sb.String()
	}
	c := semver.Compare(a, b)
	sb.WriteString("\n## Result\n\n")
	sb.WriteString("`" + a + "` **" + word(c) + "** `" + b + "`  ")
	sb.WriteString("→ `Compare = " + strconv.Itoa(c) + "`\n")
	return sb.String()
}

func describe(label, s string) string {
	v, err := semver.Parse(s)
	if err != nil {
		return "## " + label + ": `" + s + "`\n\n> invalid\n\n"
	}
	pre := "—"
	if len(v.Pre) > 0 {
		pre = "`" + strings.Join(v.Pre, ".") + "`"
	}
	build := "—"
	if v.Build != "" {
		build = "`" + v.Build + "`"
	}
	return "## " + label + ": `" + v.Canonical() + "`\n\n" +
		"| major | minor | patch | pre | build |\n|---|---|---|---|---|\n" +
		"| " + strconv.Itoa(v.Major) + " | " + strconv.Itoa(v.Minor) + " | " + strconv.Itoa(v.Patch) +
		" | " + pre + " | " + build + " |\n\n"
}

func renderSorted() string {
	var es []entry
	// Capture the submitter straight from Iterate's callback value, avoiding a
	// separate avl.Get whose arity differs across gno versions.
	submitted.Iterate("", "", func(key string, value any) bool {
		if v, err := semver.Parse(key); err == nil {
			who, _ := value.(string)
			es = append(es, entry{v: v, who: who})
		}
		return false
	})
	if len(es) == 0 {
		return "# Submitted versions\n\n_None yet._ Call `Submit(\"v1.0.0\")` to add one.\n"
	}
	sort.Stable(byPrecedence(es))

	var b strings.Builder
	b.WriteString("# Submitted versions (lowest → highest)\n\n")
	b.WriteString("| # | version | submitter |\n|---|---|---|\n")
	for i, e := range es {
		b.WriteString("| " + strconv.Itoa(i+1) + " | `" + e.v.Canonical() + "` | `" + e.who + "` |\n")
	}
	return b.String()
}

// entry pairs a parsed version with the address that submitted it.
type entry struct {
	v   semver.Version
	who string
}

// byPrecedence sorts entries ascending. `sort` on-chain has no Slice helper,
// so we implement sort.Interface; ordering defers to semver.Compare on the
// original strings.
type byPrecedence []entry

func (p byPrecedence) Len() int { return len(p) }
func (p byPrecedence) Less(i, j int) bool {
	return semver.Compare(p[i].v.Orig, p[j].v.Orig) < 0
}
func (p byPrecedence) Swap(i, j int) { p[i], p[j] = p[j], p[i] }

func relSym(c int) string {
	switch {
	case c < 0:
		return "&lt;"
	case c > 0:
		return "&gt;"
	}
	return "="
}

func word(c int) string {
	switch {
	case c < 0:
		return "<"
	case c > 0:
		return ">"
	}
	return "=="
}
