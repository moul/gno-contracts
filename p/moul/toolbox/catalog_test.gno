package toolbox

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func tool(slug string, tags ...string) Tool {
	return Tool{
		Slug:  slug,
		Path:  "gno.land/r/moul/toolbox/" + slug + "/v0",
		Title: slug,
		Desc:  "the " + slug + " tool",
		Tags:  tags,
	}
}

func slugs(tools []Tool) []string {
	out := make([]string, len(tools))
	for i, t := range tools {
		out[i] = t.Slug
	}
	return out
}

func TestCatalogZeroValue(t *testing.T) {
	var c Catalog
	uassert.Equal(t, 0, c.Len())
	uassert.Equal(t, 0, len(c.List()))
	uassert.False(t, c.Has("usernames"))
	uassert.ErrorIs(t, c.Remove("usernames"), ErrUnknownSlug)
}

// TestCatalogSortsBySlug checks the only ordering guarantee the type makes,
// against an insertion order that is reverse, interleaved and duplicated.
func TestCatalogSortsBySlug(t *testing.T) {
	var c Catalog
	for _, s := range []string{"zones", "amm", "usernames", "base64", "amm"} {
		uassert.NoError(t, c.Set(tool(s)))
	}
	uassert.Equal(t, 4, c.Len())
	want := []string{"amm", "base64", "usernames", "zones"}
	got := slugs(c.List())
	uassert.Equal(t, len(want), len(got))
	for i := range want {
		uassert.Equal(t, want[i], got[i])
	}
}

func TestCatalogSetReplaces(t *testing.T) {
	var c Catalog
	uassert.NoError(t, c.Set(tool("usernames")))
	updated := tool("usernames")
	updated.Desc = "resolve a username or an address"
	uassert.NoError(t, c.Set(updated))

	uassert.Equal(t, 1, c.Len())
	got, ok := c.Get("usernames")
	uassert.True(t, ok)
	uassert.Equal(t, "resolve a username or an address", got.Desc)
}

func TestCatalogSetRejectsInvalid(t *testing.T) {
	var c Catalog
	uassert.ErrorIs(t, c.Set(Tool{Path: "p", Title: "t"}), ErrEmptySlug)
	uassert.ErrorIs(t, c.Set(Tool{Slug: "A", Path: "p", Title: "t"}), ErrBadSlug)
	uassert.ErrorIs(t, c.Set(Tool{Slug: "a", Title: "t"}), ErrEmptyPath)
	uassert.ErrorIs(t, c.Set(Tool{Slug: "a", Path: "p"}), ErrEmptyTitle)
	uassert.Equal(t, 0, c.Len())
}

func TestCatalogGetAndRemove(t *testing.T) {
	var c Catalog
	for _, s := range []string{"amm", "base64", "usernames"} {
		uassert.NoError(t, c.Set(tool(s)))
	}

	got, ok := c.Get("base64")
	uassert.True(t, ok)
	uassert.Equal(t, "gno.land/r/moul/toolbox/base64/v0", got.Path)

	_, ok = c.Get("nope")
	uassert.False(t, ok)

	uassert.NoError(t, c.Remove("base64"))
	uassert.False(t, c.Has("base64"))
	uassert.Equal(t, 2, c.Len())
	uassert.ErrorIs(t, c.Remove("base64"), ErrUnknownSlug)

	// The two survivors are still in order around the hole.
	got2 := slugs(c.List())
	uassert.Equal(t, "amm", got2[0])
	uassert.Equal(t, "usernames", got2[1])
}

// TestCatalogListIsACopy: the tree stores Tool by value, so what List hands
// back is a copy and a caller rewriting an element cannot reach the directory
// through it. Pinned because storing *Tool instead would silently break it.
func TestCatalogListIsACopy(t *testing.T) {
	var c Catalog
	uassert.NoError(t, c.Set(tool("usernames")))

	got := c.List()
	got[0].Title = "hijacked"

	kept, ok := c.Get("usernames")
	uassert.True(t, ok)
	uassert.Equal(t, "usernames", kept.Title)
}

func TestCatalogByTagAndTags(t *testing.T) {
	var c Catalog
	uassert.NoError(t, c.Set(tool("usernames", "identity", "read")))
	uassert.NoError(t, c.Set(tool("amm", "defi")))
	uassert.NoError(t, c.Set(tool("whois", "identity")))

	identity := slugs(c.ByTag("identity"))
	uassert.Equal(t, 2, len(identity))
	uassert.Equal(t, "usernames", identity[0])
	uassert.Equal(t, "whois", identity[1])

	uassert.Equal(t, 0, len(c.ByTag("nope")))
	uassert.Equal(t, 0, len(c.ByTag("")))

	tags := c.Tags()
	uassert.Equal(t, 3, len(tags))
	uassert.Equal(t, "defi", tags[0])
	uassert.Equal(t, "identity", tags[1])
	uassert.Equal(t, "read", tags[2])
}
