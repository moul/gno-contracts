package grc20

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

func Test(t *testing.T) {
	test2 := testutils.TestAddress("test2")

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
}
