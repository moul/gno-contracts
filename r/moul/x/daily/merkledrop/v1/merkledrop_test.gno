package merkledrop

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"testing"

	"gno.land/p/moul/x/merkle/v0"
	"gno.land/p/nt/urequire/v0"
)

const (
	alice   = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5") // demo index 0, 100
	bob     = address("g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj") // demo index 1, 250
	mallory = address("g1sqmuwtsrgd6t8y2n8f6z5xkltmpmcd64sx3vgg")
)

func fund(n int64) {
	testing.IssueCoins(Address(), chain.NewCoins(chain.NewCoin(Denom, n)))
}

func balanceOf(a address) int64 {
	return banker.NewReadonlyBanker().GetCoins(a).AmountOf(Denom)
}

// Every seeded allocation must verify against the seeded root, and no other
// address or amount may.
func TestDemoDropVerifies(t *testing.T) {
	seed()
	if Total() != 4 || Root() == "" {
		t.Fatalf("seed left Total=%d Root=%q", Total(), Root())
	}
	for i, a := range demoAllocations {
		proof := DemoProof(i)
		if !Verify(i, a.Address, a.Amount, proof) {
			t.Errorf("allocation %d does not verify", i)
		}
		if Verify(i, mallory, a.Amount, proof) {
			t.Errorf("allocation %d verified for the wrong address", i)
		}
		if Verify(i, a.Address, a.Amount+1, proof) {
			t.Errorf("allocation %d verified for the wrong amount", i)
		}
		if i > 0 && Verify(i-1, a.Address, a.Amount, proof) {
			t.Errorf("allocation %d verified at the wrong index", i)
		}
	}
}

// The leaf is the whole interface to an off-chain generator, so pin it.
func TestLeafEncoding(t *testing.T) {
	got := Leaf(3, alice, 1234)
	want := "gno.land/r/moul/x/daily/merkledrop/v1|3|g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5|1234"
	if got != want {
		t.Errorf("Leaf = %q, want %q", got, want)
	}
}

func TestClaimPays(cur realm, t *testing.T) {
	seed()
	fund(1000)
	before := balanceOf(alice)

	testing.SetRealm(testing.NewUserRealm(alice))
	Claim(cross(cur), 0, 100, DemoProof(0))

	if got := balanceOf(alice) - before; got != 100 {
		t.Errorf("alice received %d ugnot, want 100", got)
	}
	if !HasClaimed(0) {
		t.Error("index 0 not marked claimed")
	}
	if ClaimedBy(0) != alice {
		t.Errorf("ClaimedBy(0) = %s, want alice", ClaimedBy(0))
	}
	if Paid() != 100 || Claims() != 1 {
		t.Errorf("Paid=%d Claims=%d, want 100 and 1", Paid(), Claims())
	}
	if Balance() != 900 {
		t.Errorf("drop balance %d, want 900", Balance())
	}
}

func TestClaimRejects(cur realm, t *testing.T) {
	seed()
	fund(1000)

	testing.SetRealm(testing.NewUserRealm(alice))
	urequire.AbortsContains(t, cur, "invalid proof", func() {
		Claim(cross(cur), 0, 999, DemoProof(0)) // wrong amount
	})
	urequire.AbortsContains(t, cur, "invalid proof", func() {
		Claim(cross(cur), 1, 250, DemoProof(1)) // bob's allocation, alice calling
	})
	urequire.AbortsContains(t, cur, "invalid proof", func() {
		Claim(cross(cur), 0, 100, "deadbeef") // malformed proof
	})
	urequire.AbortsContains(t, cur, "amount must be positive", func() {
		Claim(cross(cur), 0, 0, DemoProof(0))
	})

	testing.SetRealm(testing.NewUserRealm(mallory))
	urequire.AbortsContains(t, cur, "invalid proof", func() {
		Claim(cross(cur), 0, 100, DemoProof(0)) // not in the tree at all
	})

	// Nothing above may have consumed an allocation.
	if Claims() != 0 || Paid() != 0 {
		t.Errorf("a rejected claim left state behind: Claims=%d Paid=%d", Claims(), Paid())
	}
}

func TestDoubleClaimRejected(cur realm, t *testing.T) {
	seed()
	fund(1000)
	testing.SetRealm(testing.NewUserRealm(bob))
	Claim(cross(cur), 1, 250, DemoProof(1))
	urequire.AbortsContains(t, cur, "already claimed", func() {
		Claim(cross(cur), 1, 250, DemoProof(1))
	})
	if Claims() != 1 {
		t.Errorf("Claims = %d, want 1", Claims())
	}
}

// An underfunded drop must refuse rather than mark the allocation claimed and
// leave the recipient with nothing to re-claim.
func TestUnderfundedDropDoesNotBurnAnAllocation(cur realm, t *testing.T) {
	seed()
	fund(10) // less than alice's 100
	testing.SetRealm(testing.NewUserRealm(alice))
	urequire.AbortsContains(t, cur, "cannot cover", func() {
		Claim(cross(cur), 0, 100, DemoProof(0))
	})
	if HasClaimed(0) {
		t.Error("a refused claim still consumed the allocation")
	}
	fund(1000)
	Claim(cross(cur), 0, 100, DemoProof(0))
	if !HasClaimed(0) {
		t.Error("the claim did not go through once funded")
	}
}

func TestSetDropOwnerOnly(cur realm, t *testing.T) {
	seed()
	newRoot := merkle.New([][]byte{[]byte("only-leaf")}).RootHex()

	testing.SetRealm(testing.NewUserRealm(mallory))
	urequire.AbortsContains(t, cur, "not owner", func() {
		SetDrop(cross(cur), newRoot, 1, 0)
	})

	testing.SetRealm(testing.NewUserRealm(Ownable.Owner()))
	SetDrop(cross(cur), newRoot, 1, 0)
	if Root() != newRoot || Total() != 1 {
		t.Errorf("SetDrop left Root=%s Total=%d", Root(), Total())
	}
	if len(demo) != 0 {
		t.Error("a real drop must not keep the seeded allocation list")
	}
	if Claims() != 0 || Paid() != 0 {
		t.Error("SetDrop did not reset the claim ledger")
	}
}

func TestSetDropRejectsBadInput(cur realm, t *testing.T) {
	seed()
	testing.SetRealm(testing.NewUserRealm(Ownable.Owner()))
	good := merkle.New([][]byte{[]byte("x")}).RootHex()
	urequire.AbortsContains(t, cur, "32 bytes of hex", func() { SetDrop(cross(cur), "zz", 1, 0) })
	urequire.AbortsContains(t, cur, "32 bytes of hex", func() { SetDrop(cross(cur), "abcd", 1, 0) })
	urequire.AbortsContains(t, cur, "total must be positive", func() { SetDrop(cross(cur), good, 0, 0) })
}

func TestClosingAndSweep(cur realm, t *testing.T) {
	seed()
	fund(1000)
	owner := Ownable.Owner()
	testing.SetRealm(testing.NewUserRealm(owner))

	// A drop that never closes can never be swept: that is what setting a
	// closing height buys.
	urequire.AbortsContains(t, cur, "not closed yet", func() { Sweep(cross(cur)) })

	closeAt := runtime.ChainHeight() + 10
	root := merkle.New([][]byte{[]byte(Leaf(0, alice, 100))}).RootHex()
	SetDrop(cross(cur), root, 1, closeAt)
	if IsClosed() {
		t.Fatal("drop closed before its height")
	}
	urequire.AbortsContains(t, cur, "not closed yet", func() { Sweep(cross(cur)) })

	testing.SkipHeights(11)
	if !IsClosed() {
		t.Fatal("drop still open past its closing height")
	}
	testing.SetRealm(testing.NewUserRealm(alice))
	urequire.AbortsContains(t, cur, "has closed", func() {
		Claim(cross(cur), 0, 100, "")
	})

	ownerBefore := balanceOf(owner)
	testing.SetRealm(testing.NewUserRealm(owner))
	Sweep(cross(cur))
	if Balance() != 0 {
		t.Errorf("drop balance after sweep = %d, want 0", Balance())
	}
	if balanceOf(owner)-ownerBefore != 1000 {
		t.Errorf("owner received %d, want 1000", balanceOf(owner)-ownerBefore)
	}
	seed()
}

func TestIndexKeyPadsForOrdering(t *testing.T) {
	// ufmt has no width flags, so the padding is by hand. Unpadded keys sort
	// "0","1","10","11","2" and Render loses the order past nine entries.
	if indexKey(7) != "000007" || indexKey(123456) != "123456" {
		t.Errorf("indexKey(7)=%q indexKey(123456)=%q", indexKey(7), indexKey(123456))
	}
	if !(indexKey(2) < indexKey(10)) {
		t.Error("padded keys do not sort numerically")
	}
}
