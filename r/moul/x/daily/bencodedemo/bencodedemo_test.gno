package bencodedemo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// TestRenderRefusesOversizedInput pins the page's own limit, which is tighter
// than the library's: a Render runs under the chain's query gas meter and
// gnoweb does not bound a render argument.
func TestRenderRefusesOversizedInput(t *testing.T) {
	big := "l" + strings.Repeat("1:a", (MaxInput-2)/3) + "e"
	uassert.True(t, len(big) <= MaxInput, "the control input must be accepted")
	got := Render("/" + big)
	uassert.True(t, strings.Contains(got, "- list, "), "a legal input still decodes")

	over := "l" + strings.Repeat("1:a", MaxInput) + "e"
	got = Render("/" + over)
	uassert.True(t, strings.Contains(got, "This page decodes at most 512."),
		"an oversized input is refused by length, before decoding")
	uassert.False(t, strings.Contains(got, "- list, "), "and nothing is decoded")
}

// TestRenderEscapesCallerMarkdown pins the escaping, which a pinned example
// cannot show convincingly: the input there would have to be hostile.
func TestRenderEscapesCallerMarkdown(t *testing.T) {
	// 10 bytes, not 9: a wrong length is rejected before the decoded leaf is
	// ever rendered, and the test would then only cover the echoed heading.
	got := Render("/d3:cow10:[x](/evil)e")
	uassert.False(t, strings.Contains(got, "Rejected"), "the input must decode")
	uassert.False(t, strings.Contains(got, "[x](/evil)"), "the link must not survive")
	uassert.True(t, strings.Contains(got, "**cow**: string "), "the decoded leaf is rendered")
	uassert.Equal(t, 3, strings.Count(got, `\[x\]`), "escaped in the heading, the leaf and the re-encoding")
}

// TestRenderKeepsCallerBytes pins that the page does not trim the value it was
// handed: a trailing space is part of a six byte string, not routing noise.
func TestRenderKeepsCallerBytes(t *testing.T) {
	got := Render("/6:hello ")
	uassert.True(t, strings.Contains(got, "string hello"), "the space-bearing string decodes")
	uassert.False(t, strings.Contains(got, "Rejected"), "and is not rejected")
}
