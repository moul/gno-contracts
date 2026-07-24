package vestoken

import (
	"strings"
	"testing"
)

// Fixed test addresses (valid-length bech32-style literals), same convention
// used across the other daily-dapp realms.
const (
	alice = address("g1alicexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
	bob   = address("g1bobxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
)

// reset clears package state between tests so cases stay independent.
func reset() {
	balances = map[address]uint64{}
	grants = map[address]*grant{}
	totalSupply = 0
}

// TestVestingUnlocksLinearly opens a grant, claims nothing before any
// blocks pass, half at the midpoint, and the rest once fully vested.
func TestVestingUnlocksLinearly(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	MintVested(cross(cur), alice, 1000, 100)

	if got := TotalSupply(); got != 1000 {
		t.Fatalf("total supply = %d, want 1000", got)
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	if got := Claim(cross(cur)); got != 0 {
		t.Fatalf("claim at start = %d, want 0", got)
	}

	testing.SkipHeights(50)
	testing.SetRealm(testing.NewUserRealm(alice))
	if got := Claim(cross(cur)); got != 500 {
		t.Fatalf("claim at midpoint = %d, want 500", got)
	}
	if got := BalanceOf(alice); got != 500 {
		t.Errorf("alice liquid balance = %d, want 500", got)
	}

	testing.SkipHeights(50)
	testing.SetRealm(testing.NewUserRealm(alice))
	if got := Claim(cross(cur)); got != 500 {
		t.Fatalf("claim at end = %d, want 500", got)
	}
	if got := BalanceOf(alice); got != 1000 {
		t.Errorf("alice liquid balance = %d, want 1000", got)
	}

	total, claimed, claimable := GrantOf(alice)
	if total != 0 || claimed != 0 || claimable != 0 {
		t.Errorf("grant should be gone after full claim, got total=%d claimed=%d claimable=%d", total, claimed, claimable)
	}
}

// TestActiveGrantBlocksNewGrant asserts a beneficiary can't be granted twice
// while a previous grant is still unclaimed.
func TestActiveGrantBlocksNewGrant(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	MintVested(cross(cur), alice, 100, 10)

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("expected panic minting over an active grant, got none")
		}
	}()
	MintVested(cross(cur), alice, 50, 10)
}

// TestTransferClaimedBalance checks claimed tokens behave like a normal
// transferable ERC-20 balance.
func TestTransferClaimedBalance(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	MintVested(cross(cur), alice, 200, 10)

	testing.SkipHeights(10)
	testing.SetRealm(testing.NewUserRealm(alice))
	Claim(cross(cur))

	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), bob, 80)

	if got := BalanceOf(alice); got != 120 {
		t.Errorf("alice balance = %d, want 120", got)
	}
	if got := BalanceOf(bob); got != 80 {
		t.Errorf("bob balance = %d, want 80", got)
	}
}

// TestRenderContainsMetadata checks the Markdown view exposes name/symbol
// and the active grant.
func TestRenderContainsMetadata(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	MintVested(cross(cur), alice, 42, 10)

	out := Render("")
	for _, want := range []string{"VestToken", "VEST", "Total supply", "42"} {
		if !strings.Contains(out, want) {
			t.Errorf("render output missing %q\n%s", want, out)
		}
	}
}
