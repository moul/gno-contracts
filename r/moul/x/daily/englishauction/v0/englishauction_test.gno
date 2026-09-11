package englishauction

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestKeyAndPendKey(t *testing.T) {
	uassert.Equal(t, "000000000001", key(1))
	uassert.Equal(t, "000000000042", key(42))
	uassert.Equal(t, "000000123456", key(123456))

	addr := address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	uassert.Equal(t, "000000000007:"+addr.String(), pendKey(7, addr))
}

func TestBlocksLeftAndWinner(t *testing.T) {
	a := &Auction{ID: 1, Item: "vase", EndHeight: 100}

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
