package threads

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")

	home = "gno.land/r/moul/home"
)

func TestValidPage(t *testing.T) {
	tests := []struct {
		page string
		want bool
	}{
		{"gno.land/r/moul/home", true},
		{"gno.land/r/gov/dao:proposal/42", true},
		{"a/b", true},
		{"", false},
		{"nopath", false},
		{"/leading", false},
		{"trailing/", false},
		{"double//slash", false},
		{"gno.land/r/Moul/home", false},
		{"gno.land/r/moul/home?x=1", false},
		{"gno.land/r/moul/" + strings.Repeat("x", MaxPageLen), false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidPage(tt.page), tt.page)
	}
}

func TestValidBody(t *testing.T) {
	tests := []struct {
		name string
		body string
		want bool
	}{
		{"plain", "hello", true},
		{"newlines and tabs are content", "a\nb\tc", true},
		{"markdown is allowed and escaped later", "[x](y) | z", true},
		{"empty", "", false},
		{"blank", "   \n ", false},
		{"too long", strings.Repeat("x", MaxBodyLen+1), false},
		{"control character", "a\x01b", false},
		{"delete character", "a\x7fb", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidBody(tt.body), tt.name)
	}
}

func TestPostRejectsWhatItCannotStore(t *testing.T) {
	b := NewBoard()

	_, err := b.Post("nopath", alice, "hi", 100)
	uassert.ErrorIs(t, err, ErrBadPage)

	_, err = b.Post(home, alice, "", 100)
	uassert.ErrorIs(t, err, ErrBadBody)

	uassert.Equal(t, 0, b.Len())
	uassert.Equal(t, 0, b.Pages())
}

func TestReplyCountsPeopleAndNotMessages(t *testing.T) {
	b := NewBoard()
	id, err := b.Post(home, alice, "root", 100)
	urequire.NoError(t, err)

	// A new address is the mint signal, exactly once.
	isNew, err := b.Reply(id, bob, "first", 101)
	urequire.NoError(t, err)
	uassert.True(t, isNew, "bob is a new replier")

	isNew, err = b.Reply(id, bob, "again", 102)
	urequire.NoError(t, err)
	uassert.False(t, isNew, "bob replying twice is not two people")

	// The author replying to their own thread never counts.
	isNew, err = b.Reply(id, alice, "mine", 103)
	urequire.NoError(t, err)
	uassert.False(t, isNew, "the author is not an audience")

	isNew, err = b.Reply(id, carol, "hello", 104)
	urequire.NoError(t, err)
	uassert.True(t, isNew, "carol is a new replier")

	th, ok := b.Get(id)
	urequire.True(t, ok, "thread exists")
	uassert.Equal(t, 4, len(th.Replies))
	uassert.Equal(t, 2, th.Repliers())
	uassert.True(t, th.HasReplied(bob))
	uassert.False(t, th.HasReplied(alice), "the author is never in the replier set")
}

func TestReplyToNothing(t *testing.T) {
	b := NewBoard()
	_, err := b.Reply(42, bob, "hi", 100)
	uassert.ErrorIs(t, err, ErrNoThread)
}

func TestPinOnlyEverMovesForward(t *testing.T) {
	b := NewBoard()
	id, _ := b.Post(home, alice, "root", 100)

	urequire.NoError(t, b.Pin(id, 1000))
	th, _ := b.Get(id)
	uassert.True(t, th.Pinned(999))
	uassert.False(t, th.Pinned(1000), "the pin is exclusive at its own height")

	// A cheaper pin cannot cut an expensive one short.
	uassert.ErrorIs(t, b.Pin(id, 500), ErrPinIsPast)
	uassert.ErrorIs(t, b.Pin(id, 1000), ErrPinIsPast)
	uassert.Equal(t, int64(1000), th.PinnedUntil)

	urequire.NoError(t, b.Pin(id, 1200))
	uassert.Equal(t, int64(1200), th.PinnedUntil)
}

func TestListIsPinnedThenNewest(t *testing.T) {
	b := NewBoard()
	first, _ := b.Post(home, alice, "first", 100)
	second, _ := b.Post(home, bob, "second", 101)
	third, _ := b.Post(home, carol, "third", 102)

	// Newest first, nothing pinned.
	got := b.List(home, 200, 0)
	urequire.Equal(t, 3, len(got))
	uassert.Equal(t, uint64(third), uint64(got[0].ID))
	uassert.Equal(t, uint64(second), uint64(got[1].ID))
	uassert.Equal(t, uint64(first), uint64(got[2].ID))

	// Pinning the oldest moves it to the top and leaves the rest in order.
	urequire.NoError(t, b.Pin(first, 500))
	got = b.List(home, 200, 0)
	uassert.Equal(t, uint64(first), uint64(got[0].ID))
	uassert.Equal(t, uint64(third), uint64(got[1].ID))
	uassert.Equal(t, uint64(second), uint64(got[2].ID))

	// The pin expires on its own, with nothing to sweep.
	got = b.List(home, 500, 0)
	uassert.Equal(t, uint64(third), uint64(got[0].ID))

	// limit truncates after the partition, so a pin is never cut off.
	got = b.List(home, 200, 1)
	urequire.Equal(t, 1, len(got))
	uassert.Equal(t, uint64(first), uint64(got[0].ID))
}

func TestPagesAreIndependent(t *testing.T) {
	b := NewBoard()
	b.Post(home, alice, "on home", 100)
	b.Post("gno.land/r/moul/blog", bob, "on the blog", 101)

	uassert.Equal(t, 2, b.Len())
	uassert.Equal(t, 2, b.Pages())
	uassert.Equal(t, 1, b.PageLen(home))
	uassert.Equal(t, 0, b.PageLen("gno.land/r/nobody/here"))
	uassert.Equal(t, 0, len(b.List("gno.land/r/nobody/here", 100, 0)))
}

func TestRecentCrossesPages(t *testing.T) {
	b := NewBoard()
	b.Post(home, alice, "one", 100)
	b.Post("gno.land/r/moul/blog", bob, "two", 101)
	third, _ := b.Post(home, carol, "three", 102)

	got := b.Recent(2)
	urequire.Equal(t, 2, len(got))
	uassert.Equal(t, uint64(third), uint64(got[0].ID), "newest first")
}

func TestBlockEscapesTheBodyItShows(t *testing.T) {
	b := NewBoard()
	id, _ := b.Post(home, alice, "a | pipe and [a link](x)", 100)

	out := Block("gno.land/r/moul/x/social/threads/v0", home, b.List(home, 200, 10), 1, 200)

	// The assertion has to be on what IS there, not on what is not: an
	// escaped cell contains the backslash form, and a row that silently lost
	// the body entirely would satisfy any "does not contain" check.
	uassert.True(t, strings.Contains(out, `a \| pipe and \[a link\]\(x\)`),
		"the body is cut and escaped once, pipe included: "+out)
	uassert.False(t, strings.Contains(out, "| a | pipe"), "a raw pipe would open a column: "+out)
	uassert.True(t, strings.Contains(out, ThreadURL("gno.land/r/moul/x/social/threads/v0", id)))
	uassert.True(t, strings.Contains(out, "func=Post"), "the block offers the transaction")
}

func TestBlockOnAnEmptyPageSaysSo(t *testing.T) {
	out := Block("gno.land/r/moul/x/social/threads/v0", home, nil, 0, 200)
	uassert.True(t, strings.Contains(out, "No discussion yet."), out)
}

func TestURLsStripTheChainDomain(t *testing.T) {
	uassert.Equal(t, "/r/moul/x/social/threads/v0", RealmURL("gno.land/r/moul/x/social/threads/v0"))
	uassert.Equal(t, "/r/a/b:thread/7", ThreadURL("gno.land/r/a/b", 7))
	uassert.Equal(t, "/r/a/b:page/gno.land/r/moul/home", PageURL("gno.land/r/a/b", home))
}
