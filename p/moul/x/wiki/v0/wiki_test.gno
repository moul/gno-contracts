package wiki

import (
	"testing"
	"time"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	mod   = testutils.TestAddress("mod")
)

// at returns a deterministic timestamp and height for step n, so tests never
// depend on wall-clock time or on where a previous test left the block height.
func at(n int) (time.Time, int64) {
	return time.Unix(int64(1757000000+n*60), 0).UTC(), int64(100 + n)
}

func edit(t *testing.T, w *Wiki, n int, author address, title, body, summary string) *Revision {
	t.Helper()
	now, h := at(n)
	rev, err := w.Edit(author, now, h, title, body, summary, false)
	uassert.NoError(t, err, title)
	return rev
}

func TestEditCreatesAndUpdates(t *testing.T) {
	w := New(DefaultRetention, DefaultMaxBody)

	r1 := edit(t, w, 1, alice, "gno_land", "The first draft.\n", "create")
	uassert.Equal(t, uint64(1), r1.ID)
	uassert.Equal(t, uint64(0), r1.Prev)
	uassert.Equal(t, string(KindCreate), string(r1.Kind))

	r2 := edit(t, w, 2, bob, "Gno land", "The second draft.\n", "expand")
	uassert.Equal(t, uint64(1), r2.Prev)
	uassert.Equal(t, string(KindEdit), string(r2.Kind))

	p, err := w.Page("Gno land")
	uassert.NoError(t, err)
	uassert.Equal(t, 2, p.NumRevisions())
	body, kept := p.Body()
	uassert.True(t, kept)
	uassert.Equal(t, "The second draft.\n", body)

	s := w.Stats()
	uassert.Equal(t, 1, s.Pages, "the two edits are one page")
	uassert.Equal(t, 2, s.Revisions)
}

func TestEditRejectsNoOpAndOversize(t *testing.T) {
	w := New(DefaultRetention, 32)
	now, h := at(1)

	_, err := w.Edit(alice, now, h, "A", "", "empty", false)
	uassert.ErrorIs(t, err, ErrEmptyBody)

	_, err = w.Edit(alice, now, h, "A", "0123456789012345678901234567890123", "too big", false)
	uassert.ErrorIs(t, err, ErrBodyTooLarge)

	edit(t, w, 1, alice, "A", "same\n", "create")
	_, err = w.Edit(alice, now, h, "A", "same\n", "again", false)
	uassert.ErrorIs(t, err, ErrNoChange, "an identical body must not create a revision")

	_, err = w.Edit(alice, now, h, "Special:Anything", "x\n", "", false)
	uassert.ErrorIs(t, err, ErrSpecial)
}

// TestRetentionEvictsOldBodies is the storage design in one test: the spine
// grows by a fixed amount per edit, the held bytes do not.
func TestRetentionEvictsOldBodies(t *testing.T) {
	w := New(2, DefaultMaxBody)
	bodies := []string{"aaaa\n", "bbbbbb\n", "cccccccc\n", "dddddddddd\n"}
	for i, b := range bodies {
		edit(t, w, i+1, alice, "A", b, "edit")
	}

	p, err := w.Page("A")
	uassert.NoError(t, err)
	uassert.Equal(t, 4, p.NumRevisions(), "every revision stays in the history")

	kept := 0
	for _, r := range p.History(0, 10) {
		if r.Kept() {
			kept++
		}
	}
	uassert.Equal(t, 2, kept, "only the retention window keeps bodies")
	uassert.Equal(t, len(bodies[2])+len(bodies[3]), w.Stats().BytesHeld)

	// The spine of an evicted revision is intact, hash included.
	oldest := p.History(0, 10)[3]
	uassert.False(t, oldest.Kept())
	uassert.Equal(t, hashBody(bodies[0]), oldest.Hash)
	uassert.Equal(t, len(bodies[0]), oldest.Size)
}

func TestRevert(t *testing.T) {
	w := New(3, DefaultMaxBody)
	first := edit(t, w, 1, alice, "A", "good\n", "create")
	edit(t, w, 2, bob, "A", "VANDALISM\n", "oops")

	now, h := at(3)
	rev, err := w.Revert(mod, now, h, "A", first.ID, "rv")
	uassert.NoError(t, err)
	uassert.Equal(t, string(KindRevert), string(rev.Kind))

	p, _ := w.Page("A")
	body, _ := p.Body()
	uassert.Equal(t, "good\n", body)
	uassert.Equal(t, 3, p.NumRevisions(), "the vandalism stays in the history")
}

func TestRevertRefusesEvictedAndUnknown(t *testing.T) {
	w := New(1, DefaultMaxBody)
	first := edit(t, w, 1, alice, "A", "one\n", "")
	edit(t, w, 2, alice, "A", "two\n", "")
	now, h := at(3)

	_, err := w.Revert(alice, now, h, "A", first.ID, "")
	uassert.ErrorIs(t, err, ErrBodyEvicted,
		"reverting past the retention window must fail loudly, not silently")

	_, err = w.Revert(alice, now, h, "A", 9999, "")
	uassert.ErrorIs(t, err, ErrNoSuchRevision)
}

func TestBlankAndPurge(t *testing.T) {
	w := New(5, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "content\n", "")
	edit(t, w, 2, alice, "A", "more content\n", "")
	uassert.Equal(t, 1, w.Stats().Pages)

	now, h := at(3)
	_, err := w.Blank(mod, now, h, "A", "policy")
	uassert.NoError(t, err)
	uassert.Equal(t, 0, w.Stats().Pages, "a blanked page stops counting as a page")

	p, _ := w.Page("A")
	uassert.True(t, p.Blanked)
	uassert.Equal(t, 3, p.NumRevisions(), "blanking is a revision, not an erasure")

	released, err := w.Purge("A")
	uassert.NoError(t, err)
	uassert.Equal(t, len("content\n")+len("more content\n"), released)
	uassert.Equal(t, 0, w.Stats().BytesHeld, "purge releases every retained byte")
	uassert.Equal(t, 3, p.NumRevisions(), "purge leaves the spine intact")
}

func TestBlankThenEditRestoresThePage(t *testing.T) {
	w := New(5, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "content\n", "")
	now, h := at(2)
	w.Blank(mod, now, h, "A", "")
	edit(t, w, 3, alice, "A", "back\n", "restore")
	uassert.Equal(t, 1, w.Stats().Pages)
	p, _ := w.Page("A")
	uassert.False(t, p.Blanked)
}

func TestBacklinksAndRedlinks(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "links to [[B]] and [[C]]\n", "")
	edit(t, w, 2, alice, "D", "also links to [[B]]\n", "")

	b := MustParseTitle("B")
	in := w.Backlinks(b)
	uassert.Equal(t, 2, len(in))
	uassert.Equal(t, "A", in[0].String())
	uassert.Equal(t, "D", in[1].String())

	// C does not exist: a redlink is still indexed, so the page knows who is
	// waiting for it the moment it is created.
	uassert.False(t, w.Exists(MustParseTitle("C")))
	uassert.Equal(t, 1, len(w.Backlinks(MustParseTitle("C"))))

	// Editing A to drop the link must un-index it.
	edit(t, w, 3, alice, "A", "links to nothing\n", "")
	uassert.Equal(t, 1, len(w.Backlinks(b)))
	uassert.Equal(t, 0, len(w.Backlinks(MustParseTitle("C"))))
}

func TestCategories(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "text\n[[Category:Chains]]\n", "")
	edit(t, w, 2, alice, "B", "text\n[[Category:Chains]]\n[[Category:Tools]]\n", "")

	chains := MustParseTitle("Category:Chains")
	uassert.Equal(t, 2, len(w.CategoryMembers(chains)))
	uassert.Equal(t, 2, len(w.Categories()))

	// An explicit [[:Category:X]] links to the category instead of joining it.
	edit(t, w, 3, alice, "C", "see [[:Category:Chains]]\n", "")
	uassert.Equal(t, 2, len(w.CategoryMembers(chains)))
	uassert.Equal(t, 1, len(w.Backlinks(chains)))
}

func TestRedirect(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "Gno", "#REDIRECT [[Gno land]]\n", "")
	edit(t, w, 2, alice, "Gno land", "The article.\n", "")

	dest, asked, err := w.Resolve("Gno")
	uassert.NoError(t, err)
	uassert.Equal(t, "Gno land", dest.Title.String())
	uassert.Equal(t, "Gno", asked.Title.String())

	// A dangling redirect renders itself rather than 404ing.
	edit(t, w, 3, alice, "Nowhere", "#REDIRECT [[Absent]]\n", "")
	dest, _, err = w.Resolve("Nowhere")
	uassert.NoError(t, err)
	uassert.Equal(t, "Nowhere", dest.Title.String())
}

func TestMoveKeepsHistoryAndLeavesARedirect(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "Old name", "body linking to [[B]]\n", "")
	edit(t, w, 2, alice, "Old name", "body linking to [[B]], revised\n", "")

	now, h := at(3)
	uassert.NoError(t, w.Move(mod, now, h, "Old name", "New name", "rename"))

	moved, err := w.Page("New name")
	uassert.NoError(t, err)
	uassert.Equal(t, 3, moved.NumRevisions(), "history follows the page")
	body, kept := moved.Body()
	uassert.True(t, kept)
	uassert.Equal(t, "body linking to [[B]], revised\n", body, "a move does not touch the text")

	stub, err := w.Page("Old name")
	uassert.NoError(t, err)
	uassert.Equal(t, "New name", stub.Redirect())

	// The backlink index must follow the rename, not point at the old key.
	in := w.Backlinks(MustParseTitle("B"))
	uassert.Equal(t, 1, len(in))
	uassert.Equal(t, "New name", in[0].String())
}

func TestMoveRefusesAnExistingTarget(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "a\n", "")
	edit(t, w, 2, alice, "B", "b\n", "")
	now, h := at(3)
	uassert.ErrorIs(t, w.Move(mod, now, h, "A", "B", ""), ErrPageExists)
}

func TestProtectionIsRecordedInTheHistory(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "a\n", "")
	now, h := at(2)
	uassert.NoError(t, w.SetProtection(mod, now, h, "A", "locked"))

	p, _ := w.Page("A")
	uassert.Equal(t, "locked", p.Protection.String())
	uassert.Equal(t, 2, p.NumRevisions())

	// The protection entry must not become the current text.
	body, kept := p.Body()
	uassert.True(t, kept)
	uassert.Equal(t, "a\n", body)

	// It carries the current hash, so the history does not read as a blanking.
	last := p.History(0, 1)[0]
	uassert.Equal(t, string(KindProtect), string(last.Kind))
	uassert.Equal(t, hashBody("a\n"), last.Hash)
}

func TestMetaRevisionsDoNotEvictRealBodies(t *testing.T) {
	w := New(2, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "one\n", "")
	edit(t, w, 2, alice, "A", "two\n", "")
	now, h := at(3)
	w.SetProtection(mod, now, h, "A", "locked")
	w.SetProtection(mod, now, h, "A", "open")

	p, _ := w.Page("A")
	kept := 0
	for _, r := range p.History(0, 10) {
		if r.Kept() {
			kept++
		}
	}
	uassert.Equal(t, 2, kept, "two bodyless entries must not push both bodies out of a window of 2")
}

func TestRecentChangesIsNewestFirst(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "a\n", "first")
	edit(t, w, 2, bob, "B", "b\n", "second")

	recent := w.Recent(10)
	uassert.Equal(t, 2, len(recent))
	uassert.Equal(t, "B", recent[0].Title.String())
	uassert.Equal(t, "A", recent[1].Title.String())
}

func TestTitlesWalkOneNamespace(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "Beta", "b\n", "")
	edit(t, w, 2, alice, "Alpha", "a\n", "")
	edit(t, w, 3, alice, "Help:Alpha", "t\n", "")

	main := w.Titles(NSMain.Prefix(), 0, 10)
	uassert.Equal(t, 2, len(main))
	uassert.Equal(t, "Alpha", main[0].String())
	uassert.Equal(t, "Beta", main[1].String())

	help := w.Titles(NSHelp.Prefix(), 0, 10)
	uassert.Equal(t, 1, len(help))
	uassert.Equal(t, "Help:Alpha", help[0].String())

	uassert.Equal(t, 1, len(w.Titles(NSMain.Prefix(), 1, 10)), "offset skips")
}

func TestContributors(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "1\n", "")
	edit(t, w, 2, bob, "A", "2\n", "")
	edit(t, w, 3, alice, "A", "3\n", "")

	p, _ := w.Page("A")
	c := p.Contributors()
	uassert.Equal(t, 2, len(c))
	uassert.Equal(t, alice.String(), c[0].String())
	uassert.Equal(t, bob.String(), c[1].String())
}

func TestFormatGNOT(t *testing.T) {
	cases := []struct {
		in   int
		want string
	}{
		{0, "0 GNOT"},
		{1000000, "1 GNOT"},
		{1500000, "1.5 GNOT"},
		{100, "0.0001 GNOT"},
		{123456, "0.123456 GNOT"},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, formatGNOT(tc.in))
	}
}
