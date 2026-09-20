package wiki

import (
	"errors"
	"time"

	"gno.land/p/moul/ulist/v0"
	"gno.land/p/nt/avl/v0"
)

// MaxCommentLen bounds one comment in bytes.
const MaxCommentLen = 2000

// MaxReplyDepth is 1: a comment replies to a top-level comment, and that is
// all. Deeper nesting needs recursive rendering with no natural bound, which
// is exactly the shape a query gas ceiling punishes.
const MaxReplyDepth = 1

var (
	ErrCommentTooLong = errors.New("wiki: comment exceeds the size limit")
	ErrEmptyComment   = errors.New("wiki: empty comment")
	ErrNoSuchComment  = errors.New("wiki: no such comment")
	ErrReplyToReply   = errors.New("wiki: replies nest one level only")
)

// Comment is one message in a page's discussion.
//
// Discussion is a comment store rather than a "Talk:" article, which is the
// one place this design departs from MediaWiki on purpose. A talk page is an
// article, so the last editor can rewrite what someone else said, and
// moderating one bad message means editing the whole page. An append-only
// store gives each message its own author, its own timestamp and its own
// moderation, and nobody can silently rewrite anyone else's words.
type Comment struct {
	ID     uint64
	Parent uint64 // 0 for a top-level comment
	Author address
	Time   time.Time
	Height int64
	Body   string
	Hidden bool // a steward hid it; Body is cleared and its deposit released
}

// Comment appends a message to a page's discussion. replyTo is 0 for a
// top-level message, or the id of a top-level message to reply to.
//
// The engine does not decide who may comment: as with Edit, that is the
// realm's call. It does enforce the shape, because the shape is what bounds
// the render.
func (w *Wiki) Comment(author address, now time.Time, height int64, raw, body string, replyTo uint64) (*Comment, error) {
	t, err := ParseTitle(raw)
	if err != nil {
		return nil, err
	}
	if !w.Exists(t) {
		return nil, ErrNoSuchPage
	}
	if body == "" {
		return nil, ErrEmptyComment
	}
	if len(body) > MaxCommentLen {
		return nil, ErrCommentTooLong
	}

	list := w.thread(t, true)
	if replyTo != 0 {
		parent := findComment(list, replyTo)
		if parent == nil {
			return nil, ErrNoSuchComment
		}
		if parent.Parent != 0 {
			return nil, ErrReplyToReply
		}
	}

	w.nextComment++
	c := &Comment{
		ID:     w.nextComment,
		Parent: replyTo,
		Author: author,
		Time:   now,
		Height: height,
		Body:   body,
	}
	list.Append(c)
	w.numComments++
	w.bytesHeld += len(body)
	return c, nil
}

// HideComment clears one message's body and returns the bytes released. The
// message itself stays in the thread, so a deleted comment reads as "removed"
// rather than as a gap someone has to reconstruct from block explorers.
func (w *Wiki) HideComment(raw string, id uint64) (int, error) {
	t, err := ParseTitle(raw)
	if err != nil {
		return 0, err
	}
	list := w.thread(t, false)
	if list == nil {
		return 0, ErrNoSuchComment
	}
	c := findComment(list, id)
	if c == nil {
		return 0, ErrNoSuchComment
	}
	if c.Hidden {
		return 0, nil
	}
	n := len(c.Body)
	c.Body = ""
	c.Hidden = true
	w.bytesHeld -= n
	return n, nil
}

// Comments returns up to count top-level messages of a page's discussion,
// oldest first, skipping offset of them, each paired with its replies in the
// order they were written.
func (w *Wiki) Comments(t Title, offset, count int) []*Thread {
	out := []*Thread{}
	list := w.thread(t, false)
	if list == nil || count <= 0 {
		return out
	}

	// One pass to bucket replies by parent, a second to emit top-level
	// messages in order. Buckets live in an avl rather than a map because
	// this feeds a render, and gno map iteration order is unspecified.
	replies := avl.NewTree()
	list.Iterator(0, list.Size()-1, func(_ int, v any) bool {
		c := v.(*Comment)
		if c.Parent == 0 {
			return false
		}
		key := commentKey(c.Parent)
		var bucket []*Comment
		if b := replies.Get(key); b != nil {
			bucket = b.([]*Comment)
		}
		replies.Set(key, append(bucket, c))
		return false
	})

	skipped := 0
	list.Iterator(0, list.Size()-1, func(_ int, v any) bool {
		c := v.(*Comment)
		if c.Parent != 0 {
			return false
		}
		if skipped < offset {
			skipped++
			return false
		}
		th := &Thread{Root: c}
		if b := replies.Get(commentKey(c.ID)); b != nil {
			th.Replies = b.([]*Comment)
		}
		out = append(out, th)
		return len(out) >= count
	})
	return out
}

// Thread is a top-level comment and its replies.
type Thread struct {
	Root    *Comment
	Replies []*Comment
}

// NumComments returns how many messages a page's discussion holds, replies
// and hidden messages included.
func (w *Wiki) NumComments(t Title) int {
	list := w.thread(t, false)
	if list == nil {
		return 0
	}
	return list.Size()
}

// thread returns a page's comment list, creating it when create is set.
func (w *Wiki) thread(t Title, create bool) *ulist.List {
	v := w.talk.Get(t.Key())
	if v != nil {
		return v.(*ulist.List)
	}
	if !create {
		return nil
	}
	list := ulist.New()
	w.talk.Set(t.Key(), list)
	return list
}

func findComment(list *ulist.List, id uint64) *Comment {
	var found *Comment
	list.Iterator(0, list.Size()-1, func(_ int, v any) bool {
		c := v.(*Comment)
		if c.ID == id {
			found = c
			return true
		}
		return false
	})
	return found
}

// commentKey is only ever used as an avl key for reply buckets, where the
// order does not matter, so a plain decimal is fine here. Anything whose
// ordering IS meaningful needs a fixed-width key: see Title.Key.
func commentKey(id uint64) string {
	if id == 0 {
		return "0"
	}
	var b []byte
	for id > 0 {
		b = append([]byte{byte('0' + id%10)}, b...)
		id /= 10
	}
	return string(b)
}
