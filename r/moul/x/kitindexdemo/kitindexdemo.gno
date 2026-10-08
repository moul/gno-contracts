// untrusted-render: the tag is charset-checked to [a-z0-9-] at write time and
// is the only stored string interpolated raw; the body is a caller's text and
// goes through ui.Cell at every call site that renders it.

// Package kitindexdemo is a notes board whose only job is to show
// gno.land/p/moul/kit/index doing the thing a realm with a store always ends
// up needing: answering "every note tagged gno" as cheaply as it answers
// "note 7".
//
// There is no logic of its own here. The records are a kit/store, the two
// lookups are kit/index, the page is kit/ui, and what is worth reading is the
// shape: every write touches the store and both indexes in ONE function, which
// is the entire correctness argument for keeping them in separate containers.
//
// Demo of the p/moul/kit/index library.
package kitindexdemo

import (
	"chain/markdown"
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/moul/kit/index/v0"
	"gno.land/p/moul/kit/store/v0"
)

// MaxBody is the longest note this realm accepts, in bytes.
//
// A bound rather than none: every byte stored here locks a storage deposit,
// paid by whoever signs the write and refunded to whoever signs the delete
// (EFFECTIVE_GNO.md section 9.2), and an unbounded write is an unbounded
// state the realm carries forever.
const MaxBody = 280

// MaxTagLen bounds the index key for the same reason, and small because a tag
// is a label rather than a sentence.
const MaxTagLen = 24

// PageSize is how many tags the root page shows.
const PageSize = 20

// MaxNotes and MaxPerAuthor bound the WHOLE board, which MaxBody does not.
//
// A per-call length limit bounds one write and nothing else: a caller posting
// one-byte notes in a loop grows the store and both indexes without limit. "An unbounded container a third party can grow is an
// unbounded storage deposit someone is paying for" is a rule this realm exists
// to demonstrate, so it had better obey it.
//
// Two caps rather than one, and what each buys is narrower than it looks.
// MaxNotes bounds the state, which is the property this realm promises.
// MaxPerAuthor stops one ADDRESS, not one actor: addresses are free, so fifty
// fresh ones at twenty notes each still fill the board and lock everyone else
// out until somebody retracts. Keeping a board open to strangers needs
// something a griefer cannot mint for free, a deposit or an expiry, which this
// demo does not carry. Retracting frees a slot, so neither cap is a one-way door.
//
// MaxPerAuthor is answered by byAuthor.Count, which is the index doing the job
// it was added for.
const (
	MaxNotes     = 1000
	MaxPerAuthor = 20
)

type note struct {
	Author address
	Tag    string
	Body   string
	Height int64
}

var (
	notes    = store.Named("note")
	byTag    index.Index
	byAuthor index.Index
)

// Post files a note under a tag and returns its id.
//
// The store write and both index writes happen here, in this order, in one
// frame. An abort anywhere in it leaves none of them applied, which is what
// makes three containers safe to keep apart.
func Post(cur realm, tag, body string) int64 {
	who := caller(cur)
	tag = normaliseTag(tag)
	assertBody(body)
	assertRoom(who)

	id := notes.Add(&note{
		Author: who,
		Tag:    tag,
		Body:   body,
		Height: runtime.ChainHeight(),
	})
	mustIndex(byTag.Add(tag, id))
	mustIndex(byAuthor.Add(who.String(), id))
	return int64(id)
}

// Retract removes a note. Only its author may, and the store and both indexes
// are unwound together.
func Retract(cur realm, id int64) {
	who := caller(cur)
	sid, ok := store.ParseID(strconv.FormatInt(id, 10))
	if !ok {
		panic("kitindexdemo: not an id: " + strconv.FormatInt(id, 10))
	}
	n, ok := notes.Get(sid)
	if !ok {
		panic("kitindexdemo: note #" + sid.String() + " not found")
	}
	rec := n.(*note)
	if rec.Author != who {
		panic("kitindexdemo: note #" + sid.String() + " is not yours")
	}
	notes.Remove(sid)
	byTag.Remove(rec.Tag, sid)
	byAuthor.Remove(rec.Author.String(), sid)
}

// caller is the one place this realm decides who is acting: the realm token is
// checked before it is walked, because an unchecked token is not a caller.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("kitindexdemo: spoofed realm")
	}
	return cur.Previous().Address()
}

func mustIndex(err error) {
	if err != nil {
		panic(err)
	}
}

// normaliseTag lowercases and validates the tag.
//
// Validated at WRITE time rather than escaped at render time, deliberately: a
// tag is also an index key and a path segment, so a tag that could carry a
// pipe or a slash would break the table and the URL as well as the page. The
// charset is the narrowest thing that still reads as a label.
func normaliseTag(tag string) string {
	tag = strings.ToLower(strings.TrimSpace(tag))
	if tag == "" || len(tag) > MaxTagLen {
		panic("kitindexdemo: a tag is 1 to " + strconv.Itoa(MaxTagLen) + " characters")
	}
	for _, r := range tag {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '-':
		default:
			panic("kitindexdemo: a tag is [a-z0-9-], got " + strconv.Quote(tag))
		}
	}
	return tag
}

// assertRoom refuses a write the board has no room for, globally or for this
// address. Checked before the store write, so a refusal costs the caller the
// gas of three reads and nothing is half-applied.
func assertRoom(who address) {
	if notes.Len() >= MaxNotes {
		panic("kitindexdemo: the board is full at " + strconv.Itoa(MaxNotes) +
			" notes; retract one to free a slot")
	}
	if n := byAuthor.Count(who.String()); n >= MaxPerAuthor {
		panic("kitindexdemo: " + who.String() + " already has " + strconv.Itoa(n) +
			" notes, the limit is " + strconv.Itoa(MaxPerAuthor))
	}
}

func assertBody(body string) {
	if strings.TrimSpace(markdown.StripBidiAndZeroWidth(body)) == "" {
		panic("kitindexdemo: the body is empty")
	}
	if len(body) > MaxBody {
		panic("kitindexdemo: the body is " + strconv.Itoa(len(body)) +
			" bytes, the limit is " + strconv.Itoa(MaxBody))
	}
}
