package wiki

import (
	"testing"

	"gno.land/p/nt/markdown/sanitize/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestScanLinks(t *testing.T) {
	cases := []struct {
		name      string
		in        string
		targets   []string
		labels    []string
		explicits []bool
	}{
		{"none", "plain text", nil, nil, nil},
		{"one", "see [[Gno land]] here", []string{"Gno land"}, []string{""}, []bool{false}},
		{"labelled", "[[Gno land|the chain]]", []string{"Gno land"}, []string{"the chain"}, []bool{false}},
		{"two", "[[A]] and [[B]]", []string{"A", "B"}, []string{"", ""}, []bool{false, false}},
		{"category", "[[Category:Chains]]", []string{"Category:Chains"}, []string{""}, []bool{false}},
		{"explicit category", "[[:Category:Chains]]", []string{"Category:Chains"}, []string{""}, []bool{true}},
		{"whitespace is trimmed", "[[  A  |  b  ]]", []string{"A"}, []string{"b"}, []bool{false}},
		{"unclosed is not a link", "[[A", nil, nil, nil},
		{"empty is not a link", "[[]]", nil, nil, nil},
		{"newline inside is not a link", "[[A\nB]]", nil, nil, nil},
		{"nested opener wins", "[[a [[b]]", []string{"b"}, []string{""}, []bool{false}},
	}
	for _, tc := range cases {
		got := ScanLinks(tc.in, "[[", "]]")
		if !uassert.Equal(t, len(tc.targets), len(got), tc.name) {
			continue
		}
		for i, l := range got {
			uassert.Equal(t, tc.targets[i], l.Target, tc.name)
			uassert.Equal(t, tc.labels[i], l.Label, tc.name)
			uassert.Equal(t, tc.explicits[i], l.Explicit, tc.name)
		}
	}
}

func TestScanLinksOffsets(t *testing.T) {
	in := "see [[A]] end"
	got := ScanLinks(in, "[[", "]]")
	uassert.Equal(t, 1, len(got))
	uassert.Equal(t, "[[A]]", in[got[0].Start:got[0].End])
}

// TestScanLinksAfterSanitize is the reason ScanLinks takes its delimiters as
// parameters: the sanitizer escapes every "[", so the rendering pass has to
// look for a different byte sequence than the indexing pass.
func TestScanLinksAfterSanitize(t *testing.T) {
	escaped := sanitize.BlockRich("see [[Gno land|the chain]] here\n")
	uassert.Equal(t, 0, len(ScanLinks(escaped, "[[", "]]")),
		"the raw delimiters must find nothing in sanitized text")
	got := ScanLinks(escaped, `\[\[`, `\]\]`)
	uassert.Equal(t, 1, len(got))
	uassert.Equal(t, "Gno land", got[0].Target)
	uassert.Equal(t, "the chain", got[0].Label)
}

func TestRedirectTarget(t *testing.T) {
	cases := []struct{ in, want string }{
		{"#REDIRECT [[Gno land]]\n", "Gno land"},
		{"#redirect [[gno_land]]", "Gno land"},
		{"  #REDIRECT   [[User:Gno land]]  \nrest", "User:Gno land"},
		{"not a redirect [[Gno land]]", ""},
		{"#REDIRECT no link", ""},
		{"#REDIRECT [[bad|title]]", "Bad"},
		{"text\n#REDIRECT [[Gno land]]", ""},
		{"", ""},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, redirectTarget(tc.in), tc.in)
	}
}

func TestRewriteLinks(t *testing.T) {
	c := Ctx{
		Base:   "/r/moul/x/wiki/v0",
		Exists: func(tt Title) bool { return tt.Name == "Gno land" },
	}

	body := sanitize.BlockRich("See [[Gno land]], [[Missing page]] and [[Gno land|the chain]].\n" +
		"[[Category:Chains]]\n")
	got := RewriteLinks(c, body)

	uassert.True(t, contains(got, "[Gno land](/r/moul/x/wiki/v0:Gno_land)"), "existing page links plainly")
	uassert.True(t, contains(got, "[Missing page](/r/moul/x/wiki/v0:Missing_page) ⁺"), "a redlink is marked")
	uassert.True(t, contains(got, "[the chain](/r/moul/x/wiki/v0:Gno_land)"), "labels are honored")
	uassert.False(t, contains(got, "Category:Chains"), "category declarations leave the flow")
}

func TestRewriteLinksEscapesURLs(t *testing.T) {
	c := Ctx{Base: "/r/moul/x/wiki/v0"}
	got := RewriteLinks(c, sanitize.BlockRich("[[Mercury (planet)]]\n"))
	// An unescaped ")" would terminate the markdown destination early and
	// leave "planet))" as visible text.
	uassert.True(t, contains(got, "(/r/moul/x/wiki/v0:Mercury_%28planet%29)"), got)
}

func TestRewriteLinksLeavesNonTitlesAlone(t *testing.T) {
	c := Ctx{Base: "/r/moul/x/wiki/v0"}
	// "[[ ]]" has no usable target, and "[[a/b]]" is not a legal title: both
	// must render as the literal text the author typed, never as a link.
	got := RewriteLinks(c, sanitize.BlockRich("[[a/b]]\n"))
	uassert.True(t, contains(got, `\[\[a/b\]\]`), got)
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
