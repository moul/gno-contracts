package reactions

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

const (
	realmPath = "gno.land/r/test/reactions/v0"
	homePage  = "gno.land/r/moul/home"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

func TestValidPage(t *testing.T) {
	cases := []struct {
		page string
		want bool
	}{
		{"gno.land/r/moul/home", true},
		{"gno.land/p/moul/kit/ui/v0", true},
		{"gno.land/r/moul/x/daily/b58demo", true},
		{"a/b", true},
		{"gno.land/r/you/blog:hello-world", true}, // one page per article
		{"", false},
		{"nolslash", false},
		{"/leading", false},
		{"trailing/", false},
		{"double//slash", false},
		{"gno.land/r/MOUL/home", false},                   // uppercase is not a path here
		{"gno.land/r/moul/home ", false},                  // a space is not path-shaped
		{"gno.land/r/[x](http://e.vil)", false},           // a markdown link cannot be a key
		{"gno.land/r/‮moul/home", false},             // bidi override
		{strings.Repeat("a/", MaxPageLen) + "b", false},   // over the cap
		{strings.Repeat("a", MaxPageLen-2) + "/b", true},  // exactly at the cap
		{strings.Repeat("a", MaxPageLen-1) + "/b", false}, // one byte over
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, ValidPage(tc.page), tc.page)
	}
}

func TestPaletteIsClosed(t *testing.T) {
	uassert.Equal(t, 6, len(Keys()))
	for _, k := range Keys() {
		uassert.True(t, Valid(k), k)
		uassert.NotEqual(t, "", Emoji(k), k)
	}
	uassert.False(t, Valid("poop"))
	uassert.Equal(t, "", Emoji("poop"))

	// Keys returns a copy: reordering it must not reorder the palette.
	ks := Keys()
	ks[0] = "clobbered"
	uassert.Equal(t, KeyUp, Keys()[0])
}

// TestNilPageReadsAsEmpty is what lets a host realm render the block without
// ever checking whether the page exists.
func TestNilPageReadsAsEmpty(t *testing.T) {
	var p *Page
	uassert.Equal(t, 0, p.Count(KeyUp))
	uassert.Equal(t, 0, p.Total())
	uassert.Equal(t, "", p.Of(alice))
	key, who, at := p.Last()
	uassert.Equal(t, "", key)
	uassert.Equal(t, address(""), who)
	uassert.Equal(t, int64(0), at)
}

func TestReactCountsAddressesNotClicks(t *testing.T) {
	b := NewBoard()

	uassert.True(t, b.React(homePage, alice, KeyUp, 100))
	uassert.True(t, b.React(homePage, alice, KeyUp, 101))
	uassert.True(t, b.React(homePage, alice, KeyUp, 102))

	p := b.Page(homePage)
	uassert.Equal(t, 1, p.Count(KeyUp), "three clicks from one address is one reaction")
	uassert.Equal(t, 1, p.Total())

	// The repeat still counts as the last event, because it happened.
	_, _, at := p.Last()
	uassert.Equal(t, int64(102), at)
}

func TestChangingReactionMovesTheCount(t *testing.T) {
	b := NewBoard()
	b.React(homePage, alice, KeyUp, 100)
	b.React(homePage, bob, KeyUp, 101)
	b.React(homePage, alice, KeyFire, 102)

	p := b.Page(homePage)
	uassert.Equal(t, 1, p.Count(KeyUp))
	uassert.Equal(t, 1, p.Count(KeyFire))
	uassert.Equal(t, 2, p.Total(), "changing a reaction never changes the head count")
	uassert.Equal(t, KeyFire, p.Of(alice))
	uassert.Equal(t, KeyUp, p.Of(bob))
}

func TestUnreact(t *testing.T) {
	b := NewBoard()
	b.React(homePage, alice, KeyUp, 100)

	uassert.False(t, b.Unreact("gno.land/r/never/touched", alice), "no page")
	uassert.False(t, b.Unreact(homePage, bob), "no reaction of bob's")
	uassert.True(t, b.Unreact(homePage, alice))
	uassert.False(t, b.Unreact(homePage, alice), "removing twice is not an error, just false")

	p := b.Page(homePage)
	uassert.Equal(t, 0, p.Count(KeyUp), "an emptied bucket leaves no residue")
	uassert.Equal(t, 0, p.Total())

	// Last is deliberately not rewound: it records what happened.
	key, who, _ := p.Last()
	uassert.Equal(t, KeyUp, key)
	uassert.Equal(t, alice, who)
}

func TestReactRejects(t *testing.T) {
	b := NewBoard()
	uassert.False(t, b.React("not a path", alice, KeyUp, 1), "bad page")
	uassert.False(t, b.React(homePage, alice, "poop", 1), "key outside the palette")
	uassert.Equal(t, 0, b.Pages(), "a rejected reaction creates no page")
}

func TestPagesAreIndependentAndOrdered(t *testing.T) {
	b := NewBoard()
	b.React("gno.land/r/moul/home", alice, KeyUp, 1)
	b.React("gno.land/r/moul/blog", bob, KeyFire, 2)
	b.React("gno.land/r/moul/blog", carol, KeyFire, 3)

	uassert.Equal(t, 2, b.Pages())
	uassert.Equal(t, 1, b.Page("gno.land/r/moul/home").Total())
	uassert.Equal(t, 2, b.Page("gno.land/r/moul/blog").Total())

	var seen []string
	b.Each(func(page string, p *Page) bool {
		seen = append(seen, page)
		return false
	})
	uassert.Equal(t, "gno.land/r/moul/blog,gno.land/r/moul/home", strings.Join(seen, ","),
		"Each walks in key order, so a Render built from it is stable")
}

func TestEachStopsOnTrue(t *testing.T) {
	b := NewBoard()
	b.React("gno.land/r/a/one", alice, KeyUp, 1)
	b.React("gno.land/r/b/two", alice, KeyUp, 2)

	n := 0
	b.Each(func(page string, p *Page) bool {
		n++
		return true
	})
	uassert.Equal(t, 1, n)
}

func TestRealmAndPageURL(t *testing.T) {
	uassert.Equal(t, "/r/test/reactions/v0", RealmURL(realmPath))
	uassert.Equal(t, "", RealmURL("nodomain"))
	uassert.Equal(t, "/r/test/reactions/v0:gno.land/r/moul/home",
		PageURL(realmPath, homePage))
	uassert.Equal(t, "", PageURL("nodomain", homePage))
}

// TestBlockShape pins the embed byte for byte. It is a Test and not an Example
// because the block contains a blank line, and gno collapses consecutive blank
// lines inside an // Output: block.
func TestBlockShape(t *testing.T) {
	b := NewBoard()

	empty := "[\U0001F44D](/r/test/reactions/v0$help&func=React&key=up&page=gno.land%2Fr%2Fmoul%2Fhome) " +
		"[\U0001F49C](/r/test/reactions/v0$help&func=React&key=heart&page=gno.land%2Fr%2Fmoul%2Fhome) " +
		"[\U0001F525](/r/test/reactions/v0$help&func=React&key=fire&page=gno.land%2Fr%2Fmoul%2Fhome) " +
		"[\U0001F389](/r/test/reactions/v0$help&func=React&key=party&page=gno.land%2Fr%2Fmoul%2Fhome) " +
		"[\U0001F680](/r/test/reactions/v0$help&func=React&key=rocket&page=gno.land%2Fr%2Fmoul%2Fhome) " +
		"[\U0001F440](/r/test/reactions/v0$help&func=React&key=eyes&page=gno.land%2Fr%2Fmoul%2Fhome)" +
		"\n\n*no reactions yet*\n"
	uassert.Equal(t, empty, Block(realmPath, homePage, b.Page(homePage)),
		"a page nobody has reacted to still renders the whole strip")

	b.React(homePage, alice, KeyUp, 100)
	b.React(homePage, bob, KeyUp, 101)
	b.React(homePage, carol, KeyFire, 102)

	got := Block(realmPath, homePage, b.Page(homePage))
	uassert.True(t, strings.Contains(got, "[\U0001F44D 2]"), "the count rides in the link title")
	uassert.True(t, strings.Contains(got, "[\U0001F525 1]"))
	uassert.True(t, strings.Contains(got, "[\U0001F389]"), "an empty bucket shows no zero")
	uassert.True(t, strings.Contains(got, "last \U0001F525 by "))
	uassert.True(t, strings.Contains(got, "[3 reactions](/r/test/reactions/v0:gno.land/r/moul/home)"))
	uassert.True(t, strings.HasSuffix(got, "*\n"), "one trailing newline, so it drops into a Render")
}

func TestSummaryPluralises(t *testing.T) {
	b := NewBoard()
	b.React(homePage, alice, KeyUp, 100)
	uassert.True(t, strings.Contains(Summary(realmPath, homePage, b.Page(homePage)), "[1 reaction]"))

	b.React(homePage, bob, KeyUp, 101)
	uassert.True(t, strings.Contains(Summary(realmPath, homePage, b.Page(homePage)), "[2 reactions]"))
}

// TestEmojiSurviveTheEscaper is the reason the palette holds no U+FE0F and no
// zero-width joiner: ui.ActionIn escapes the link title, and that escaper
// strips exactly those. A glyph that does not survive it renders as a
// monochrome box on every page that embeds the block.
func TestEmojiSurviveTheEscaper(t *testing.T) {
	b := NewBoard()
	for _, k := range Keys() {
		got := Block(realmPath, homePage, b.Page(homePage))
		uassert.True(t, strings.Contains(got, "["+Emoji(k)+"]"), k)
	}
}

// TestSummaryGoesEmptyWhenEveryoneLeaves is the interaction between the two
// halves of Last: it is deliberately not rewound by Unreact, so the summary has
// to decide for itself whether there is anything left to summarise. Gating on
// the last key alone would print "last 👍 by g1… · 0 reactions" above an empty
// strip, which contradicts itself and keeps attributing a reaction its author
// took back.
func TestSummaryGoesEmptyWhenEveryoneLeaves(t *testing.T) {
	b := NewBoard()
	b.React(homePage, alice, KeyUp, 100)
	b.Unreact(homePage, alice)

	p := b.Page(homePage)
	uassert.Equal(t, 0, p.Total(), "the tally is empty")

	key, _, _ := p.Last()
	uassert.Equal(t, KeyUp, key, "and Last still records the event, by design")

	uassert.Equal(t, "no reactions yet", Summary(realmPath, homePage, p),
		"so the summary shows the empty state rather than a withdrawn reaction")

	uassert.True(t, strings.HasSuffix(Block(realmPath, homePage, p), "*no reactions yet*\n"))
}
