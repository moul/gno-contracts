package erc721

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestKeyPaddingSortable(t *testing.T) {
	// keys must be fixed-width so avl iteration is numeric-order.
	uassert.Equal(t, "000000000001", key(1))
	uassert.Equal(t, "000000000042", key(42))
	uassert.Equal(t, "000000123456", key(123456))
	// lexical order must match numeric order
	uassert.True(t, key(2) < key(10), "padded key(2) should sort before key(10)")
	uassert.True(t, key(99) < key(100), "padded key(99) should sort before key(100)")
}

func TestReadOnlyDefaults(t *testing.T) {
	// on a fresh realm nothing is minted.
	uassert.Equal(t, int64(0), totalSupply())
	uassert.False(t, exists(1), "token 1 must not exist before minting")

	var someone address = "g1someoneelsehere000000000000000000000000"
	uassert.Equal(t, uint64(0), balanceOf(someone))
	uassert.Equal(t, "", approvedOf(1).String())
}
