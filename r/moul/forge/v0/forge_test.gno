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
	CreateRepo(cross(cur), "moul/demo", "a demo repo", "")
	uassert.True(t, HasRepo("moul/demo"))
	uassert.Equal(t, 1, RepoCount())
	uassert.Equal(t, "", LogHead("moul/demo"), "a fresh repo has an empty log")

	// The creator is the owner, so roles are theirs to hand out.
	SetMember(cross(cur), "moul/demo", carol, "writer")
	SetMember(cross(cur), "moul/demo", bob, "maintainer")
	SetMirrors(cross(cur), "moul/demo", "https://github.com/moul/demo.git, ipfs://bafyfakefakefakefakefakefakefakefakefake")
	uassert.Equal(t, 2, len(f.Repo("moul/demo").Mirrors), "comma-separated lists are how a tx passes a slice")

	// A writer creates the branch, then moves it by compare-and-swap.
	testing.SetRealm(testing.NewUserRealm(carol))
	SetRef(cross(cur), "moul/demo", "refs/heads/main", "", oid("a"), "initial import")
	uassert.Equal(t, oid("a"), RefOID("moul/demo", "refs/heads/main"))
	head := LogHead("moul/demo")
	uassert.NotEqual(t, "", head)

	testing.SetRealm(testing.NewUserRealm(carol))
	SetRef(cross(cur), "moul/demo", "refs/heads/main", oid("a"), oid("b"), "second commit")
	uassert.NotEqual(t, head, LogHead("moul/demo"), "each entry advances the chain digest")

	// A stale expectation aborts: this is the lost-push case, caught.
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "stale ref", func() {
		SetRef(cross(cur), "moul/demo", "refs/heads/main", oid("a"), oid("c"), "")
	})

	// A stranger cannot move a ref at all.
	testing.SetRealm(testing.NewUserRealm(eve))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		SetRef(cross(cur), "moul/demo", "refs/heads/main", oid("b"), oid("c"), "")
	})

	// ...but anyone may file an issue and propose a change.
	testing.SetRealm(testing.NewUserRealm(eve))
	issueID := OpenIssue(cross(cur), "moul/demo", "the log needs a UI", "hard to read over RPC", "ux,help wanted")
	uassert.Equal(t, int64(0), issueID)

	testing.SetRealm(testing.NewUserRealm(eve))
	changeID := OpenChange(cross(cur), "moul/demo", "add a log view", "", "eve/demo", "refs/heads/logview", oid("c"), "refs/heads/main")
	uassert.Equal(t, int64(0), changeID)

	// A maintainer's approval satisfies the default policy; the merge moves the
	// ref and lands in the same log as every other move.
	testing.SetRealm(testing.NewUserRealm(bob))
	ReviewChange(cross(cur), "moul/demo", changeID, "approve", "lgtm")
	testing.SetRealm(testing.NewUserRealm(bob))
	MergeChange(cross(cur), "moul/demo", changeID, oid("b"), oid("d"), "merge change 0")

	uassert.Equal(t, oid("d"), RefOID("moul/demo", "refs/heads/main"))
	r := f.Repo("moul/demo")
	uassert.Equal(t, 3, r.LogSize())
	uassert.Equal(t, fg.KindMerge, r.LogEntryAt(2).Kind)
	uassert.Equal(t, bob.String(), r.LogEntryAt(2).Actor.String(), "the log records who merged, not who proposed")
	ok, _ := r.VerifyLog()
	uassert.True(t, ok, "the digest chain verifies end to end")

	// Issue triage: the maintainer closes what the reporter opened.
	testing.SetRealm(testing.NewUserRealm(bob))
	CloseIssue(cross(cur), "moul/demo", issueID)
	uassert.Equal(t, 0, r.OpenIssueCount())
}

// TestHeightsComeFromTheChain checks the realm stamps entries with the block it
// ran in. SkipHeights is relative and there is no absolute height getter, so the
// assertion is on the delta.
func TestHeightsComeFromTheChain(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), "moul/heights", "", "")
	testing.SetRealm(testing.NewUserRealm(alice))
	SetRef(cross(cur), "moul/heights", "refs/heads/main", "", oid("a"), "")

	testing.SkipHeights(7)

	testing.SetRealm(testing.NewUserRealm(alice))
	SetRef(cross(cur), "moul/heights", "refs/heads/main", oid("a"), oid("b"), "")

	r := f.Repo("moul/heights")
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
		SetRef(cross(cur), "moul/ghost", "refs/heads/main", "", oid("a"), "")
	})
	uassert.Equal(t, "", RefOID("moul/ghost", "refs/heads/main"))
	uassert.Equal(t, "", LogHead("moul/ghost"))
	uassert.False(t, HasRepo("moul/ghost"))
}

// TestRoleParsing: the role argument is a string on the wire, so a typo must
// abort rather than silently grant nothing.
func TestRoleParsing(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), "moul/roles", "", "")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "invalid role", func() {
		SetMember(cross(cur), "moul/roles", bob, "commiter")
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	SetMember(cross(cur), "moul/roles", bob, "maintainer")
	uassert.Equal(t, "maintainer", f.Repo("moul/roles").RoleOf(bob).String())
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
