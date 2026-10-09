package toolbox

import (
	"strings"
	"testing"

	tb "gno.land/p/moul/toolbox/v0"
	"gno.land/p/nt/uassert/v0"
)

// TestEveryToolIsNested is the check that makes the compiled-in catalog safe:
// a copy-pasted entry that kept the wrong path would publish a dead link, and
// buildCatalog panics on it at deploy rather than at read.
func TestEveryToolIsNested(t *testing.T) {
	uassert.True(t, len(tools) > 0)
	for _, tool := range tools {
		uassert.NoError(t, tool.Validate())
		uassert.Equal(t, tool.Slug, tb.SlugOf(hubPath, tool.Path))
	}
}

func TestReadAPI(t *testing.T) {
	uassert.Equal(t, len(tools), Count())
	uassert.True(t, Has("usernames"))
	uassert.False(t, Has("nope"))
	uassert.Equal(t, "gno.land/r/moul/toolbox/usernames/v0", PathOf("usernames"))
	uassert.Equal(t, "Usernames", TitleOf("usernames"))
	uassert.True(t, strings.Contains(DescOf("usernames"), "address"))

	uassert.Equal(t, "", PathOf("nope"))
	uassert.Equal(t, "", TitleOf("nope"))
	uassert.Equal(t, "", DescOf("nope"))
}

func TestSlugsAreSorted(t *testing.T) {
	got := Slugs()
	uassert.Equal(t, Count(), len(got))
	for i := 1; i < len(got); i++ {
		uassert.True(t, got[i-1] < got[i])
	}
}

func TestTags(t *testing.T) {
	got := Tags()
	uassert.True(t, len(got) > 0)
	found := false
	for _, tag := range got {
		if tag == "identity" {
			found = true
		}
	}
	uassert.True(t, found)
}

func TestRenderIndex(t *testing.T) {
	got := Render("")
	uassert.True(t, strings.Contains(got, "# Toolbox"))
	uassert.True(t, strings.Contains(got, "[Usernames](/r/moul/toolbox/usernames/v0)"))
	uassert.True(t, strings.Contains(got, "Tags:"))
}

func TestRenderTagFilter(t *testing.T) {
	kept := Render("?tag=identity")
	uassert.True(t, strings.Contains(kept, "[Usernames](/r/moul/toolbox/usernames/v0)"))
	uassert.True(t, strings.Contains(kept, "Show all"))

	empty := Render("?tag=nope")
	uassert.True(t, strings.Contains(empty, "No tools yet."))
	uassert.False(t, strings.Contains(empty, "[Usernames]"))
}

func TestRenderTool(t *testing.T) {
	got := Render("usernames")
	uassert.True(t, strings.Contains(got, "[toolbox](/r/moul/toolbox/v0)"))
	uassert.True(t, strings.Contains(got, "## Usernames"))
	uassert.True(t, strings.Contains(got, "`gno.land/r/moul/toolbox/usernames/v0`"))
}

func TestRenderUnknown(t *testing.T) {
	for _, path := range []string{"nope", "a/b", "usernames/extra"} {
		got := Render(path)
		uassert.True(t, strings.Contains(got, "# Not found"))
		uassert.True(t, strings.Contains(got, "Back to the toolbox"))
	}
}

// TestRenderNeverEmitsTwoBlankLines: gno collapses them in an Output block, so
// a Render that produces one can never be pinned by an example. Checked here
// rather than discovered later.
func TestRenderNeverEmitsTwoBlankLines(t *testing.T) {
	for _, path := range []string{"", "?tag=identity", "usernames", "nope"} {
		uassert.False(t, strings.Contains(Render(path), "\n\n\n"))
	}
}
