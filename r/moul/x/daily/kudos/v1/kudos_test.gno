package kudos

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestGiveAndLeaderboard(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")
	carol := testutils.TestAddress("carol")

	// reset package state between test funcs
	counts = avl.Tree{}
	feed = nil

	testing.SetRealm(testing.NewUserRealm(alice))
	Give(cross(cur), bob, "great review")

	testing.SetRealm(testing.NewUserRealm(carol))
	Give(cross(cur), bob, "helpful pairing")
	Give(cross(cur), alice, "nice docs")

	lb := leaderboard()
	uassert.Equal(t, 2, len(lb))
	// bob has 2, alice has 1 -> bob first
	uassert.Equal(t, bob.String(), lb[0].addr)
	uassert.Equal(t, int64(2), lb[0].count)
	uassert.Equal(t, alice.String(), lb[1].addr)
	uassert.Equal(t, int64(1), lb[1].count)

	out := Render("")
	uassert.True(t, strings.Contains(out, "helpful pairing"))
	uassert.True(t, strings.Contains(out, "Leaderboard"))
}

func TestCannotKudosSelf(cur realm, t *testing.T) {
	dave := testutils.TestAddress("dave")

	counts = avl.Tree{}
	feed = nil

	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsWithMessage(t, cur, "cannot give kudos to yourself", func() {
		Give(cross(cur), dave, "self five")
	})
}

func TestEmptyReasonAborts(cur realm, t *testing.T) {
	eve := testutils.TestAddress("eve")
	frank := testutils.TestAddress("frank")

	counts = avl.Tree{}
	feed = nil

	testing.SetRealm(testing.NewUserRealm(eve))
	uassert.AbortsWithMessage(t, cur, "reason must not be empty", func() {
		Give(cross(cur), frank, "   ")
	})
}
