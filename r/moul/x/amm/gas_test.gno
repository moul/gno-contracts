package amm

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// A fixed four-step profile, declared in order so `gno test -v` reports one
// `--- GAS:` figure per operation. The same four steps exist verbatim in v1,
// so the difference between the two runs is the cost of the share accounting
// and nothing else. See moul/gno-contracts#135.

var (
	gasAlice = testutils.TestAddress("gas-alice")
	gasBob   = testutils.TestAddress("gas-bob")
)

// TestGas0Fund keeps the fixture cost (minting and approving both tokens for
// both actors) out of the four measured numbers.
func TestGas0Fund(t *testing.T) {
	reset()
	fund(gasAlice, 10_000_000)
	fund(gasBob, 10_000_000)
}

func TestGas1Seed(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(gasAlice))
	uassert.Equal(t, int64(1_000_000), AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 4_000_000))
}

func TestGas2Swap(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(gasAlice))
	uassert.Equal(t, int64(362_644), Swap(cross(cur), keyAAA, keyBBB, 100_000, 1))
}

func TestGas3Join(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(gasBob))
	uassert.Equal(t, int64(90_908), AddLiquidity(cross(cur), keyAAA, keyBBB, 100_000, 1_000_000))
}

func TestGas4Exit(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(gasBob))
	held := SharesOf(keyAAA, keyBBB, gasBob)
	uassert.Equal(t, int64(90_908), held)
	RemoveLiquidity(cross(cur), keyAAA, keyBBB, held)
	uassert.Equal(t, int64(0), SharesOf(keyAAA, keyBBB, gasBob))
}
