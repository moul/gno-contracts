package bwtdemo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// TestParseArgDoesNotTrim pins that the routing slash is the only thing
// removed. The transform is byte-preserving, so trimming would show the
// caller the result of transforming a string they never sent, and a path of
// nothing but spaces would be mistaken for the root page.
func TestParseArgDoesNotTrim(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"", ""},
		{"/", ""},
		{"/ab", "ab"},
		{"/ ab ", " ab "},
		{"/ ", " "},
		{"/a/b", "a/b"},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, parseArg(tc.in))
	}
}

// TestRenderKeepsCallerWhitespace pins the same thing one level up: the page
// echoes the bytes it was handed, spaces included, and a path of one space is
// an input rather than the root page.
func TestRenderKeepsCallerWhitespace(t *testing.T) {
	// md.InlineCode pads the span with one extra space on each side, which is
	// how CommonMark keeps a code span's own leading and trailing spaces.
	got := Render("/ ab ")
	uassert.True(t, strings.Contains(got, "Input: `  ab  `"), "the echoed input kept its spaces")

	space := Render("/ ")
	uassert.True(t, strings.Contains(space, "Input:"), "a path of one space is an input, not the root page")
	uassert.False(t, strings.Contains(space, "What the clustering is worth"), "the root page was rendered instead")
}
