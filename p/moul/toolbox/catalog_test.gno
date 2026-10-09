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

// TestCatalogCopyIsAHandle is the shape bug the state pointer exists to stop.
// With the tree embedded by value, the root is a pointer and the size an int,
// so a write through a copy threaded the node onto the tree both of them saw
// while incrementing only the copy's counter: a.Len() said 1 while a.Get found
// the second entry.
func TestCatalogCopyIsAHandle(t *testing.T) {
	a := New()
	uassert.NoError(t, a.Set(tool("amm")))

	b := *a
	uassert.NoError(t, b.Set(tool("usernames")))

	uassert.Equal(t, 2, a.Len())
	uassert.Equal(t, 2, b.Len())
	uassert.Equal(t, a.Len(), len(a.List()))
	uassert.True(t, a.Has("usernames"))

	uassert.NoError(t, b.Remove("amm"))
	uassert.Equal(t, 1, a.Len())
	uassert.False(t, a.Has("amm"))
}

// TestCatalogCopyOfAZeroValueIsSeparate: nothing has been allocated yet, so
// there is no directory to share. Stated because it is the one case where
// copying does NOT alias, and a reader would otherwise have to guess.
func TestCatalogCopyOfAZeroValueIsSeparate(t *testing.T) {
	var a Catalog
	b := a
	uassert.NoError(t, b.Set(tool("usernames")))

	uassert.Equal(t, 0, a.Len())
	uassert.Equal(t, 1, b.Len())
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

// TestCatalogListIsACopy: a caller rewriting what List handed back must not
// reach the directory through it. The struct copy covers the string fields on
// its own; Tags is a slice, so without copyTool the header is duplicated and
// the backing array is shared, and the write below would land in the catalog.
func TestCatalogListIsACopy(t *testing.T) {
	var c Catalog
	uassert.NoError(t, c.Set(tool("usernames", "identity")))

	got := c.List()
	got[0].Title = "hijacked"
	got[0].Tags[0] = "hijacked"

	kept, ok := c.Get("usernames")
	uassert.True(t, ok)
	uassert.Equal(t, "usernames", kept.Title)
	uassert.Equal(t, "identity", kept.Tags[0])
}

// TestCatalogDoesNotAliasTheCallersTags is the same hole from the other side:
// Set must not keep a handle on the slice the caller still holds.
func TestCatalogDoesNotAliasTheCallersTags(t *testing.T) {
	var c Catalog
	tags := []string{"identity"}
	uassert.NoError(t, c.Set(Tool{
		Slug:  "usernames",
		Path:  "gno.land/r/moul/toolbox/usernames",
		Title: "Usernames",
		Tags:  tags,
	}))

	tags[0] = "hijacked"

	kept, ok := c.Get("usernames")
	uassert.True(t, ok)
	uassert.Equal(t, "identity", kept.Tags[0])
	uassert.Equal(t, 1, len(c.ByTag("identity")))
	uassert.Equal(t, 0, len(c.ByTag("hijacked")))
}

// TestCatalogGetIsACopyToo: ByTag and Get hand out the same values List does.
func TestCatalogGetIsACopyToo(t *testing.T) {
	var c Catalog
	uassert.NoError(t, c.Set(tool("usernames", "identity")))

	got, ok := c.Get("usernames")
	uassert.True(t, ok)
	got.Tags[0] = "hijacked"

	byTag := c.ByTag("identity")
	uassert.Equal(t, 1, len(byTag))
	byTag[0].Tags[0] = "hijacked-again"

	kept, _ := c.Get("usernames")
	uassert.Equal(t, "identity", kept.Tags[0])
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
