package erc20

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// Fixed test addresses. testutils.TestAddress derives real, valid-length
// addresses; literal strings would fail address.IsValid() and trip the realm's
// zero-address guard.
var (
	alice   = testutils.TestAddress("alice")
	bob     = testutils.TestAddress("bob")
	spender = testutils.TestAddress("spender")
	dest    = testutils.TestAddress("dest")
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

	// Aborts from a cross(cur) call cannot be caught by a plain recover();
	// assert on the abort message instead.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "erc20: insufficient balance", func() {
		Transfer(cross(cur), bob, 100) // more than balance -> panic
	})
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
