// Package semver is an on-chain port of the core of golang.org/x/mod/semver
// (and the spirit of github.com/Masterminds/semver): parse "vMAJOR.MINOR.PATCH
// [-prerelease][+build]" strings and compare them with correct Semantic
// Versioning 2.0.0 precedence. Pure and deterministic — no time, randomness,
// goroutines, or I/O.
package semver

import (
	"chain"
	"chain/runtime/unsafe"
	"errors"
	"sort"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// Version is a parsed semantic version. Build metadata is retained for display
// but, per the spec, is ignored when comparing precedence.
type Version struct {
	Major, Minor, Patch int
	Pre                 []string // pre-release identifiers (dot-separated)
	Build               string   // build metadata (after '+')
	Orig                string   // original input
}

var errBadVersion = errors.New("invalid semantic version")

// submitted holds versions users have posted on-chain: version string -> submitter.
var submitted = avl.NewTree()

// Parse reads "vMAJOR.MINOR.PATCH[-prerelease][+build]". The leading 'v' is
// optional. Numeric fields must be non-empty digit runs without leading zeros.
func Parse(s string) (Version, error) {
	v := Version{Orig: s}
	body := strings.TrimPrefix(s, "v")

	if i := strings.IndexByte(body, '+'); i >= 0 {
		v.Build = body[i+1:]
		body = body[:i]
		if v.Build == "" {
			return Version{}, errBadVersion
		}
	}
	if i := strings.IndexByte(body, '-'); i >= 0 {
		pre := body[i+1:]
		body = body[:i]
		v.Pre = strings.Split(pre, ".")
		for _, id := range v.Pre {
			if !validPreIdent(id) {
				return Version{}, errBadVersion
			}
		}
	}

	parts := strings.Split(body, ".")
	if len(parts) != 3 {
		return Version{}, errBadVersion
	}
	nums := [3]int{}
	for i, p := range parts {
		n, ok := parseNum(p)
		if !ok {
			return Version{}, errBadVersion
		}
		nums[i] = n
	}
	v.Major, v.Minor, v.Patch = nums[0], nums[1], nums[2]
	return v, nil
}

// Compare returns -1, 0, or +1 as a < b, a == b, or a > b under semver
// precedence. Unparseable inputs sort after everything valid (and equal to
// each other), so Compare never panics.
func Compare(a, b string) int {
	va, ea := Parse(a)
	vb, eb := Parse(b)
	switch {
	case ea != nil && eb != nil:
		return 0
	case ea != nil:
		return 1
	case eb != nil:
		return -1
	}
	return va.compare(vb)
}

func (v Version) compare(o Version) int {
	if c := cmpInt(v.Major, o.Major); c != 0 {
		return c
	}
	if c := cmpInt(v.Minor, o.Minor); c != 0 {
		return c
	}
	if c := cmpInt(v.Patch, o.Patch); c != 0 {
		return c
	}
	return comparePre(v.Pre, o.Pre)
}

// comparePre implements SemVer §11: a version WITH a pre-release has lower
// precedence than the same version WITHOUT one.
func comparePre(a, b []string) int {
	if len(a) == 0 && len(b) == 0 {
		return 0
	}
	if len(a) == 0 { // a is a release, b is a pre-release
		return 1
	}
	if len(b) == 0 {
		return -1
	}
	for i := 0; i < len(a) && i < len(b); i++ {
		if c := compareIdent(a[i], b[i]); c != 0 {
			return c
		}
	}
	return cmpInt(len(a), len(b))
}

// compareIdent: numeric identifiers compare numerically and always rank below
// alphanumeric ones; alphanumerics compare in ASCII order.
func compareIdent(a, b string) int {
	an, aNum := parseNum(a)
	bn, bNum := parseNum(b)
	switch {
	case aNum && bNum:
		return cmpInt(an, bn)
	case aNum:
		return -1
	case bNum:
		return 1
	}
	return strings.Compare(a, b)
}

func cmpInt(a, b int) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

// parseNum accepts a non-empty run of ASCII digits with no leading zero (except
// "0" itself), returning the value and whether it qualified.
func parseNum(s string) (int, bool) {
	if s == "" {
		return 0, false
	}
	if len(s) > 1 && s[0] == '0' {
		return 0, false
	}
	n := 0
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n*10 + int(c-'0')
	}
	return n, true
}

// validPreIdent allows [0-9A-Za-z-] and rejects empty identifiers.
func validPreIdent(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		ok := (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
			(c >= 'A' && c <= 'Z') || c == '-'
		if !ok {
			return false
		}
	}
	return true
}

// Canonical renders the parsed version back to a canonical string.
func (v Version) Canonical() string {
	s := ufmt(v.Major) + "." + ufmt(v.Minor) + "." + ufmt(v.Patch)
	if len(v.Pre) > 0 {
		s += "-" + strings.Join(v.Pre, ".")
	}
	if v.Build != "" {
		s += "+" + v.Build
	}
	return s
}

func ufmt(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}

// Submit stores a valid version on-chain, tagged with the caller's address, so
// Render("/sorted") can list everyone's submissions in precedence order.
func Submit(cur realm, version string) {
	if _, err := Parse(version); err != nil {
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
	b.WriteString("A port of `golang.org/x/mod/semver`. Parse ")
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
		b.WriteString("| `" + ex[0] + "` | " + relSym(Compare(ex[0], ex[1])) +
			" | `" + ex[1] + "` | " + notes[i] + " |\n")
	}

	b.WriteString("\n## Try it\n\n")
	b.WriteString("- Compare two versions: [`/1.2.3/1.2.10`](/r/moul/x/daily/semver:1.2.3/1.2.10)\n")
	b.WriteString("- Submitted list: [`/sorted`](/r/moul/x/daily/semver:sorted)\n")
	b.WriteString("- Submit on-chain: `Submit(\"v1.4.2\")`\n")
	return b.String()
}

func renderCompare(a, b string) string {
	var sb strings.Builder
	sb.WriteString("# Compare\n\n")
	sb.WriteString(describe("A", a))
	sb.WriteString(describe("B", b))

	va, ea := Parse(a)
	vb, eb := Parse(b)
	if ea != nil || eb != nil {
		sb.WriteString("\n> One or both inputs are not valid semver.\n")
		return sb.String()
	}
	c := va.compare(vb)
	sb.WriteString("\n## Result\n\n")
	sb.WriteString("`" + a + "` **" + word(c) + "** `" + b + "`  ")
	sb.WriteString("→ `Compare = " + ufmtSigned(c) + "`\n")
	return sb.String()
}

func describe(label, s string) string {
	v, err := Parse(s)
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
		"| " + ufmt(v.Major) + " | " + ufmt(v.Minor) + " | " + ufmt(v.Patch) +
		" | " + pre + " | " + build + " |\n\n"
}

func renderSorted() string {
	var es []entry
	// Capture the submitter straight from Iterate's callback value, avoiding a
	// separate avl.Get whose arity differs across gno versions.
	submitted.Iterate("", "", func(key string, value any) bool {
		if v, err := Parse(key); err == nil {
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
		b.WriteString("| " + ufmt(i+1) + " | `" + e.v.Canonical() + "` | `" + e.who + "` |\n")
	}
	return b.String()
}

// entry pairs a parsed version with the address that submitted it.
type entry struct {
	v   Version
	who string
}

// byPrecedence sorts entries ascending. `sort` on-chain has no Slice helper,
// so we implement sort.Interface.
type byPrecedence []entry

func (p byPrecedence) Len() int           { return len(p) }
func (p byPrecedence) Less(i, j int) bool { return p[i].v.compare(p[j].v) < 0 }
func (p byPrecedence) Swap(i, j int)      { p[i], p[j] = p[j], p[i] }

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

func ufmtSigned(c int) string {
	if c < 0 {
		return "-1"
	}
	return ufmt(c)
}
