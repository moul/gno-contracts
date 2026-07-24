package erc20

import (
	"strings"
	"testing"
)

// Fixed test addresses (valid-length bech32-style literals). The uverse
// `address` type is used directly by the realm; tests construct it the same way.
const (
	alice   = address("g1alicexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
	bob     = address("g1bobxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
	spender = address("g1spenderxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
	dest    = address("g1destxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
)

// reset clears package state between tests so cases stay independent.
func reset() {
	balances = map[address]uint64{}
	allowances = map[address]map[address]uint64{}
	totalSupply = 0
}

// TestMintAndTransfer mints to alice, then transfers alice -> bob.
func TestMintAndTransfer(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Mint(cross(cur), alice, 1000)

	if got := TotalSupply(); got != 1000 {
		t.Fatalf("total supply = %d, want 1000", got)
	}
	if got := BalanceOf(alice); got != 1000 {
		t.Fatalf("alice balance = %d, want 1000", got)
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), bob, 400)

	if got := BalanceOf(alice); got != 600 {
		t.Errorf("alice balance = %d, want 600", got)
	}
	if got := BalanceOf(bob); got != 400 {
		t.Errorf("bob balance = %d, want 400", got)
	}
	if got := TotalSupply(); got != 1000 {
		t.Errorf("total supply changed on transfer: %d, want 1000", got)
	}
}

// TestApproveAndTransferFrom exercises the allowance path.
func TestApproveAndTransferFrom(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Mint(cross(cur), alice, 500)

	testing.SetRealm(testing.NewUserRealm(alice))
	Approve(cross(cur), spender, 300)
	if got := Allowance(alice, spender); got != 300 {
		t.Fatalf("allowance = %d, want 300", got)
	}

	testing.SetRealm(testing.NewUserRealm(spender))
	TransferFrom(cross(cur), alice, dest, 200)

	if got := BalanceOf(alice); got != 300 {
		t.Errorf("owner balance = %d, want 300", got)
	}
	if got := BalanceOf(dest); got != 200 {
		t.Errorf("dest balance = %d, want 200", got)
	}
	if got := Allowance(alice, spender); got != 100 {
		t.Errorf("remaining allowance = %d, want 100", got)
	}
}

// TestTransferInsufficientPanics asserts an over-transfer reverts.
func TestTransferInsufficientPanics(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Mint(cross(cur), alice, 10)

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("expected panic on over-transfer, got none")
		}
	}()

	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), bob, 100) // more than balance -> panic
}

// TestRenderContainsMetadata checks the Markdown view exposes name/symbol/supply.
func TestRenderContainsMetadata(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Mint(cross(cur), alice, 42)

	out := Render("")
	for _, want := range []string{"MiniToken", "MINI", "Total supply", "42"} {
		if !strings.Contains(out, want) {
			t.Errorf("render output missing %q\n%s", want, out)
		}
	}
}
