package forge

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func TestIssueLifecycle(t *testing.T) {
	_, r := newRepo(t)

	// Filing an issue needs no role: the gate is that the author pays for the
	// bytes they write.
	i, err := r.OpenIssue(eve, 200, "Render eats the last newline", "Steps:\n1. …", []string{"bug"})
	urequire.NoError(t, err)
	uassert.Equal(t, int64(0), i.ID)
	uassert.True(t, i.Open)
	uassert.Equal(t, eve.String(), i.Author.String())
	uassert.Equal(t, 1, r.IssueCount())
	uassert.Equal(t, 1, r.OpenIssueCount())

	c, err := r.CommentIssue(bob, 201, 0, "reproduced")
	urequire.NoError(t, err)
	uassert.Equal(t, int64(0), c.ID)
	uassert.Equal(t, 1, i.CommentCount())
	uassert.Equal(t, int64(201), i.UpdatedAt)

	// The author may close their own; a stranger may not close someone else's.
	uassert.ErrorIs(t, r.SetIssueOpen(carol, 202, 0, false), ErrUnauthorized)
	urequire.NoError(t, r.SetIssueOpen(eve, 202, 0, false))
	uassert.False(t, i.Open)
	uassert.Equal(t, 0, r.OpenIssueCount())

	// Closed is a triage state, not a gag.
	_, err = r.CommentIssue(eve, 203, 0, "still happening on pearl")
	urequire.NoError(t, err)

	// Maintainers can reopen and label.
	urequire.NoError(t, r.SetIssueOpen(bob, 204, 0, true))
	uassert.ErrorIs(t, r.SetIssueLabels(eve, 205, 0, []string{"p1"}), ErrUnauthorized)
	urequire.NoError(t, r.SetIssueLabels(bob, 205, 0, []string{"bug", "p1"}))
	uassert.Equal(t, 2, len(i.Labels))
}

func TestIssueValidation(t *testing.T) {
	_, r := newRepo(t)

	_, err := r.OpenIssue(eve, 200, "", "body", nil)
	uassert.ErrorIs(t, err, ErrInvalidText, "a title is required")
	_, err = r.OpenIssue(eve, 200, "two\nlines", "", nil)
	uassert.ErrorIs(t, err, ErrInvalidText, "a title is one line")
	_, err = r.OpenIssue(eve, 200, "ok", "", []string{"a,b"})
	uassert.ErrorIs(t, err, ErrInvalidText, "labels are comma-free")
	_, err = r.OpenIssue(eve, 200, "ok", "", []string{"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"})
	uassert.ErrorIs(t, err, ErrTooMany)

	_, err = r.CommentIssue(eve, 200, 7, "no such issue")
	uassert.ErrorIs(t, err, ErrIssueNotFound)
	uassert.ErrorIs(t, r.SetIssueOpen(bob, 200, 7, false), ErrIssueNotFound)

	urequire.NoError(t, func() error { _, err := r.OpenIssue(eve, 200, "ok", "", nil); return err }())
	_, err = r.CommentIssue(eve, 201, 0, "")
	uassert.ErrorIs(t, err, ErrInvalidText, "an empty comment is not a comment")
}

func TestIssueIterationIsNewestFirst(t *testing.T) {
	_, r := newRepo(t)
	for _, title := range []string{"first", "second", "third"} {
		_, err := r.OpenIssue(eve, 200, title, "", nil)
		urequire.NoError(t, err)
	}

	var got []string
	r.IterateIssues(0, 0, func(i *Issue) bool {
		got = append(got, i.Title)
		return false
	})
	uassert.Equal(t, "third,second,first", join(got))

	var page []string
	r.IterateIssues(1, 1, func(i *Issue) bool {
		page = append(page, i.Title)
		return false
	})
	uassert.Equal(t, "second", join(page))

	i := r.Issue(0)
	urequire.NotEqual(t, nil, i)
	for n := 0; n < 3; n++ {
		_, err := r.CommentIssue(eve, 201, 0, "ping")
		urequire.NoError(t, err)
	}
	var bodies []string
	i.IterateComments(0, 2, func(c *Comment) bool {
		bodies = append(bodies, c.Body)
		return false
	})
	uassert.Equal(t, "ping,ping", join(bodies))
}
