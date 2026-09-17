// Package forge is the domain engine of an on-chain software forge: repos,
// roles, an append-only reference log, issues and change requests (pull
// requests), with no chain imports of its own.
//
// What it does NOT do, on purpose: store blobs, trees or packfiles. Git objects
// stay wherever git already puts them (a mirror, an IPFS CID, a peer) and this
// package records what a forge is actually trusted for and what git alone does
// not authenticate:
//
//  1. which object id a ref points at, in what order it got there, and who said
//     so: an append-only, hash-chained reference log (the same shape as
//     gittuf's reference state log, with consensus playing the notary);
//  2. who is allowed to move which ref, and under what review policy;
//  3. the social layer: issues, change requests, reviews: bound to addresses
//     rather than to platform accounts;
//  4. the merge decision itself, recorded as one more entry in the same log.
//
// The chain cannot see the object graph, so it cannot verify that a new tip
// descends from the old one. It does not pretend to: every ref move is a
// compare-and-swap against the tip the caller expected (git's
// --force-with-lease, moved somewhere the forge operator cannot rewrite), any
// move that abandons that discipline is recorded as a force, and ancestry is
// checked by a client that has the objects. Ordering, attribution and policy
// are on chain; proof is local.
//
// All state lives in avl trees so every listing is ordered and paginatable, and
// every mutation takes the actor and the block height from the caller: the
// package is pure, deterministic and unit-testable without a chain.
//
// Live demo: gno.land/r/moul/forge/v0.
package forge

import (
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// Role is a repo-scoped capability level. Roles are totally ordered: every
// check is "at least this role", so there is one comparison to audit.
type Role int

const (
	RoleNone       Role = iota // not a member
	RoleReader                 // explicit read (all repos are public in v0)
	RoleWriter                 // move non-protected refs, update own changes
	RoleMaintainer             // force-move refs, merge changes, triage issues
	RoleAdmin                  // manage members and repo settings
	RoleOwner                  // admin + transfer; at least one always exists
)

// String renders the role as the lowercase token used by the realm API.
func (r Role) String() string {
	switch r {
	case RoleReader:
		return "reader"
	case RoleWriter:
		return "writer"
	case RoleMaintainer:
		return "maintainer"
	case RoleAdmin:
		return "admin"
	case RoleOwner:
		return "owner"
	default:
		return "none"
	}
}

// ParseRole is the inverse of Role.String.
func ParseRole(s string) (Role, error) {
	switch s {
	case "none":
		return RoleNone, nil
	case "reader":
		return RoleReader, nil
	case "writer":
		return RoleWriter, nil
	case "maintainer":
		return RoleMaintainer, nil
	case "admin":
		return RoleAdmin, nil
	case "owner":
		return RoleOwner, nil
	}
	return RoleNone, ErrInvalidRole
}

// Forge is the top-level registry: repo id -> repo.
type Forge struct {
	repos *avl.Tree // "<namespace>/<name>" -> *Repo
}

// New returns an empty forge.
func New() *Forge {
	return &Forge{repos: avl.NewTree()}
}

// Repo is one repository. Nothing here is the code: Mirrors says where the
// objects can be fetched, Refs says what the objects are supposed to be.
type Repo struct {
	ID          string // "<namespace>/<name>", immutable
	Description string
	DefaultRef  string // fully-qualified, e.g. "refs/heads/main"
	Mirrors     []string
	ParentID    string // fork lineage, "" for a root repo
	CreatedAt   int64  // block height
	Archived    bool

	// Merge policy.
	RequiredApprovals int  // approvals needed to merge a change
	AllowSelfApproval bool // may the change author's own approval count

	members *avl.Tree // address string -> Role
	refs    *avl.Tree // ref name -> *Ref
	log     *avl.Tree // padded seq -> *LogEntry (append-only)
	issues  *avl.Tree // padded id -> *Issue
	changes *avl.Tree // padded id -> *Change

	head       string // digest of the last log entry ("" when the log is empty)
	nextSeq    int64
	nextIssue  int64
	nextChange int64
}

// CreateRepo registers a repo owned by actor.
func (f *Forge) CreateRepo(actor address, height int64, id, description, defaultRef string) (*Repo, error) {
	if !ValidRepoID(id) {
		return nil, ErrInvalidRepoID
	}
	if !ValidText(description, MaxDescLen) {
		return nil, ErrInvalidText
	}
	if defaultRef == "" {
		defaultRef = "refs/heads/main"
	}
	if !ValidRefName(defaultRef) {
		return nil, ErrInvalidRefName
	}
	if f.repos.Has(id) {
		return nil, ErrRepoExists
	}
	r := &Repo{
		ID:                id,
		Description:       description,
		DefaultRef:        defaultRef,
		CreatedAt:         height,
		RequiredApprovals: 1,
		members:           avl.NewTree(),
		refs:              avl.NewTree(),
		log:               avl.NewTree(),
		issues:            avl.NewTree(),
		changes:           avl.NewTree(),
	}
	r.members.Set(actor.String(), RoleOwner)
	f.repos.Set(id, r)
	return r, nil
}

// Fork registers newID as a fork of srcID and copies the parent's current refs
// into the child's log, so the fork records exactly what it forked from. The
// objects are not copied: they never were on chain: so the child inherits the
// parent's mirrors as its initial fetch locators.
func (f *Forge) Fork(actor address, height int64, srcID, newID string) (*Repo, error) {
	src := f.Repo(srcID)
	if src == nil {
		return nil, ErrRepoNotFound
	}
	child, err := f.CreateRepo(actor, height, newID, src.Description, src.DefaultRef)
	if err != nil {
		return nil, err
	}
	child.ParentID = srcID
	child.Mirrors = append([]string{}, src.Mirrors...)
	note := "fork of " + srcID + " at seq " + strconv.FormatInt(src.nextSeq, 10)
	if len(note) > MaxNoteLen {
		note = "fork of " + srcID
	}
	n := 0
	src.refs.Iterate("", "", func(key string, value any) bool {
		ref := value.(*Ref)
		child.appendLog(actor, height, ref.Name, "", ref.OID, KindCreate, 0, note)
		child.refs.Set(ref.Name, &Ref{Name: ref.Name, OID: ref.OID, UpdatedAt: height, UpdatedBy: actor})
		n++
		return n >= 32 // a fork records a snapshot, not an unbounded copy
	})
	return child, nil
}

// Repo returns the repo, or nil.
func (f *Forge) Repo(id string) *Repo {
	v := f.repos.Get(id)
	if v == nil {
		return nil
	}
	return v.(*Repo)
}

// HasRepo reports whether the id is taken.
func (f *Forge) HasRepo(id string) bool { return f.repos.Has(id) }

// Size is the number of repos.
func (f *Forge) Size() int { return f.repos.Size() }

// IterateRepos walks repos in id order, newest-last, and stops when cb returns
// true. offset/count page the walk; count <= 0 means "to the end".
func (f *Forge) IterateRepos(offset, count int, cb func(*Repo) bool) {
	if count <= 0 {
		count = f.repos.Size()
	}
	f.repos.IterateByOffset(offset, count, func(_ string, value any) bool {
		return cb(value.(*Repo))
	})
}

// IterateNamespace walks the repos of one namespace in id order.
func (f *Forge) IterateNamespace(ns string, cb func(*Repo) bool) {
	f.repos.Iterate(ns+"/", ns+"0", func(_ string, value any) bool { // '0' is '/'+1
		return cb(value.(*Repo))
	})
}

// RoleOf returns the member's role, RoleNone when not a member.
func (r *Repo) RoleOf(a address) Role {
	v := r.members.Get(a.String())
	if v == nil {
		return RoleNone
	}
	return v.(Role)
}

// Can reports whether a holds at least the given role.
func (r *Repo) Can(a address, min Role) bool { return r.RoleOf(a) >= min }

// MemberCount is the number of members with an explicit role.
func (r *Repo) MemberCount() int { return r.members.Size() }

// IterateMembers walks members in address order.
func (r *Repo) IterateMembers(cb func(addr string, role Role) bool) {
	r.members.Iterate("", "", func(key string, value any) bool {
		return cb(key, value.(Role))
	})
}

// SetMember grants or revokes a role. Admins manage members; only an owner may
// mint another owner, and the last owner cannot be demoted: a repo with no
// owner is a repo nobody can ever unarchive.
func (r *Repo) SetMember(actor address, target address, role Role) error {
	if role < RoleNone || role > RoleOwner {
		return ErrInvalidRole
	}
	if !r.Can(actor, RoleAdmin) {
		return ErrUnauthorized
	}
	if role == RoleOwner && !r.Can(actor, RoleOwner) {
		return ErrUnauthorized
	}
	cur := r.RoleOf(target)
	if cur == RoleOwner && role != RoleOwner {
		if !r.Can(actor, RoleOwner) {
			return ErrUnauthorized // an admin cannot demote an owner
		}
		if r.ownerCount() == 1 {
			return ErrLastOwner
		}
	}
	if role == RoleNone {
		r.members.Remove(target.String())
		return nil
	}
	r.members.Set(target.String(), role)
	return nil
}

func (r *Repo) ownerCount() int {
	n := 0
	r.members.Iterate("", "", func(_ string, value any) bool {
		if value.(Role) == RoleOwner {
			n++
		}
		return false
	})
	return n
}

// SetDescription updates the one-line description.
func (r *Repo) SetDescription(actor address, description string) error {
	if !r.Can(actor, RoleAdmin) {
		return ErrUnauthorized
	}
	if !ValidText(description, MaxDescLen) {
		return ErrInvalidText
	}
	r.Description = description
	return nil
}

// SetMirrors replaces the fetch locators. The first one is the canonical
// remote; the rest are fallbacks. The chain records them, it never fetches.
func (r *Repo) SetMirrors(actor address, mirrors []string) error {
	if !r.Can(actor, RoleMaintainer) {
		return ErrUnauthorized
	}
	if len(mirrors) > MaxMirrors {
		return ErrTooMany
	}
	for _, m := range mirrors {
		if !ValidMirror(m) {
			return ErrInvalidMirror
		}
	}
	r.Mirrors = append([]string{}, mirrors...)
	return nil
}

// SetDefaultRef points the repo at another default branch.
func (r *Repo) SetDefaultRef(actor address, name string) error {
	if !r.Can(actor, RoleMaintainer) {
		return ErrUnauthorized
	}
	if !ValidRefName(name) {
		return ErrInvalidRefName
	}
	r.DefaultRef = name
	return nil
}

// SetPolicy sets the merge policy: how many approvals a change needs, and
// whether the author's own approval counts.
func (r *Repo) SetPolicy(actor address, requiredApprovals int, allowSelfApproval bool) error {
	if !r.Can(actor, RoleAdmin) {
		return ErrUnauthorized
	}
	if requiredApprovals < 0 || requiredApprovals > 16 {
		return ErrTooMany
	}
	r.RequiredApprovals = requiredApprovals
	r.AllowSelfApproval = allowSelfApproval
	return nil
}

// SetArchived freezes (or unfreezes) the repo. An archived repo takes no
// mutation except unarchiving: the log stays readable forever.
func (r *Repo) SetArchived(actor address, archived bool) error {
	if !r.Can(actor, RoleAdmin) {
		return ErrUnauthorized
	}
	r.Archived = archived
	return nil
}

// Counts for rendering.
func (r *Repo) RefCount() int    { return r.refs.Size() }
func (r *Repo) IssueCount() int  { return r.issues.Size() }
func (r *Repo) ChangeCount() int { return r.changes.Size() }

// seqKey zero-pads an id to a fixed width so avl keys sort numerically.
// ufmt has no width flags in gno, so the padding is done by hand: "%016d"
// silently returns the bare number and would sort 10 before 2.
func seqKey(n int64) string {
	s := strconv.FormatInt(n, 10)
	if len(s) >= 16 {
		return s
	}
	return strings.Repeat("0", 16-len(s)) + s
}
