package vault

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

func Test(cur realm, t *testing.T) {
	test2 := testutils.TestAddress("test2")
	test3 := testutils.TestAddress("test3")

	// check token metadata.
	{
		got := Token.GetName()
		expected := "Foo Token"
		if strings.TrimSpace(got) != strings.TrimSpace(expected) {
			t.Fatalf("expected %q, got %q.", expected, got)
		}
	}

	// check balance of test1.
	{
		got := Token.BalanceOf(test1)
		expected := int64(100000000)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// transfer tokens from test1 to test2.
	if err := privateLedger.Transfer(test1, test2, 1000); err != nil {
		t.Fatal(err)
	}

	// check balance of test1.
	{
		got := Token.BalanceOf(test1)
		expected := int64(99999000)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// check balance of test2.
	{
		got := Token.BalanceOf(test2)
		expected := int64(1000)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// test1 deposits 300 with test3 as recovery address.
	testing.SetOriginCaller(test1)
	Deposit(cross(cur), 300, test3)

	// check balance of test1.
	{
		got := Token.BalanceOf(test1)
		expected := int64(99998700)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// check balance of the vault.
	{
		got := Token.BalanceOf(vaultAddr)
		expected := int64(300)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// test1 unvaults 50 tokens, waits past the lock, then redeems them.
	Unvault(cross(cur), 50)
	testing.SkipHeights(101)  // SkipHeights resets the context, so re-set the caller.
	testing.SetOriginCaller(test1)
	Redeem(cross(cur), 50)

	// check balance of test1.
	{
		got := Token.BalanceOf(test1)
		expected := int64(99998750)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// check balance of the vault.
	{
		got := Token.BalanceOf(vaultAddr)
		expected := int64(250)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// Recover sends test1's still-locked 250 to the recovery address recorded
	// at deposit time (test3), leaving the vault empty.
	//
	// It is called here by test2, a bystander who never deposited, because
	// Recover has NO caller check. That is a real flaw and this test pins it:
	// it cannot steal (the destination is whatever the target itself recorded)
	// but anyone can rewind anyone's deposit at will, which is a free denial of
	// service. If a caller check is ever added, this assertion is what will
	// fail, so the change has to be deliberate.
	testing.SetOriginCaller(test2)
	Recover(cross(cur), test1)

	// the recovery address received the whole locked balance.
	{
		got := Token.BalanceOf(test3)
		expected := int64(250)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// the vault is empty.
	{
		got := Token.BalanceOf(vaultAddr)
		expected := int64(0)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}

	// Recovering twice is a no-op rather than a second payout: the vaulted
	// balance is zero, so Recover returns before transferring anything.
	Recover(cross(cur), test1)
	{
		got := Token.BalanceOf(test3)
		expected := int64(250)
		if got != expected {
			t.Fatalf("expected %d, got %d.", expected, got)
		}
	}
}
