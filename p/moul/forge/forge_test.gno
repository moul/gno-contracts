package forge

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func TestCreateRepo(t *testing.T) {
	f := New()

	r, err := f.CreateRepo(alice, 42, "moul/forge", "desc", "")
	urequire.NoError(t, err)
	uassert.Equal(t, "refs/heads/main", r.DefaultRef, "default ref defaults")
	uassert.Equal(t, int64(42), r.CreatedAt)
	uassert.Equal(t, "owner", r.RoleOf(alice).String())
	uassert.Equal(t, 1, f.Size())

	_, err = f.CreateRepo(bob, 43, "moul/forge", "", "")
	uassert.ErrorIs(t, err, ErrRepoExists)

	_, err = f.CreateRepo(bob, 43, "Moul/Forge", "", "")
	uassert.ErrorIs(t, err, ErrInvalidRepoID)

	_, err = f.CreateRepo(bob, 43, "moul/other", "", "main")
	uassert.ErrorIs(t, err, ErrInvalidRefName)

	uassert.True(t, f.Repo("moul/nope") == nil, "missing repo is nil")
	uassert.True(t, f.HasRepo("moul/forge"))
}

func TestMembership(t *testing.T) {
	_, r := newRepo(t)

	uassert.True(t, r.Can(bob, RoleWriter), "maintainer covers writer")
	uassert.False(t, r.Can(carol, RoleMaintainer))
	uassert.Equal(t, "none", r.RoleOf(eve).String())
	uassert.Equal(t, 4, r.MemberCount())

	// A writer cannot hand out roles.
	uassert.ErrorIs(t, r.SetMember(carol, eve, RoleWriter), ErrUnauthorized)

	// An admin can promote up to admin, but cannot mint an owner...
	urequire.NoError(t, r.SetMember(alice, bob, RoleAdmin))
	uassert.ErrorIs(t, r.SetMember(bob, eve, RoleOwner), ErrUnauthorized)
	// ...nor demote one.
	uassert.ErrorIs(t, r.SetMember(bob, alice, RoleReader), ErrUnauthorized)

	// The last owner cannot demote themselves: a repo with no owner is a repo
	// nobody can ever administer again.
	uassert.ErrorIs(t, r.SetMember(alice, alice, RoleReader), ErrLastOwner)
	urequire.NoError(t, r.SetMember(alice, bob, RoleOwner))
	urequire.NoError(t, r.SetMember(alice, alice, RoleReader))
	uassert.Equal(t, "reader", r.RoleOf(alice).String())

	// Revoking removes the member outright.
	urequire.NoError(t, r.SetMember(bob, dave, RoleNone))
	uassert.Equal(t, "none", r.RoleOf(dave).String())
	uassert.Equal(t, 3, r.MemberCount())

	uassert.ErrorIs(t, r.SetMember(bob, eve, Role(99)), ErrInvalidRole)
}

func TestRepoSettings(t *testing.T) {
	_, r := newRepo(t)

	uassert.ErrorIs(t, r.SetDescription(carol, "nope"), ErrUnauthorized)
	urequire.NoError(t, r.SetDescription(alice, "an on-chain forge for gno"))
	uassert.Equal(t, "an on-chain forge for gno", r.Description)

	uassert.ErrorIs(t, r.SetMirrors(carol, []string{"https://example.com/x.git"}), ErrUnauthorized)
	uassert.ErrorIs(t, r.SetMirrors(bob, []string{"nope"}), ErrInvalidMirror)
	urequire.NoError(t, r.SetMirrors(bob, []string{"https://github.com/moul/gno-contracts.git"}))
	uassert.Equal(t, 1, len(r.Mirrors))

	uassert.ErrorIs(t, r.SetPolicy(carol, 2, false), ErrUnauthorized)
	uassert.ErrorIs(t, r.SetPolicy(alice, 99, false), ErrTooMany)
	urequire.NoError(t, r.SetPolicy(alice, 2, true))
	uassert.Equal(t, 2, r.RequiredApprovals)
	uassert.True(t, r.AllowSelfApproval)

	urequire.NoError(t, r.SetDefaultRef(bob, "refs/heads/trunk"))
	uassert.Equal(t, "refs/heads/trunk", r.DefaultRef)

	// An archived repo takes no writes at all.
	urequire.NoError(t, r.SetArchived(alice, true))
	_, err := r.SetRef(alice, 101, "refs/heads/trunk", "", oid("a"), "")
	uassert.ErrorIs(t, err, ErrRepoArchived)
	_, err = r.OpenIssue(eve, 101, "hello", "", nil)
	uassert.ErrorIs(t, err, ErrRepoArchived)
	urequire.NoError(t, r.SetArchived(alice, false))
}

func TestForkSnapshotsRefs(t *testing.T) {
	f, r := newRepo(t)
	urequire.NoError(t, r.SetMirrors(alice, []string{"https://github.com/moul/gno-contracts.git"}))
	_, err := r.SetRef(alice, 101, "refs/heads/main", "", oid("a"), "initial")
	urequire.NoError(t, err)
	_, err = r.SetRef(alice, 102, "refs/tags/v0.1.0", "", oid("b"), "tag")
	urequire.NoError(t, err)

	child, err := f.Fork(eve, 110, "moul/forge", "eve/forge")
	urequire.NoError(t, err)
	uassert.Equal(t, "moul/forge", child.ParentID)
	uassert.Equal(t, "owner", child.RoleOf(eve).String(), "the forker owns the fork")
	uassert.Equal(t, 2, child.RefCount(), "refs are snapshotted")
	uassert.Equal(t, 2, child.LogSize(), "and the snapshot is in the log")
	uassert.Equal(t, oid("a"), child.Ref("refs/heads/main").OID)
	uassert.Equal(t, 1, len(child.Mirrors), "the fork inherits where to fetch objects")

	ok, bad := child.VerifyLog()
	uassert.True(t, ok, "fork log is a valid chain")
	uassert.Equal(t, int64(-1), bad)

	_, err = f.Fork(eve, 111, "moul/nope", "eve/nope")
	uassert.ErrorIs(t, err, ErrRepoNotFound)
	_, err = f.Fork(eve, 111, "moul/forge", "eve/forge")
	uassert.ErrorIs(t, err, ErrRepoExists)
}

func TestIterateReposAndNamespace(t *testing.T) {
	f := New()
	for _, id := range []string{"alice/one", "alice/two", "bob/three"} {
		_, err := f.CreateRepo(alice, 1, id, "", "")
		urequire.NoError(t, err)
	}

	var all []string
	f.IterateRepos(0, 0, func(r *Repo) bool {
		all = append(all, r.ID)
		return false
	})
	uassert.Equal(t, "alice/one,alice/two,bob/three", join(all))

	var ns []string
	f.IterateNamespace("alice", func(r *Repo) bool {
		ns = append(ns, r.ID)
		return false
	})
	uassert.Equal(t, "alice/one,alice/two", join(ns))

	var page []string
	f.IterateRepos(1, 1, func(r *Repo) bool {
		page = append(page, r.ID)
		return false
	})
	uassert.Equal(t, "alice/two", join(page))
}

func join(ss []string) string {
	out := ""
	for i, s := range ss {
		if i > 0 {
			out += ","
		}
		out += s
	}
	return out
}
