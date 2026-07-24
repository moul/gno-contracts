package escrow

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

func resetState() {
	deals = avl.NewTree()
	nextID = 0
}

func TestCreateAndConfirmSettles(cur realm, t *testing.T) {
	resetState()

	// Alice creates a deal with Bob.
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Create(cross(cur), bob, "swap NFT for 100 GNOT")
	uassert.Equal(t, 0, id)

	// Alice confirms (1/2, still open).
	Confirm(cross(cur), id)
	out := Render("0")
	uassert.True(t, strings.Contains(out, "State:** Open"), "expected still open after one confirm")

	// Bob confirms -> settles.
	testing.SetRealm(testing.NewUserRealm(bob))
	Confirm(cross(cur), id)

	out = Render("0")
	uassert.True(t, strings.Contains(out, "Settled"), "expected Settled state")
	uassert.True(t, strings.Contains(out, "swap NFT for 100 GNOT"), "expected terms")
}

func TestCancelByCreator(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Create(cross(cur), bob, "rent payment")

	Cancel(cross(cur), id)

	out := Render("")
	uassert.True(t, strings.Contains(out, "Canceled"), "expected Canceled state")
}

func TestNonPartyCannotConfirm(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Create(cross(cur), bob, "consulting")

	// Carol is not a party.
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, "escrow: caller is not a party to this deal", func() {
		Confirm(cross(cur), id)
	})
}

func TestOnlyCreatorCancels(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Create(cross(cur), bob, "loan")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, "escrow: only the creator can cancel", func() {
		Cancel(cross(cur), id)
	})
}
