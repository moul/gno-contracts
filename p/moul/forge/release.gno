package forge

import "strings"

// Size caps for a release.
const (
	MaxTagLen     = 64
	MaxRelNameLen = 200
	MaxNotesLen   = 8192
)

// Release is a named point in a repo's history, with notes.
//
// A tag ref already says "this name points at this object". A release says why
// anyone should care: what changed, whether it is ready, and which deployed
// package paths came out of it. That last part is the one an explorer wants,
// and it is also the only honest bridge between a git object id and an on-chain
// deploy, because the chain cannot verify either against the other.
type Release struct {
	Tag        string // "v1.2.0", the key; immutable once cut
	Name       string // human title, may be empty
	Notes      string // markdown, may be empty
	OID        string // the object this release names
	Ref        string // the tag ref, "" if the release does not have one
	Prerelease bool
	CreatedAt  int64 // block height
	CreatedBy  address
	Yanked     bool // withdrawn; kept, because a version that existed cannot un-exist
	YankReason string
}

// ValidTag reports whether s is usable as a release tag.
//
// Not semver-enforcing: gno.land's own packages version as v0, v1 with no minor
// or patch, and a forge that refused those would refuse its own ecosystem.
// Ordering is therefore lexical over a padded form, not semantic, and
// LatestRelease says so.
func ValidTag(s string) bool {
	if s == "" || len(s) > MaxTagLen {
		return false
	}
	if strings.Contains(s, "..") || strings.Contains(s, "/") {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_' || c == '+'
		if !ok {
			return false
		}
	}
	return true
}

// CutRelease records a release. The tag is the key and cannot be re-cut: a
// consumer that pinned v1.2.0 and got different bytes later has been lied to,
// and the whole point of a tag is that it does not move. Withdrawing one is
// YankRelease, which leaves it visible.
func (r *Repo) CutRelease(actor address, height int64, tag, name, notes, oid, ref string, prerelease bool) (*Release, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	if !r.Can(actor, RoleWriter) {
		return nil, ErrUnauthorized
	}
	if !ValidTag(tag) {
		return nil, ErrInvalidTag
	}
	if !ValidText(name, MaxRelNameLen) || !ValidText(notes, MaxNotesLen) {
		return nil, ErrInvalidText
	}
	if oid != "" && !ValidOID(oid) {
		return nil, ErrInvalidOID
	}
	if ref != "" && !ValidRefName(ref) {
		return nil, ErrInvalidRefName
	}
	if r.releases.Has(tag) {
		return nil, ErrReleaseExists
	}

	rel := &Release{
		Tag:        tag,
		Name:       name,
		Notes:      notes,
		OID:        oid,
		Ref:        ref,
		Prerelease: prerelease,
		CreatedAt:  height,
		CreatedBy:  actor,
	}
	r.releases.Set(tag, rel)
	r.releaseOrder.Set(seqKey(int64(r.releases.Size())), tag)
	return rel, nil
}

// YankRelease marks a release withdrawn without deleting it.
//
// Deleting would make a pinned version silently vanish, which reads to a
// consumer as "this was never published" rather than "do not use this".
func (r *Repo) YankRelease(actor address, tag, reason string) error {
	if !r.Can(actor, RoleWriter) {
		return ErrUnauthorized
	}
	if !ValidText(reason, MaxNoteLen) {
		return ErrInvalidText
	}
	v := r.releases.Get(tag)
	if v == nil {
		return ErrReleaseNotFound
	}
	rel := v.(*Release)
	rel.Yanked = true
	rel.YankReason = reason
	return nil
}

// Release returns one release by tag, or nil.
func (r *Repo) Release(tag string) *Release {
	v := r.releases.Get(tag)
	if v == nil {
		return nil
	}
	return v.(*Release)
}

// ReleaseCount is how many releases this repo has cut, yanked ones included.
func (r *Repo) ReleaseCount() int { return r.releases.Size() }

// IterateReleases walks releases newest-cut first.
//
// Cut order, not tag order: tags are not required to be semver here (gno.land's
// own packages are v0 and v1), so there is no total order to sort by that would
// not be wrong for somebody. When they were cut is a fact the forge does know.
func (r *Repo) IterateReleases(offset, count int, cb func(*Release) bool) {
	if count <= 0 {
		count = r.releaseOrder.Size()
	}
	r.releaseOrder.ReverseIterateByOffset(offset, count, func(_ string, v any) bool {
		rel := r.releases.Get(v.(string))
		if rel == nil {
			return false
		}
		return cb(rel.(*Release))
	})
}

// LatestRelease is the most recently cut release that is neither a prerelease
// nor yanked, or nil. "Most recently cut", never "highest version": see
// IterateReleases.
func (r *Repo) LatestRelease() *Release {
	var out *Release
	r.IterateReleases(0, 0, func(rel *Release) bool {
		if rel.Prerelease || rel.Yanked {
			return false
		}
		out = rel
		return true
	})
	return out
}
