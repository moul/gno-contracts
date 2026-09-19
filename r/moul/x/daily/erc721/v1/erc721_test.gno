package erc721

import (
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/uassert/v0"
)

// v0 asserted that its own key() padded to width 12. That rule held only below
// the width: key(10^12) is 13 characters and sorts before key(10^12-1), so the
// token table would have rendered out of order from that id on. The store key
// has no width to outgrow, which is what this replaces it with.
func TestTokenKeysSortNumericallyPastTheOldWidth(t *testing.T) {
	uassert.True(t, store.ID(2).Key() < store.ID(10).Key(), "2 sorts before 10")
	uassert.True(t, store.ID(99).Key() < store.ID(100).Key(), "99 sorts before 100")
	uassert.True(t, store.ID(999999999999).Key() < store.ID(1000000000000).Key(),
		"and it keeps holding one past v0's width-12 ceiling")
}

func TestReadOnlyDefaults(t *testing.T) {
	// on a fresh realm nothing is minted.
	uassert.Equal(t, int64(0), totalSupply())
	uassert.False(t, exists(1), "token 1 must not exist before minting")

	var someone address = "g1someoneelsehere000000000000000000000000"
	uassert.Equal(t, uint64(0), balanceOf(someone))
	uassert.Equal(t, "", approvedOf(1).String())
}
