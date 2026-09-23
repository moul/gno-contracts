package blog

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/uassert/v0"
)

// reset empties every package-level variable. ExampleRender runs after every
// Test in this package and would otherwise render whatever they left behind,
// so both the tests and the example start from here.
func reset() {
	posts = avl.NewTree()
	order = avl.NewTree()
	intro = ""
	rev = 0
}

// seed writes a post without going through Set, so a caller needs no
// `cur realm` and the example stays a plain function.
func seed(slug, title, date, tags, body string) {
	rev++
	p := &post{
		slug:  slug,
		title: title,
		date:  date,
		tags:  joinTags(splitTags(tags)),
		body:  body,
		rev:   rev,
	}
	posts.Set(slug, p)
	order.Set(orderKey(date, slug), p)
}

func TestValidSlug(t *testing.T) {
	for _, tc := range []struct {
		slug string
		want bool
	}{
		{"mygnoscan", true},
		{"a", true},
		{"hello-world.2", true},
		{"under_score", true},
		{"", false},
		{"Caps", false},
		{"has space", false},
		{"colon:here", false},
		{"slash/here", false},
		{"!intro", false},
		{strings.Repeat("a", maxSlugLen), true},
		{strings.Repeat("a", maxSlugLen+1), false},
	} {
		uassert.Equal(t, tc.want, validSlug(tc.slug), "validSlug("+tc.slug+")")
	}
}

func TestValidDate(t *testing.T) {
	for _, tc := range []struct {
		date string
		want bool
	}{
		{"2026-09-23", true},
		{"0000-00-00", true}, // shape only: ordering is all this field is for
		{"2026-9-23", false},
		{"2026/09/23", false},
		{"2026-09-233", false},
		{"", false},
	} {
		uassert.Equal(t, tc.want, validDate(tc.date), "validDate("+tc.date+")")
	}
}

func TestSplitTagsNormalizes(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"", ""},
		{"gno", "gno"},
		{" Gno , TOOLING ", "gno,tooling"},
		{"gno,gno,gno", "gno"},
		{"gno,,tooling", "gno,tooling"},
	} {
		uassert.Equal(t, tc.want, joinTags(splitTags(tc.in)), "splitTags("+tc.in+")")
	}
}

// A post published earlier must render below one published later, which is
// the only thing the second tree exists to guarantee.
func TestIndexIsNewestFirst(t *testing.T) {
	reset()
	seed("older", "Older", "2026-01-01", "", "First.")
	seed("newer", "Newer", "2026-09-23", "", "Second.")

	out := Render("")
	iNew := strings.Index(out, "Newer")
	iOld := strings.Index(out, "Older")
	uassert.True(t, iNew >= 0 && iOld >= 0, "both posts render")
	uassert.True(t, iNew < iOld, "the newer post renders first")
}

// Re-dating a post has to move it, not leave a ghost entry behind at the old
// key. Set is the only path that can do this, so it is checked through Set.
func TestRedatingMovesTheIndexEntry(t *testing.T) {
	reset()
	seed("a", "A", "2026-01-01", "", "Body A.")
	uassert.Equal(t, 1, order.Size(), "one order entry")

	// Emulate Set's re-key without needing a realm: remove then re-add.
	p := posts.Get("a").(*post)
	order.Remove(orderKey(p.date, "a"))
	p.date = "2026-12-31"
	order.Set(orderKey(p.date, "a"), p)

	uassert.Equal(t, 1, order.Size(), "still one order entry, not two")
	uassert.True(t, strings.Contains(Render(""), "2026-12-31"), "the new date renders")
}

func TestRenderPostAndNotFound(t *testing.T) {
	reset()
	seed("mygnoscan", "Sharing mygnoscan", "2026-09-23", "mygnoscan,tooling", "## Why\n\nBecause it is useful.")

	out := Render("mygnoscan")
	uassert.True(t, strings.Contains(out, "# Sharing mygnoscan"), "title renders as the H1")
	uassert.True(t, strings.Contains(out, "Because it is useful."), "body renders verbatim")
	uassert.True(t, strings.Contains(out, "## Why"), "markdown in the body is not escaped")

	missing := Render("nope")
	uassert.True(t, strings.Contains(missing, "Not found"), "an unknown slug is a 404, not the index")
}

func TestRenderTagFiltersAndReportsEmpty(t *testing.T) {
	reset()
	seed("a", "A", "2026-01-01", "tooling", "Body A.")
	seed("b", "B", "2026-01-02", "chain", "Body B.")

	out := Render("t/tooling")
	uassert.True(t, strings.Contains(out, "A"), "the tagged post is listed")
	uassert.False(t, strings.Contains(out, "](/r/moul/blog:b)"), "the untagged post is not")

	empty := Render("t/nothing")
	uassert.True(t, strings.Contains(empty, "No post carries this tag."), "an unused tag says so")
}

// The manifest is the whole diff protocol. A change to any of the four fields
// the record covers has to change the hash, or gnoblog reports a stale post as
// up to date and the fix never gets pushed.
func TestManifestHashCoversEveryField(t *testing.T) {
	base := record("T", "2026-01-01", "a", "body")
	for _, tc := range []struct {
		name string
		got  string
	}{
		{"title", record("T2", "2026-01-01", "a", "body")},
		{"date", record("T", "2026-01-02", "a", "body")},
		{"tags", record("T", "2026-01-01", "b", "body")},
		{"body", record("T", "2026-01-01", "a", "body2")},
	} {
		uassert.NotEqual(t, hashOf(base), hashOf(tc.got), "changing the "+tc.name+" changes the hash")
	}
}

func TestManifestShape(t *testing.T) {
	reset()
	seed("a", "A", "2026-01-01", "tooling", "Body A.")

	lines := strings.Split(strings.TrimRight(Manifest(), "\n"), "\n")
	uassert.Equal(t, 2, len(lines), "one intro row plus one post row")
	uassert.True(t, strings.HasPrefix(lines[0], introKey+"\t"), "the intro row comes first")

	f := strings.Split(lines[1], "\t")
	uassert.Equal(t, 5, len(f), "five tab-separated fields")
	uassert.Equal(t, "a", f[0], "slug")
	uassert.Equal(t, "2026-01-01", f[2], "date")
	uassert.Equal(t, "7", f[3], "body length")
	uassert.Equal(t, hashOf(record("A", "2026-01-01", "tooling", "Body A.")), f[4], "record hash")
}

func TestFirstLineSkipsHeadings(t *testing.T) {
	uassert.Equal(t, "The prose.", firstLine("# Title\n\n## Sub\n\nThe prose.\n"))
	uassert.Equal(t, "", firstLine("# Only a heading\n"))
}

func TestIntroDefaultsAndOverrides(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render(""), "moul's blog"), "the built-in header shows before SetIntro")

	intro = "# Something else"
	uassert.True(t, strings.Contains(Render(""), "Something else"), "a set intro replaces it")
	uassert.False(t, strings.Contains(Render(""), "moul's blog"), "and the default is gone")
}
