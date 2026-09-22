package forge

import (
	"testing"

	fg "gno.land/p/moul/forge/v0"
	"gno.land/p/nt/uassert/v0"
)

// TestLifecycle drives the realm exactly as a user would: one signed call at a
// time, each from a different address.
func TestLifecycle(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), demoID, "a demo repo", "")
	uassert.True(t, HasRepo(demoID))
	uassert.Equal(t, 1, RepoCount())
	uassert.Equal(t, "", LogHead(demoID), "a fresh repo has an empty log")

	// The creator is the owner, so roles are theirs to hand out.
	SetMember(cross(cur), demoID, carol, "writer")
	SetMember(cross(cur), demoID, bob, "maintainer")
	SetMirrors(cross(cur), demoID, "https://github.com/moul/demo.git, ipfs://bafyfakefakefakefakefakefakefakefakefake")
	uassert.Equal(t, 2, len(f.Repo(demoID).Mirrors), "comma-separated lists are how a tx passes a slice")

	// A writer creates the branch, then moves it by compare-and-swap.
	testing.SetRealm(testing.NewUserRealm(carol))
	SetRef(cross(cur), demoID, "refs/heads/main", "", oid("a"), "initial import")
	uassert.Equal(t, oid("a"), RefOID(demoID, "refs/heads/main"))
	head := LogHead(demoID)
	uassert.NotEqual(t, "", head)

	testing.SetRealm(testing.NewUserRealm(carol))
	SetRef(cross(cur), demoID, "refs/heads/main", oid("a"), oid("b"), "second commit")
	uassert.NotEqual(t, head, LogHead(demoID), "each entry advances the chain digest")

	// A stale expectation aborts: this is the lost-push case, caught.
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "stale ref", func() {
		SetRef(cross(cur), demoID, "refs/heads/main", oid("a"), oid("c"), "")
	})

	// A stranger cannot move a ref at all.
	testing.SetRealm(testing.NewUserRealm(eve))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		SetRef(cross(cur), demoID, "refs/heads/main", oid("b"), oid("c"), "")
	})

	// ...but anyone may file an issue and propose a change.
	testing.SetRealm(testing.NewUserRealm(eve))
	issueID := OpenIssue(cross(cur), demoID, "the log needs a UI", "hard to read over RPC", "ux,help wanted")
	uassert.Equal(t, int64(0), issueID)

	testing.SetRealm(testing.NewUserRealm(eve))
	changeID := OpenChange(cross(cur), demoID, "add a log view", "", "eve/demo", "refs/heads/logview", oid("c"), "refs/heads/main")
	uassert.Equal(t, int64(0), changeID)

	// A maintainer's approval satisfies the default policy; the merge moves the
	// ref and lands in the same log as every other move.
	testing.SetRealm(testing.NewUserRealm(bob))
	ReviewChange(cross(cur), demoID, changeID, "approve", "lgtm")
	testing.SetRealm(testing.NewUserRealm(bob))
	MergeChange(cross(cur), demoID, changeID, oid("b"), oid("d"), "merge change 0")

	uassert.Equal(t, oid("d"), RefOID(demoID, "refs/heads/main"))
	r := f.Repo(demoID)
	uassert.Equal(t, 3, r.LogSize())
	uassert.Equal(t, fg.KindMerge, r.LogEntryAt(2).Kind)
	uassert.Equal(t, bob.String(), r.LogEntryAt(2).Actor.String(), "the log records who merged, not who proposed")
	ok, _ := r.VerifyLog()
	uassert.True(t, ok, "the digest chain verifies end to end")

	// Issue triage: the maintainer closes what the reporter opened.
	testing.SetRealm(testing.NewUserRealm(bob))
	CloseIssue(cross(cur), demoID, issueID)
	uassert.Equal(t, 0, r.OpenIssueCount())
}

// TestHeightsComeFromTheChain checks the realm stamps entries with the block it
// ran in. SkipHeights is relative and there is no absolute height getter, so the
// assertion is on the delta.
func TestHeightsComeFromTheChain(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), heightsID, "", "")
	testing.SetRealm(testing.NewUserRealm(alice))
	SetRef(cross(cur), heightsID, "refs/heads/main", "", oid("a"), "")

	testing.SkipHeights(7)

	testing.SetRealm(testing.NewUserRealm(alice))
	SetRef(cross(cur), heightsID, "refs/heads/main", oid("a"), oid("b"), "")

	r := f.Repo(heightsID)
	first := r.LogEntryAt(0).Height
	second := r.LogEntryAt(1).Height
	uassert.Equal(t, int64(7), second-first, "seven blocks passed between the two writes")
}

// TestUnknownRepoAborts: every write resolves the repo first, so a typo fails
// loudly instead of creating something.
func TestUnknownRepoAborts(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "repo not found", func() {
		SetRef(cross(cur), ghostID, "refs/heads/main", "", oid("a"), "")
	})
	uassert.Equal(t, "", RefOID(ghostID, "refs/heads/main"))
	uassert.Equal(t, "", LogHead(ghostID))
	uassert.False(t, HasRepo(ghostID))
}

// TestRoleParsing: the role argument is a string on the wire, so a typo must
// abort rather than silently grant nothing.
func TestRoleParsing(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), rolesID, "", "")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "invalid role", func() {
		SetMember(cross(cur), rolesID, bob, "commiter")
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	SetMember(cross(cur), rolesID, bob, "maintainer")
	uassert.Equal(t, "maintainer", f.Repo(rolesID).RoleOf(bob).String())
}

func TestSplitList(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"   ", 0},
		{"a", 1},
		{"a,b", 2},
		{" a , b ,, c ", 3},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, len(splitList(tc.in)), tc.in)
	}
}

// TestNamespaceOwnership: a namespace is an r/sys/users name you hold or your
// own address, and nothing else. No name is registered in a unit test, so the
// name path is exercised through its rejection.
func TestNamespaceOwnership(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), demoID, "under alice's own address", "")
	uassert.True(t, HasRepo(demoID))

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "namespace is not yours", func() {
		CreateRepo(cross(cur), bob.String()+"/squat", "", "")
	}, "an address namespace belongs to that address")

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "namespace is not yours", func() {
		CreateRepo(cross(cur), "moul/forge", "", "")
	}, "an unregistered name belongs to nobody")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "namespace is not yours", func() {
		Fork(cross(cur), demoID, alice.String()+"/fork")
	}, "a fork lands in the forker's namespace, not the parent's")

	testing.SetRealm(testing.NewUserRealm(bob))
	Fork(cross(cur), demoID, bob.String()+"/fork")
	uassert.True(t, HasRepo(bob.String()+"/fork"))

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "invalid repo id", func() {
		CreateRepo(cross(cur), "nonamespace", "", "")
	})
}
