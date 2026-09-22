package ui

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestShortN(t *testing.T) {
	cases := []struct {
		name       string
		in         string
		head, tail int
		want       string
	}{
		{"empty", "", 8, 4, ""},
		{"shorter than the rule", "abc", 8, 4, "abc"},
		{"exactly at the threshold", "0123456789abc", 8, 4, "0123456789abc"},
		{"one over the threshold", "0123456789abcd", 8, 4, "01234567…abcd"},
		{"gno address", "g1manfred47kzduec920z88wfr64ylksmdcedlf5", 8, 4, "g1manfre…dlf5"},
		{"head only", "0123456789abcd", 6, 0, "012345…"},
		{"tail only", "0123456789abcd", 0, 4, "…abcd"},
		{"negative clamps to zero", "0123456789abcd", -3, -3, "…"},
		{"multibyte is not split", "éééééééééééééé", 2, 2, "éé…éé"},
	}
	for _, tc := range cases {
		got := ShortN(tc.in, tc.head, tc.tail)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

// ShortN must never make a string longer: that is the property the four
// divergent shortAddr implementations disagreed on.
func TestShortNeverGrows(t *testing.T) {
	inputs := []string{"", "a", "abcdefghijkl", "0123456789abc", "0123456789abcd", strings.Repeat("x", 100)}
	for _, in := range inputs {
		got := Short(in)
		uassert.True(t, len([]rune(got)) <= len([]rune(in)), "Short("+in+") grew the input")
	}
}

func TestAddr(t *testing.T) {
	a := testutils.TestAddress("alice")
	full := a.String()

	uassert.Equal(t, "`"+full+"`", AddrFull(a))
	uassert.Equal(t, Short(full), AddrText(a))
	uassert.Equal(t, "`"+Short(full)+"`", Addr(a))

	// The shortened form keeps the recognisable head and the distinguishing tail.
	uassert.True(t, strings.HasPrefix(AddrText(a), full[:Head]), "head is kept")
	uassert.True(t, strings.HasSuffix(AddrText(a), full[len(full)-Tail:]), "tail is kept")
	uassert.True(t, strings.Contains(AddrText(a), Ellipsis), "ellipsis is present")
}

// Two different addresses must not collide once shortened, or the display is
// worse than useless.
func TestAddrOf(t *testing.T) {
	a := testutils.TestAddress("alice")
	uassert.Equal(t, Addr(a), AddrOf(a.String()))
}

func TestAddrDistinguishes(t *testing.T) {
	seen := map[string]bool{}
	for _, name := range []string{"alice", "bob", "carol", "dave", "eve"} {
		s := AddrText(testutils.TestAddress(name))
		uassert.False(t, seen[s], "shortened address collision on "+name)
		seen[s] = true
	}
}

func TestInlineEscapes(t *testing.T) {
	// The seven pairs the hand-rolled escapeInline copies covered.
	for _, meta := range []string{"*", "_", "[", "]", "`", "\\"} {
		got := Inline("a" + meta + "b")
		uassert.True(t, strings.Contains(got, "\\"+meta), "Inline did not escape "+meta)
	}
	// And the one they all missed: a newline lets user text escape its line.
	uassert.False(t, strings.Contains(Inline("a\nb"), "\n"), "Inline must fold newlines")
}

func TestCellEscapesPipe(t *testing.T) {
	got := Cell("a|b")
	uassert.False(t, strings.Contains(got, " |"), "a bare pipe would open a new column")
	uassert.True(t, strings.Contains(got, "\\|"), "pipe must be escaped")
}

func TestEmpty(t *testing.T) {
	uassert.Equal(t, "*No games yet.*\n", Empty("No games yet."))
}

func TestPodium(t *testing.T) {
	cases := []struct {
		rank int
		want string
	}{
		{0, "\U0001F947"},
		{1, "\U0001F948"},
		{2, "\U0001F949"},
		{3, ""},
		{99, ""},
		{-1, ""},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, Podium(tc.rank))
	}
}

func TestTable(t *testing.T) {
	tbl := NewTable("#", "who", "score")
	uassert.Equal(t, 0, tbl.Len())
	uassert.Equal(t, "", tbl.String())
	uassert.Equal(t, "*nobody yet.*\n", tbl.OrEmpty("nobody yet."))

	tbl.Row("1", "`g1abc…wxyz`", "42").Row("2", "`g1def…uvwx`", "7")
	uassert.Equal(t, 2, tbl.Len())

	want := "| # | who | score |\n" +
		"| --- | --- | --- |\n" +
		"| 1 | `g1abc…wxyz` | 42 |\n" +
		"| 2 | `g1def…uvwx` | 7 |\n"
	uassert.Equal(t, want, tbl.String())
	uassert.Equal(t, want, tbl.OrEmpty("nobody yet."))
}

// A short row is padded rather than producing a table the renderer misreads.
func TestTableShortRowIsPadded(t *testing.T) {
	tbl := NewTable("a", "b", "c")
	tbl.Row("1")
	uassert.Equal(t, "| a | b | c |\n| --- | --- | --- |\n| 1 |  |  |\n", tbl.String())
}

// A cell escaped with Cell must survive Table untouched: stacking Cell on an
// escaper that also rewrites "|" produced "a\\&#124;b" in the guestbook port.
func TestTableDoesNotDoubleEscape(t *testing.T) {
	tbl := NewTable("msg")
	tbl.Row(Cell("a|b"))
	got := tbl.String()
	uassert.True(t, strings.Contains(got, `a\|b`), "expected the GFM pipe escape, got: "+got)
	uassert.False(t, strings.Contains(got, "&#124;"), "cell was escaped twice: "+got)
}

func TestJoin(t *testing.T) {
	uassert.Equal(t, "a\n\nb", Join("\n\n", "a", "", "b"))
	uassert.Equal(t, "", Join("\n\n", "", ""))
	uassert.Equal(t, "solo", Join("\n\n", "solo"))
}

// Action must produce a markdown link whose target carries the function name
// and the key/value arguments, and must escape the title (which helplink
// itself does not).
func TestAction(t *testing.T) {
	got := Action("Play cell 4", "Move", "gameID", "7", "cell", "4")
	uassert.True(t, strings.HasPrefix(got, "[Play cell 4]("), "expected a markdown link, got: "+got)
	uassert.True(t, strings.Contains(got, "Move"), "link must name the function")
	uassert.True(t, strings.Contains(got, "gameID=7"), "link must carry the args")
	uassert.True(t, strings.Contains(got, "cell=4"), "link must carry the args")

	esc := Action("a*b", "Fn")
	uassert.True(t, strings.HasPrefix(esc, "[a\\*b]("), "title must be escaped, got: "+esc)
}

func TestActionIn(t *testing.T) {
	got := ActionIn("gno.land/r/moul/gns/v0", "Say hi", "Hello", "name", "moul")
	uassert.True(t, strings.Contains(got, "/r/moul/gns/v0"), "must target the named realm, got: "+got)
	uassert.True(t, strings.Contains(got, "Hello"), "must name the function")
}

func TestExcerpt(t *testing.T) {
	cases := []struct {
		name  string
		in    string
		width int
		want  string
	}{
		{"empty", "", 10, ""},
		{"shorter than the width", "hello", 10, "hello"},
		{"one over is kept whole, as ShortN does", "0123456789a", 10, "0123456789a"},
		{"two over is cut", "0123456789ab", 10, "0123456789…"},
		{"zero width", "hello", 0, "…"},
		{"negative width clamps to zero", "hello", -3, "…"},
		// The cut counts runes. A byte slice at 10 would split the 11th 'é'
		// and put invalid UTF-8 on the page.
		{"multibyte is not split", strings.Repeat("é", 20), 10, strings.Repeat("é", 10) + "…"},
		// The escaping half: what is kept is escaped, the ellipsis is not.
		{"escapes what it keeps", "[link](url) and more", 11, "\\[link\\]\\(url\\)…"},
		{"newline cannot escape the line", "one\ntwo", 10, "one two"},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, Excerpt(tc.in, tc.width), tc.name)
	}
}

// Excerpt must never leave a trailing lone backslash: that is the bug that
// comes from escaping first and cutting second, and it escapes whatever the
// caller appends after the excerpt.
func TestExcerptNeverStrandsABackslash(t *testing.T) {
	// Each of these ends, at some width, on a character the escaper backslashes.
	for _, in := range []string{
		"....................", "********************", "[[[[[[[[[[[[[[[[[[[[",
		"!!!!!!!!!!!!!!!!!!!!", "<<<<<<<<<<<<<<<<<<<<", "--------------------",
	} {
		for width := 0; width <= 15; width++ {
			got := Excerpt(in, width)
			body := strings.TrimSuffix(got, Ellipsis)
			trailing := 0
			for i := len(body) - 1; i >= 0 && body[i] == '\\'; i-- {
				trailing++
			}
			uassert.Equal(t, 0, trailing%2, "odd run of trailing backslashes in Excerpt("+in+")")
		}
	}
}
