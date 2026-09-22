package forge

import "gno.land/p/nt/avl/v0"

// Issue is a discussion thread bound to a repo. Anyone with an address may open
// one: the spam gate is not a moderator, it is that the author pays gas and
// locks the storage deposit for every byte they write.
type Issue struct {
	ID        int64
	Title     string
	Body      string
	Author    address
	Open      bool
	Labels    []string
	CreatedAt int64
	UpdatedAt int64

	comments    *avl.Tree // padded id -> *Comment
	nextComment int64
}

// Comment is one reply, on an issue or on a change request.
type Comment struct {
	ID        int64
	Author    address
	Body      string
	CreatedAt int64
}

// OpenIssue files an issue. Permissionless by design.
func (r *Repo) OpenIssue(actor address, height int64, title, body string, labels []string) (*Issue, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	if title == "" || !ValidLine(title, MaxTitleLen) {
		return nil, ErrInvalidText
	}
	if !ValidText(body, MaxBodyLen) {
		return nil, ErrInvalidText
	}
	if err := checkLabels(labels); err != nil {
		return nil, err
	}
	i := &Issue{
		ID:        r.nextIssue,
		Title:     title,
		Body:      body,
		Author:    actor,
		Open:      true,
		Labels:    append([]string{}, labels...),
		CreatedAt: height,
		UpdatedAt: height,
		comments:  avl.NewTree(),
	}
	r.issues.Set(seqKey(i.ID), i)
	r.nextIssue++
	return i, nil
}

// CommentIssue appends a reply. Closed issues still take comments (closing is a
// triage state, not a gag); an archived repo takes none.
func (r *Repo) CommentIssue(actor address, height, id int64, body string) (*Comment, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	i := r.Issue(id)
	if i == nil {
		return nil, ErrIssueNotFound
	}
	if body == "" || !ValidText(body, MaxCommentLen) {
		return nil, ErrInvalidText
	}
	c := &Comment{ID: i.nextComment, Author: actor, Body: body, CreatedAt: height}
	i.comments.Set(seqKey(c.ID), c)
	i.nextComment++
	i.UpdatedAt = height
	return c, nil
}

// SetIssueOpen closes or reopens an issue. The author can always close their
// own; maintainers can close anyone's.
func (r *Repo) SetIssueOpen(actor address, height, id int64, open bool) error {
	if r.Archived {
		return ErrRepoArchived
	}
	i := r.Issue(id)
	if i == nil {
		return ErrIssueNotFound
	}
	if i.Author != actor && !r.Can(actor, RoleMaintainer) {
		return ErrUnauthorized
	}
	i.Open = open
	i.UpdatedAt = height
	return nil
}

// SetIssueLabels replaces an issue's labels. Triage is a maintainer action.
func (r *Repo) SetIssueLabels(actor address, height, id int64, labels []string) error {
	if r.Archived {
		return ErrRepoArchived
	}
	i := r.Issue(id)
	if i == nil {
		return ErrIssueNotFound
	}
	if !r.Can(actor, RoleMaintainer) {
		return ErrUnauthorized
	}
	if err := checkLabels(labels); err != nil {
		return err
	}
	i.Labels = append([]string{}, labels...)
	i.UpdatedAt = height
	return nil
}

// Issue returns an issue by id, or nil.
func (r *Repo) Issue(id int64) *Issue {
	v := r.issues.Get(seqKey(id))
	if v == nil {
		return nil
	}
	return v.(*Issue)
}

// IterateIssues walks issues newest-first.
func (r *Repo) IterateIssues(offset, count int, cb func(*Issue) bool) {
	if count <= 0 {
		count = r.issues.Size()
	}
	r.issues.ReverseIterateByOffset(offset, count, func(_ string, value any) bool {
		return cb(value.(*Issue))
	})
}

// OpenIssueCount counts issues still open.
func (r *Repo) OpenIssueCount() int {
	n := 0
	r.issues.Iterate("", "", func(_ string, value any) bool {
		if value.(*Issue).Open {
			n++
		}
		return false
	})
	return n
}

// CommentCount is the number of replies on the issue.
func (i *Issue) CommentCount() int { return i.comments.Size() }

// IterateComments walks replies oldest-first.
func (i *Issue) IterateComments(offset, count int, cb func(*Comment) bool) {
	if count <= 0 {
		count = i.comments.Size()
	}
	i.comments.IterateByOffset(offset, count, func(_ string, value any) bool {
		return cb(value.(*Comment))
	})
}

func checkLabels(labels []string) error {
	if len(labels) > MaxLabels {
		return ErrTooMany
	}
	for _, l := range labels {
		if !ValidLabel(l) {
			return ErrInvalidText
		}
	}
	return nil
}
