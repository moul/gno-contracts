package wiki

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func comment(t *testing.T, w *Wiki, n int, author address, title, body string, replyTo uint64) *Comment {
	t.Helper()
	now, h := at(n)
	c, err := w.Comment(author, now, h, title, body, replyTo)
	uassert.NoError(t, err, title)
	return c
}

func TestCommentThreads(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "the article\n", "")

	root1 := comment(t, w, 2, alice, "A", "First point.\n", 0)
	root2 := comment(t, w, 3, bob, "A", "Second point.\n", 0)
	reply := comment(t, w, 4, mod, "A", "Answering the first.\n", root1.ID)

	title := MustParseTitle("A")
	uassert.Equal(t, 3, w.NumComments(title))

	threads := w.Comments(title, 0, 10)
	uassert.Equal(t, 2, len(threads), "replies do not count as threads")
	uassert.Equal(t, uint64(root1.ID), threads[0].Root.ID)
	uassert.Equal(t, 1, len(threads[0].Replies))
	uassert.Equal(t, uint64(reply.ID), threads[0].Replies[0].ID)
	uassert.Equal(t, uint64(root2.ID), threads[1].Root.ID)
	uassert.Equal(t, 0, len(threads[1].Replies))

	uassert.Equal(t, 1, len(w.Comments(title, 1, 10)), "offset skips whole threads")
}

func TestCommentRejectsBadInput(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "the article\n", "")
	now, h := at(2)

	_, err := w.Comment(alice, now, h, "Missing page", "hi\n", 0)
	uassert.ErrorIs(t, err, ErrNoSuchPage, "a discussion needs a page to be about")

	_, err = w.Comment(alice, now, h, "A", "", 0)
	uassert.ErrorIs(t, err, ErrEmptyComment)

	_, err = w.Comment(alice, now, h, "A", strings.Repeat("x", MaxCommentLen+1), 0)
	uassert.ErrorIs(t, err, ErrCommentTooLong)

	_, err = w.Comment(alice, now, h, "A", "hi\n", 999)
	uassert.ErrorIs(t, err, ErrNoSuchComment)
}

// TestRepliesNestOneLevel pins MaxReplyDepth. Unbounded nesting means
// unbounded recursive rendering, which is the shape the query gas ceiling
// punishes hardest.
func TestRepliesNestOneLevel(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "the article\n", "")
	root := comment(t, w, 2, alice, "A", "root\n", 0)
	reply := comment(t, w, 3, bob, "A", "reply\n", root.ID)

	now, h := at(4)
	_, err := w.Comment(mod, now, h, "A", "reply to a reply\n", reply.ID)
	uassert.ErrorIs(t, err, ErrReplyToReply)
}

func TestHideComment(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "the article\n", "")
	before := w.Stats().BytesHeld
	c := comment(t, w, 2, bob, "A", "unpleasant\n", 0)
	uassert.Equal(t, before+len("unpleasant\n"), w.Stats().BytesHeld,
		"a comment costs its author the bytes it adds")

	released, err := w.HideComment("A", c.ID)
	uassert.NoError(t, err)
	uassert.Equal(t, len("unpleasant\n"), released)
	uassert.Equal(t, before, w.Stats().BytesHeld)

	threads := w.Comments(MustParseTitle("A"), 0, 10)
	uassert.Equal(t, 1, len(threads), "a hidden message stays in the thread")
	uassert.True(t, threads[0].Root.Hidden)
	uassert.Equal(t, "", threads[0].Root.Body)

	// Hiding twice must not double-count the refund.
	released, err = w.HideComment("A", c.ID)
	uassert.NoError(t, err)
	uassert.Equal(t, 0, released)
	uassert.Equal(t, before, w.Stats().BytesHeld)
}

func TestRenderTalk(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "the article\n", "")
	root := comment(t, w, 2, alice, "A", "Is [[B]] the right link?\n", 0)
	comment(t, w, 3, bob, "A", "Yes.\n", root.ID)
	hidden := comment(t, w, 4, mod, "A", "spam\n", 0)
	w.HideComment("A", hidden.ID)

	p, _ := w.Page("A")
	c := Ctx{Base: "/r/moul/x/wiki/v0", Exists: w.Exists}
	out := RenderTalk(c, w, p, 0, 10, act)

	uassert.True(t, strings.Contains(out, "# Discussion: A"))
	uassert.True(t, strings.Contains(out, "func=Comment"), "an add-a-message action")
	uassert.True(t, strings.Contains(out, "Yes."), "replies render under their root")
	uassert.True(t, strings.Contains(out, "removed by a steward"))
	uassert.False(t, strings.Contains(out, "spam"), "a hidden body is gone from the render")

	// A comment is user markdown too: it goes through the sanitizer, and it
	// is NOT a wikilink slot, so brackets stay literal rather than linking.
	uassert.True(t, strings.Contains(out, `\[\[B\]\]`), out)
}

func TestRenderTalkEmpty(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "the article\n", "")
	p, _ := w.Page("A")
	out := RenderTalk(Ctx{Base: "/r/moul/x/wiki/v0"}, w, p, 0, 10, nil)
	uassert.True(t, strings.Contains(out, "No messages yet"))
}

func TestArticleLinksToItsDiscussion(t *testing.T) {
	w := New(3, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "the article\n", "")
	comment(t, w, 2, alice, "A", "hi\n", 0)

	p, _ := w.Page("A")
	out := RenderArticle(Ctx{Base: "/r/moul/x/wiki/v0"}, w, p, nil)
	uassert.True(t, strings.Contains(out, "[discussion](/r/moul/x/wiki/v0:A/talk) (1)"), out)
}
