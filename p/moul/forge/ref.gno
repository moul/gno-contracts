package forge

import (
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"
)

// Log entry kinds.
const (
	KindCreate = "create" // a ref that did not exist now points somewhere
	KindUpdate = "update" // compare-and-swap succeeded
	KindForce  = "force"  // the tip was replaced without a matching expectation
	KindDelete = "delete" // the ref is gone (the log is not)
	KindMerge  = "merge"  // an update performed by merging a change request
)

// Ref is the current state of one reference. The history of how it got here is
// in the repo log, which nothing can rewrite.
type Ref struct {
	Name      string
	OID       string
	UpdatedAt int64
	UpdatedBy address
}

// LogEntry is one link of the repo's reference log. The log is append-only and
// hash-chained: Digest commits to every earlier entry, so publishing a single
// digest (in a release note, a package manifest, a tweet) pins the entire
// history of every ref up to that point.
type LogEntry struct {
	Seq      int64
	Ref      string
	OldOID   string // "" when the ref did not exist
	NewOID   string // "" on delete
	Actor    address
	Height   int64
	Kind     string
	ChangeID int64 // the merged change, 0 otherwise
	Note     string
	Digest   string // hex sha256 over the previous digest and this entry
}

// EntryDigest computes the chain digest of e given the previous entry's digest.
// It is exported so an off-chain verifier can recompute the chain byte for byte
// from the values it read back; the field order below is the wire format and
// must not change within a version.
func EntryDigest(prev string, e *LogEntry) string {
	fields := []string{
		prev,
		strconv.FormatInt(e.Seq, 10),
		e.Ref,
		e.OldOID,
		e.NewOID,
		e.Actor.String(),
		strconv.FormatInt(e.Height, 10),
		e.Kind,
		strconv.FormatInt(e.ChangeID, 10),
		e.Note,
	}
	sum := sha256.Sum256([]byte(strings.Join(fields, "\n")))
	return hex.EncodeToString(sum[:])
}

// appendLog writes one entry and advances the chain head. Callers have already
// authorized and validated; this never fails.
func (r *Repo) appendLog(actor address, height int64, ref, oldOID, newOID, kind string, changeID int64, note string) *LogEntry {
	e := &LogEntry{
		Seq:      r.nextSeq,
		Ref:      ref,
		OldOID:   oldOID,
		NewOID:   newOID,
		Actor:    actor,
		Height:   height,
		Kind:     kind,
		ChangeID: changeID,
		Note:     note,
	}
	e.Digest = EntryDigest(r.head, e)
	r.log.Set(seqKey(e.Seq), e)
	r.head = e.Digest
	r.nextSeq++
	return e
}

// SetRef moves a ref by compare-and-swap: expectedOID must be the tip the
// caller last saw ("" to create a ref that does not exist yet). This is git's
// --force-with-lease, except the lease is held by consensus rather than by the
// server you are pushing to, so a concurrent push cannot be silently lost and a
// rewritten history cannot be presented as if it had always been that way.
//
// The chain cannot check that newOID descends from expectedOID: it has no
// objects. That check belongs to a client holding the repo, which is exactly
// why every move is recorded rather than merely applied.
func (r *Repo) SetRef(actor address, height int64, name, expectedOID, newOID, note string) (*LogEntry, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	if !r.Can(actor, RoleWriter) {
		return nil, ErrUnauthorized
	}
	if !ValidRefName(name) {
		return nil, ErrInvalidRefName
	}
	if !ValidOID(newOID) {
		return nil, ErrInvalidOID
	}
	if !ValidLine(note, MaxNoteLen) {
		return nil, ErrInvalidText
	}
	cur := r.Ref(name)
	switch {
	case cur == nil && expectedOID != "":
		return nil, ErrRefNotFound
	case cur != nil && expectedOID == "":
		return nil, ErrRefExists
	case cur != nil && cur.OID != expectedOID:
		return nil, ErrStaleRef
	case cur != nil && cur.OID == newOID:
		return nil, ErrSameOID
	}
	kind := KindUpdate
	old := ""
	if cur == nil {
		kind = KindCreate
	} else {
		old = cur.OID
	}
	r.refs.Set(name, &Ref{Name: name, OID: newOID, UpdatedAt: height, UpdatedBy: actor})
	return r.appendLog(actor, height, name, old, newOID, kind, 0, note), nil
}

// ForceSetRef moves a ref without an expectation. It needs RoleMaintainer and
// is permanently recorded as KindForce: the point is not to forbid a force-push
// (sometimes it is the right call) but to make one impossible to hide.
func (r *Repo) ForceSetRef(actor address, height int64, name, newOID, note string) (*LogEntry, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	if !r.Can(actor, RoleMaintainer) {
		return nil, ErrUnauthorized
	}
	if !ValidRefName(name) {
		return nil, ErrInvalidRefName
	}
	if !ValidOID(newOID) {
		return nil, ErrInvalidOID
	}
	if !ValidLine(note, MaxNoteLen) {
		return nil, ErrInvalidText
	}
	old := ""
	if cur := r.Ref(name); cur != nil {
		if cur.OID == newOID {
			return nil, ErrSameOID
		}
		old = cur.OID
	}
	r.refs.Set(name, &Ref{Name: name, OID: newOID, UpdatedAt: height, UpdatedBy: actor})
	return r.appendLog(actor, height, name, old, newOID, KindForce, 0, note), nil
}

// DeleteRef removes a ref by compare-and-swap. The ref disappears from the
// current state; the log keeps every object it ever pointed at.
//
// Maintainer-only for an economic reason as much as a safety one: on gno.land
// the storage-deposit refund goes to whoever frees the bytes, not to whoever
// paid for them (`receiver := caller` in the vm keeper's deposit path, gno
// master 2026-09-19), so an open delete path pays for vandalism.
func (r *Repo) DeleteRef(actor address, height int64, name, expectedOID, note string) (*LogEntry, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	if !r.Can(actor, RoleMaintainer) {
		return nil, ErrUnauthorized
	}
	if !ValidLine(note, MaxNoteLen) {
		return nil, ErrInvalidText
	}
	cur := r.Ref(name)
	if cur == nil {
		return nil, ErrRefNotFound
	}
	if cur.OID != expectedOID {
		return nil, ErrStaleRef
	}
	if name == r.DefaultRef {
		return nil, ErrUnauthorized // the default branch is not deletable
	}
	r.refs.Remove(name)
	return r.appendLog(actor, height, name, cur.OID, "", KindDelete, 0, note), nil
}

// Ref returns the current state of a ref, or nil.
func (r *Repo) Ref(name string) *Ref {
	v := r.refs.Get(name)
	if v == nil {
		return nil
	}
	return v.(*Ref)
}

// IterateRefs walks refs in name order.
func (r *Repo) IterateRefs(cb func(*Ref) bool) {
	r.refs.Iterate("", "", func(_ string, value any) bool {
		return cb(value.(*Ref))
	})
}

// LogHead is the digest of the last entry, "" for an empty log. Pin this value
// anywhere off chain and the whole history becomes falsifiable.
func (r *Repo) LogHead() string { return r.head }

// LogSize is the number of entries ever appended.
func (r *Repo) LogSize() int { return r.log.Size() }

// LogEntryAt returns one entry by sequence number, or nil.
func (r *Repo) LogEntryAt(seq int64) *LogEntry {
	v := r.log.Get(seqKey(seq))
	if v == nil {
		return nil
	}
	return v.(*LogEntry)
}

// IterateLog walks the log oldest-first.
func (r *Repo) IterateLog(offset, count int, cb func(*LogEntry) bool) {
	if count <= 0 {
		count = r.log.Size()
	}
	r.log.IterateByOffset(offset, count, func(_ string, value any) bool {
		return cb(value.(*LogEntry))
	})
}

// IterateLogReverse walks the log newest-first, which is what a UI wants.
func (r *Repo) IterateLogReverse(offset, count int, cb func(*LogEntry) bool) {
	if count <= 0 {
		count = r.log.Size()
	}
	r.log.ReverseIterateByOffset(offset, count, func(_ string, value any) bool {
		return cb(value.(*LogEntry))
	})
}

// VerifyLog recomputes the whole digest chain and reports the first entry whose
// digest does not follow from its predecessor. It should be impossible on a
// live chain: it is here because a transparency log nobody can verify is just
// a log, and a client should be running this against the values it read back.
func (r *Repo) VerifyLog() (bool, int64) {
	prev := ""
	bad := int64(-1)
	r.log.Iterate("", "", func(_ string, value any) bool {
		e := value.(*LogEntry)
		if EntryDigest(prev, e) != e.Digest {
			bad = e.Seq
			return true
		}
		prev = e.Digest
		return false
	})
	return bad < 0, bad
}
