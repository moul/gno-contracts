package toolbox

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestIndex(t *testing.T) {
	var c Catalog
	uassert.NoError(t, c.Set(Tool{
		Slug:  "usernames",
		Path:  "gno.land/r/moul/toolbox/usernames",
		Title: "Usernames",
		Desc:  "resolve a username or an address",
		Tags:  []string{"identity", "read"},
	}))

	got := Index(c.List())
	uassert.True(t, strings.Contains(got, "[Usernames](/r/moul/toolbox/usernames)"))
	uassert.True(t, strings.Contains(got, "resolve a username or an address"))
	uassert.True(t, strings.Contains(got, "identity, read"))
}

func TestIndexEmpty(t *testing.T) {
	uassert.True(t, strings.Contains(Index(nil), "No tools yet."))
}

// TestIndexEscapesCells pins the escaping contract: a description is written
// by whoever wrote the entry, and a pipe in one would otherwise add a column to
// every row below it. The title is link text inside a cell, so it needs the
// pipe escaped there too.
func TestIndexEscapesCells(t *testing.T) {
	got := Index([]Tool{{
		Slug:  "evil",
		Path:  "gno.land/r/moul/toolbox/evil",
		Title: "Ev|il",
		Desc:  "a | b",
		Tags:  []string{"x|y"},
	}})
	uassert.False(t, strings.Contains(got, "a | b"))
	uassert.True(t, strings.Contains(got, `[Ev\|il](/r/moul/toolbox/evil)`))
	uassert.True(t, strings.Contains(got, `x\|y`))
}

// TestIndexEscapesTitleExactlyOnce is the double-wrap regression, and the
// values are copied from what the escapers actually produce rather than
// guessed: md.Link runs its text through sanitize.InlineText itself, so
// md.Link(ui.Cell(title), url) yields `[a\\\*b]` where one pass yields
// `[a\*b]`, and the reader sees a stray backslash.
func TestIndexEscapesTitleExactlyOnce(t *testing.T) {
	got := Index([]Tool{{
		Slug:  "star",
		Path:  "gno.land/r/moul/toolbox/star",
		Title: "a*b",
		Desc:  "c*d",
	}})
	uassert.True(t, strings.Contains(got, `[a\*b](/r/moul/toolbox/star)`))
	uassert.False(t, strings.Contains(got, `a\\`))
	uassert.True(t, strings.Contains(got, `c\*d`))
}

func TestCard(t *testing.T) {
	got := Card(Tool{
		Slug:  "usernames",
		Path:  "gno.land/r/moul/toolbox/usernames",
		Title: "Usernames",
		Desc:  "resolve a username or an address",
		Tags:  []string{"identity"},
	})
	uassert.True(t, strings.Contains(got, "## Usernames"))
	uassert.True(t, strings.Contains(got, "resolve a username or an address"))
	uassert.True(t, strings.Contains(got, "`gno.land/r/moul/toolbox/usernames`"))
	uassert.True(t, strings.Contains(got, "/r/moul/toolbox/usernames"))
	uassert.True(t, strings.Contains(got, "Tags: identity"))
}

func TestCardMinimal(t *testing.T) {
	got := Card(Tool{Slug: "x", Path: "gno.land/r/moul/toolbox/x/v0", Title: "X"})
	uassert.True(t, strings.Contains(got, "## X"))
	uassert.False(t, strings.Contains(got, "Tags:"))
}

func TestNav(t *testing.T) {
	uassert.Equal(t, "[toolbox](/r/moul/toolbox) / **Usernames**\n",
		Nav("/r/moul/toolbox", "Usernames"))
}
