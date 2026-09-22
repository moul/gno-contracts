package englishauction

import (
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/uassert/v0"
)

// v0 asserted that its own key() padded to width 12, and built pendKey on top
// of it. The auction key is now the store's, which has no width to outgrow;
// pending is only point-read, so its key is the plain decimal id.
func TestKeyAndPendKey(t *testing.T) {
	uassert.True(t, store.ID(2).Key() < store.ID(10).Key())
	uassert.True(t, store.ID(999999999999).Key() < store.ID(1000000000000).Key(),
		"one past v0's width-12 ceiling")

	addr := address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	uassert.Equal(t, "7:"+addr.String(), pendKey(7, addr))
}

func TestBlocksLeftAndWinner(t *testing.T) {
	a := &Auction{Item: "vase", EndHeight: 100}

	// before the deadline, blocks remain and there is no winner yet.
	uassert.Equal(t, int64(40), blocksLeft(a, 60))
	uassert.Equal(t, int64(1), blocksLeft(a, 99))
	uassert.False(t, hasWinner(a))

	// at/after the deadline, no blocks remain.
	uassert.Equal(t, int64(0), blocksLeft(a, 100))
	uassert.Equal(t, int64(0), blocksLeft(a, 150))

	// a recorded bid makes it a winner.
	a.HighestBid = 500
	a.HighestBidder = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	uassert.True(t, hasWinner(a))
}
