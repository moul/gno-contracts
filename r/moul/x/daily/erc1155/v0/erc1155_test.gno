package erc1155

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestSplitBalKey(t *testing.T) {
	cases := []struct {
		key       string
		wantOwner string
		wantID    string
	}{
		{"g1abcxyz:0", "g1abcxyz", "0"},
		{"g1abcxyz:42", "g1abcxyz", "42"},
		{"g1def:1", "g1def", "1"},
		{"noseparator", "noseparator", ""},
	}
	for _, tc := range cases {
		owner, id := splitBalKey(tc.key)
		uassert.Equal(t, tc.wantOwner, owner)
		uassert.Equal(t, tc.wantID, id)
	}
}

func TestKeyHelpers(t *testing.T) {
	addr := address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	uassert.Equal(t, addr.String()+":7", balKey(addr, 7))
	uassert.Equal(t, "7", supKey(7))
	uassert.Equal(t, "0", supKey(0))
}
