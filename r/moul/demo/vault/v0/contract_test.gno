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

	// TODO: additional test case(s) for Recover().
}
