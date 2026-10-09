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
		Path:  "gno.land/r/moul/toolbox/usernames/v0",
		Title: "Usernames",
		Desc:  "resolve a username or an address",
		Tags:  []string{"identity", "read"},
	}))

	got := Index(c.List())
	uassert.True(t, strings.Contains(got, "[Usernames](/r/moul/toolbox/usernames/v0)"))
	uassert.True(t, strings.Contains(got, "resolve a username or an address"))
	uassert.True(t, strings.Contains(got, "identity, read"))
}

func TestIndexEmpty(t *testing.T) {
	uassert.True(t, strings.Contains(Index(nil), "No tools yet."))
}

// TestIndexEscapesCells pins the escaping contract: a description is written
// by whoever wrote the entry, and a pipe in one would otherwise add a column
// to every row below it.
func TestIndexEscapesCells(t *testing.T) {
	got := Index([]Tool{{
		Slug:  "evil",
		Path:  "gno.land/r/moul/toolbox/evil/v0",
		Title: "Evil",
		Desc:  "a | b",
	}})
	uassert.False(t, strings.Contains(got, "a | b"))
}

func TestCard(t *testing.T) {
	got := Card(Tool{
		Slug:  "usernames",
		Path:  "gno.land/r/moul/toolbox/usernames/v0",
		Title: "Usernames",
		Desc:  "resolve a username or an address",
		Tags:  []string{"identity"},
	})
	uassert.True(t, strings.Contains(got, "## Usernames"))
	uassert.True(t, strings.Contains(got, "resolve a username or an address"))
	uassert.True(t, strings.Contains(got, "`gno.land/r/moul/toolbox/usernames/v0`"))
	uassert.True(t, strings.Contains(got, "/r/moul/toolbox/usernames/v0"))
	uassert.True(t, strings.Contains(got, "Tags: identity"))
}

func TestCardMinimal(t *testing.T) {
	got := Card(Tool{Slug: "x", Path: "gno.land/r/moul/toolbox/x/v0", Title: "X"})
	uassert.True(t, strings.Contains(got, "## X"))
	uassert.False(t, strings.Contains(got, "Tags:"))
}

func TestNav(t *testing.T) {
	uassert.Equal(t, "[toolbox](/r/moul/toolbox/v0) / **Usernames**\n",
		Nav("/r/moul/toolbox/v0", "Usernames"))
}
