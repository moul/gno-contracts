// Package forge is an on-chain software forge: repos, an append-only reference
// log, issues, change requests and reviews, browsable through gnoweb and
// writable only through signed transactions.
//
// It is the realm half of gno.land/p/moul/forge/v1, which holds the whole
// domain model; this file is wiring. Every exported mutation is a crossing
// function that resolves the caller, forwards to the library, aborts on error
// (the only way to revert state in gno) and emits an event for indexers.
//
// What the chain stores is NOT the code. Git objects stay in git (a mirror, an
// IPFS CID, a peer) and the realm records what a forge is actually trusted for:
// which object a ref points at, in what order, on whose authority, under
// what review policy, and what got merged. See the package README for the
// design, the threat model and what this deliberately does not do.
//
// A caller may be a user or another realm: a repo whose owner is a DAO realm is
// a repo whose merge button is a governance vote.
package forge

import (
	"chain"
	"chain/runtime"
	"errors"
	"strings"

	fg "gno.land/p/moul/forge/v1"
	"gno.land/r/sys/users"
)

// errForeignNamespace is the one rule this realm adds on top of the library:
// a namespace is yours or it is not.
var errForeignNamespace = errors.New("forge: namespace is not yours")

var f = fg.New()

// caller is the address that crossed into this realm. It is deliberately not
// restricted to end users: a realm holding a role is the point (see the doc
// comment above).
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("forge: spoofed realm")
	}
	return cur.Previous().Address()
}

func height() int64 { return runtime.ChainHeight() }

// repo resolves a repo id or aborts. Read paths use f.Repo directly and return
// a rendered "not found" instead.
func repo(id string) *fg.Repo {
	r := f.Repo(id)
	if r == nil {
		panic(fg.ErrRepoNotFound)
	}
	return r
}

// requireNamespace enforces the ownership rule. Two namespaces exist and they
// cannot collide, since an address is 40 characters and a name caps at 39:
//
//   - an address namespace ("g1.../forge") belongs to that account, always, with
//     nothing to register and nothing to lose;
//   - a name namespace ("moul/forge") belongs to whoever holds that name in
//     r/sys/users, including through a rename, since the lookup resolves aliases
//     to the same record.
//
// A realm caller passes the same way a user does, which is what makes a
// DAO-owned repo possible: the DAO's address is its namespace.
func requireNamespace(a address, id string) {
	ns, _, ok := fg.SplitRepoID(id)
	if !ok {
		panic(fg.ErrInvalidRepoID)
	}
	if fg.AddressNamespace(ns) {
		if ns != a.String() {
			panic(errForeignNamespace)
		}
		return
	}
	data, _ := users.ResolveName(ns)
	if data.IsDeleted() || data.Addr() != a {
		panic(errForeignNamespace)
	}
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

// splitList parses the comma-separated lists the transaction API has to use:
// gnokey can only pass strings, so a []string parameter would not be callable.
func splitList(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// Repos
// ---------------------------------------------------------------------------

// CreateRepo registers "<namespace>/<name>" with the caller as owner.
// defaultRef may be empty for refs/heads/main.
//
// The namespace must be one the caller owns: an r/sys/users name registered to
// their address, or their own bech32 address. Nobody squats anybody.
func CreateRepo(cur realm, id, description, defaultRef string) {
	a := caller(cur)
	requireNamespace(a, id)
	_, err := f.CreateRepo(a, height(), id, description, defaultRef)
	must(err)
	chain.Emit("RepoCreated", "repo", id, "owner", a.String())
}

// Fork registers newID as a fork of srcID, snapshotting the parent's current
// refs into the fork's log so the lineage records exactly what was forked.
func Fork(cur realm, srcID, newID string) {
	a := caller(cur)
	requireNamespace(a, newID)
	_, err := f.Fork(a, height(), srcID, newID)
	must(err)
	chain.Emit("RepoForked", "repo", newID, "parent", srcID, "owner", a.String())
}

// SetDescription updates the repo description (admin).
func SetDescription(cur realm, repoID, description string) {
	must(repo(repoID).SetDescription(caller(cur), description))
	chain.Emit("RepoUpdated", "repo", repoID, "field", "description")
}

// SetMirrors replaces the fetch locators, comma-separated, first one canonical
// (maintainer). The chain records them; it never fetches.
func SetMirrors(cur realm, repoID, mirrors string) {
	must(repo(repoID).SetMirrors(caller(cur), splitList(mirrors)))
	chain.Emit("RepoUpdated", "repo", repoID, "field", "mirrors")
}

// SetDefaultRef points the repo at another default branch (maintainer).
func SetDefaultRef(cur realm, repoID, name string) {
	must(repo(repoID).SetDefaultRef(caller(cur), name))
	chain.Emit("RepoUpdated", "repo", repoID, "field", "default_ref")
}

// SetPolicy sets how many writer approvals a change needs, and whether the
// author's own approval counts (admin).
func SetPolicy(cur realm, repoID string, requiredApprovals int, allowSelfApproval bool) {
	must(repo(repoID).SetPolicy(caller(cur), requiredApprovals, allowSelfApproval))
	chain.Emit("RepoUpdated", "repo", repoID, "field", "policy")
}

// SetMember grants a role: none, reader, writer, maintainer, admin, owner.
func SetMember(cur realm, repoID string, member address, role string) {
	parsed, err := fg.ParseRole(role)
	must(err)
	must(repo(repoID).SetMember(caller(cur), member, parsed))
	chain.Emit("MemberSet", "repo", repoID, "member", member.String(), "role", role)
}

// SetArchived freezes or unfreezes a repo (admin). The log stays readable.
func SetArchived(cur realm, repoID string, archived bool) {
	must(repo(repoID).SetArchived(caller(cur), archived))
	chain.Emit("RepoUpdated", "repo", repoID, "field", "archived")
}

// ---------------------------------------------------------------------------
// Refs: the reference log
// ---------------------------------------------------------------------------

// SetRef moves a ref by compare-and-swap (writer). expectedOID is the tip the
// caller last saw, empty to create. A stale expectation aborts instead of
// overwriting: git's --force-with-lease, with consensus holding the lease.
func SetRef(cur realm, repoID, name, expectedOID, newOID, note string) {
	a := caller(cur)
	e, err := repo(repoID).SetRef(a, height(), name, expectedOID, newOID, note)
	must(err)
	emitRef(repoID, e)
}

// ForceSetRef moves a ref with no expectation (maintainer). It is not
// forbidden, it is recorded as a force, in a log nobody can rewrite.
func ForceSetRef(cur realm, repoID, name, newOID, note string) {
	a := caller(cur)
	e, err := repo(repoID).ForceSetRef(a, height(), name, newOID, note)
	must(err)
	emitRef(repoID, e)
}

// DeleteRef removes a ref by compare-and-swap (maintainer). The default branch
// is not deletable.
func DeleteRef(cur realm, repoID, name, expectedOID, note string) {
	a := caller(cur)
	e, err := repo(repoID).DeleteRef(a, height(), name, expectedOID, note)
	must(err)
	emitRef(repoID, e)
}

func emitRef(repoID string, e *fg.LogEntry) {
	chain.Emit("RefLog",
		"repo", repoID,
		"ref", e.Ref,
		"kind", e.Kind,
		"old", e.OldOID,
		"new", e.NewOID,
		"seq", itoa(e.Seq),
		"digest", e.Digest,
	)
}

// ---------------------------------------------------------------------------
// Issues
// ---------------------------------------------------------------------------

// OpenIssue files an issue. Permissionless: the author pays for their bytes.
// labels is comma-separated. Returns the issue id.
func OpenIssue(cur realm, repoID, title, body, labels string) int64 {
	a := caller(cur)
	i, err := repo(repoID).OpenIssue(a, height(), title, body, splitList(labels))
	must(err)
	chain.Emit("IssueOpened", "repo", repoID, "issue", itoa(i.ID), "author", a.String())
	return i.ID
}

// CommentIssue appends a reply.
func CommentIssue(cur realm, repoID string, issueID int64, body string) {
	a := caller(cur)
	_, err := repo(repoID).CommentIssue(a, height(), issueID, body)
	must(err)
	chain.Emit("IssueComment", "repo", repoID, "issue", itoa(issueID), "author", a.String())
}

// CloseIssue closes an issue (author or maintainer).
func CloseIssue(cur realm, repoID string, issueID int64) {
	must(repo(repoID).SetIssueOpen(caller(cur), height(), issueID, false))
	chain.Emit("IssueClosed", "repo", repoID, "issue", itoa(issueID))
}

// ReopenIssue reopens an issue (author or maintainer).
func ReopenIssue(cur realm, repoID string, issueID int64) {
	must(repo(repoID).SetIssueOpen(caller(cur), height(), issueID, true))
	chain.Emit("IssueReopened", "repo", repoID, "issue", itoa(issueID))
}

// SetIssueLabels replaces an issue's labels, comma-separated (maintainer).
func SetIssueLabels(cur realm, repoID string, issueID int64, labels string) {
	must(repo(repoID).SetIssueLabels(caller(cur), height(), issueID, splitList(labels)))
	chain.Emit("IssueLabeled", "repo", repoID, "issue", itoa(issueID), "labels", labels)
}

// ---------------------------------------------------------------------------
// Change requests
// ---------------------------------------------------------------------------

// OpenChange proposes moving targetRef to include headOID. sourceRepo may be
// another forge repo id, a mirror locator, or empty for this repo. Returns the
// change id.
func OpenChange(cur realm, repoID, title, body, sourceRepo, sourceRef, headOID, targetRef string) int64 {
	a := caller(cur)
	c, err := repo(repoID).OpenChange(a, height(), title, body, sourceRepo, sourceRef, headOID, targetRef)
	must(err)
	chain.Emit("ChangeOpened", "repo", repoID, "change", itoa(c.ID), "author", a.String(), "head", headOID, "target", targetRef)
	return c.ID
}

// UpdateChangeHead repoints an open change at a new object (author or writer).
// Every approval of the previous head stops counting, by construction.
func UpdateChangeHead(cur realm, repoID string, changeID int64, headOID string) {
	must(repo(repoID).UpdateChangeHead(caller(cur), height(), changeID, headOID))
	chain.Emit("ChangeUpdated", "repo", repoID, "change", itoa(changeID), "head", headOID)
}

// ReviewChange records a verdict: approve, request-changes, comment: against
// the change's current head. Anyone may review; a writer's approval counts.
func ReviewChange(cur realm, repoID string, changeID int64, verdict, body string) {
	a := caller(cur)
	must(repo(repoID).ReviewChange(a, height(), changeID, verdict, body))
	chain.Emit("ChangeReviewed", "repo", repoID, "change", itoa(changeID), "reviewer", a.String(), "verdict", verdict)
}

// CommentChange appends a reply to a change request.
func CommentChange(cur realm, repoID string, changeID int64, body string) {
	a := caller(cur)
	_, err := repo(repoID).CommentChange(a, height(), changeID, body)
	must(err)
	chain.Emit("ChangeComment", "repo", repoID, "change", itoa(changeID), "author", a.String())
}

// CloseChange withdraws or rejects a change (author or maintainer).
func CloseChange(cur realm, repoID string, changeID int64) {
	must(repo(repoID).CloseChange(caller(cur), height(), changeID))
	chain.Emit("ChangeClosed", "repo", repoID, "change", itoa(changeID))
}

// MergeChange moves the target ref to mergedOID and records the move as a merge
// entry naming the change (maintainer). expectedTargetOID is a compare-and-swap
// on the target: a change approved against a base that has moved is refused,
// not silently rebased.
func MergeChange(cur realm, repoID string, changeID int64, expectedTargetOID, mergedOID, note string) {
	a := caller(cur)
	e, err := repo(repoID).MergeChange(a, height(), changeID, expectedTargetOID, mergedOID, note)
	must(err)
	chain.Emit("ChangeMerged", "repo", repoID, "change", itoa(changeID), "merger", a.String(), "new", mergedOID, "digest", e.Digest)
	emitRef(repoID, e)
}

// ---------------------------------------------------------------------------
// Packages and releases
// ---------------------------------------------------------------------------

// PublishPackage records that a repo publishes a deployed package path.
//
// The claim is not verified and cannot be: a realm cannot ask the chain who
// deployed a path. What is guaranteed is that someone with write access to the
// repo said it, under a namespace r/sys/users governs. A reader weighs it the
// way they weigh a go.mod.
//
// ref, oid and tag may each be empty when unstated.
func PublishPackage(cur realm, repoID, path, ref, oid, tag string) {
	a := caller(cur)
	p, err := f.PublishPackage(a, height(), repoID, path, ref, oid, tag)
	must(err)
	chain.Emit("PackagePublished",
		"repo", repoID,
		"path", p.Path,
		"ref", p.Ref,
		"oid", p.OID,
		"tag", p.Tag,
	)
}

// UnpublishPackage withdraws the claim. The package stays on chain; only the
// repo's assertion about it goes away.
func UnpublishPackage(cur realm, repoID, path string) {
	a := caller(cur)
	must(f.UnpublishPackage(a, repoID, path))
	chain.Emit("PackageUnpublished", "repo", repoID, "path", path)
}

// CutRelease names a point in a repo's history. A tag cannot be re-cut: see
// YankRelease for withdrawing one.
func CutRelease(cur realm, repoID, tag, name, notes, oid, ref string, prerelease bool) {
	a := caller(cur)
	rel, err := repo(repoID).CutRelease(a, height(), tag, name, notes, oid, ref, prerelease)
	must(err)
	chain.Emit("ReleaseCut",
		"repo", repoID,
		"tag", rel.Tag,
		"oid", rel.OID,
		"prerelease", btoa(rel.Prerelease),
	)
}

// YankRelease marks a release withdrawn. It stays visible: a version that
// vanished reads as "never published" rather than "do not use this".
func YankRelease(cur realm, repoID, tag, reason string) {
	a := caller(cur)
	must(repo(repoID).YankRelease(a, tag, reason))
	chain.Emit("ReleaseYanked", "repo", repoID, "tag", tag, "reason", reason)
}

// ---------------------------------------------------------------------------
// Read-only helpers, for other realms and for vm/qeval
// ---------------------------------------------------------------------------

// PackageRepo is the lookup an explorer makes: given a deployed package path,
// which repo claims to publish it. Empty when nobody does.
func PackageRepo(pkgPath string) string { return f.PackageRepo(pkgPath) }

// PackageCount is how many package paths the whole forge claims.
func PackageCount() int { return f.PackageCount() }

// LatestReleaseTag is the most recently cut release of a repo that is neither a
// prerelease nor yanked, or "". Most recently CUT, never highest version: tags
// here are not required to be semver, so there is no order to sort by that
// would not be wrong for somebody.
func LatestReleaseTag(repoID string) string {
	r := f.Repo(repoID)
	if r == nil {
		return ""
	}
	rel := r.LatestRelease()
	if rel == nil {
		return ""
	}
	return rel.Tag
}

// ReleaseCount is how many releases a repo has cut, yanked ones included.
func ReleaseCount(repoID string) int {
	r := f.Repo(repoID)
	if r == nil {
		return 0
	}
	return r.ReleaseCount()
}

// RefOID returns the object a ref points at, or "" if there is no such ref.
func RefOID(repoID, name string) string {
	r := f.Repo(repoID)
	if r == nil {
		return ""
	}
	ref := r.Ref(name)
	if ref == nil {
		return ""
	}
	return ref.OID
}

// LogHead returns the repo's chain digest: pin it off chain and the whole
// history of every ref becomes falsifiable.
func LogHead(repoID string) string {
	r := f.Repo(repoID)
	if r == nil {
		return ""
	}
	return r.LogHead()
}

// HasRepo reports whether a repo id is registered.
func HasRepo(repoID string) bool { return f.HasRepo(repoID) }

// RepoCount is the number of repos on this forge.
func RepoCount() int { return f.Size() }
