package probe

import (
	"chain"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

const selfPath = "gno.land/r/moul/x/framelab/probe/v0"

func self() address { return chain.PackageAddress(selfPath) }

// The claim: pure-package code called with a forwarded `cur` still runs in the
// importing realm's frame, so it reports that realm's path and address and its
// `cur` is still accepted as current by grc20's spoof check.
func TestPureCodeKeepsImportingRealmFrame(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	path, addr, isCurrent := Frame(cross(cur))
	uassert.Equal(t, selfPath, path)
	uassert.Equal(t, self().String(), addr.String())
	uassert.True(t, isCurrent)
}

// The same claim, exercised through the operation that actually matters: a
// GRC20 pull issued from inside the pure package must credit the instance
// realm's own address.
func TestPureCodePullsToImportingRealm(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	ledger.Mint(alice, 1_000)
	ledger.Approve(alice, self(), 500)

	testing.SetRealm(testing.NewUserRealm(alice))
	bound := Run(cross(cur), alice, 400)

	uassert.Equal(t, self().String(), bound.String())
	uassert.Equal(t, int64(400), Token.BalanceOf(self()))
	uassert.Equal(t, int64(600), Token.BalanceOf(alice))
	uassert.Equal(t, int64(100), Token.Allowance(alice, self()))
}
