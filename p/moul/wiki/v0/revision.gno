package wiki

import (
	"crypto/sha256"
	"encoding/hex"
	"time"
)

// Kind labels what a revision did, for the recent-changes feed.
type Kind string

const (
	KindCreate  Kind = "create"
	KindEdit    Kind = "edit"
	KindRevert  Kind = "revert"
	KindMove    Kind = "move"
	KindBlank   Kind = "blank"
	KindProtect Kind = "protect"
)

// Revision is one entry in a page's append-only history.
//
// The exported fields are the permanent spine: they are never evicted, and
// they are what makes the history tamper-evident. Hash is the SHA-256 of the
// body bytes as submitted, so a body recovered from transaction history can be
// checked against the chain's own record of it.
//
// body is the only field under a retention policy. When a revision falls out
// of the page's body window it is evicted, which releases the storage deposit
// those bytes locked.
type Revision struct {
	ID      uint64
	Prev    uint64 // 0 for the first revision of a page
	Kind    Kind
	Author  address
	Time    time.Time
	Height  int64
	Summary string
	Hash    string // hex-encoded SHA-256 of the body
	Size    int    // body length in bytes
	Minor   bool

	body string
	kept bool
}

// Body returns the revision's text and whether it is still held on chain. A
// false second return is not corruption: the body aged out of the retention
// window and must be recovered from the transaction that wrote it, then
// checked against Hash.
func (r *Revision) Body() (string, bool) { return r.body, r.kept }

// Kept reports whether this revision's body is still on chain.
func (r *Revision) Kept() bool { return r.kept }

// evict drops the body and returns the number of bytes released.
func (r *Revision) evict() int {
	if !r.kept {
		return 0
	}
	n := len(r.body)
	r.body = ""
	r.kept = false
	return n
}

// hashBody is the content address of a revision body.
func hashBody(body string) string {
	sum := sha256.Sum256([]byte(body))
	return hex.EncodeToString(sum[:])
}

// ShortHash is the first 12 hex characters of Hash, for display.
func (r *Revision) ShortHash() string {
	if len(r.Hash) < 12 {
		return r.Hash
	}
	return r.Hash[:12]
}

// Change is a recent-changes entry: a revision plus the page it landed on.
type Change struct {
	Title Title
	Rev   *Revision
}
