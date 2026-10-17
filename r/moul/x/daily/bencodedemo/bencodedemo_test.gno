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
	got := Render("/d3:cow9:[x](/evil)e")
	uassert.False(t, strings.Contains(got, "[x](/evil)"), "the link must not survive")
	uassert.True(t, strings.Contains(got, `\[x\]`), "it is escaped instead")
}
