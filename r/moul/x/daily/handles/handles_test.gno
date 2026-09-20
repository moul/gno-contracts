package handles

import (
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

// reset clears package state between tests so cases stay independent.
func reset() {
	byHandle = avl.Tree{}
	byOwner = avl.Tree{}
}

func TestValidHandle(t *testing.T) {
	cases := map[string]bool{
		"moul":                           true,
		"m":                              false, // too short
		"ab":                             false, // too short
		"Moul":                           false, // uppercase
		"1moul":                          false, // starts with digit
		"moul1":                          true,
		"moul-1":                         false, // hyphen
		"averylonghandlethatistoolong12": false, // too long
	}
	for h, want := range cases {
		if got := validHandle(h); got != want {
			t.Errorf("validHandle(%q) = %v, want %v", h, got, want)
		}
	}
}

func TestRegisterAndLookup(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "moul")

	owner, ok := OwnerOf("moul")
	if !ok || owner != alice {
		t.Fatalf("OwnerOf(moul) = %v, %v; want %v, true", owner, ok, alice)
	}
	handle, ok := HandleOf(alice)
	if !ok || handle != "moul" {
		t.Fatalf("HandleOf(alice) = %q, %v; want moul, true", handle, ok)
	}
	if got := Count(); got != 1 {
		t.Fatalf("Count() = %d, want 1", got)
	}
}

func TestRegisterRejectsTakenHandle(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "moul")

	testing.SetRealm(testing.NewUserRealm(bob))
	defer func() {
		if r := recover(); r == nil {
			t.Errorf("expected panic registering a taken handle")
		}
	}()
	Register(cur, "moul")
}

func TestRegisterRejectsSecondHandleForSameOwner(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "moul")

	testing.SetRealm(testing.NewUserRealm(alice))
	defer func() {
		if r := recover(); r == nil {
			t.Errorf("expected panic when the same owner registers twice")
		}
	}()
	Register(cur, "second")
}

func TestTransferAndRelease(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "moul")

	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), bob)

	if _, ok := HandleOf(alice); ok {
		t.Fatalf("alice should no longer own a handle after transfer")
	}
	handle, ok := HandleOf(bob)
	if !ok || handle != "moul" {
		t.Fatalf("HandleOf(bob) = %q, %v; want moul, true", handle, ok)
	}

	testing.SetRealm(testing.NewUserRealm(bob))
	Release(cross(cur))

	if Count() != 0 {
		t.Fatalf("Count() = %d, want 0 after release", Count())
	}
	if _, ok := OwnerOf("moul"); ok {
		t.Fatalf("moul should be unclaimed after release")
	}
}

func TestSetBioAndRender(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "moul")
	SetBio(cross(cur), "building gno stuff")

	out := Render("/moul")
	if !contains(out, "moul") || !contains(out, "building gno stuff") {
		t.Fatalf("Render(/moul) missing expected content: %s", out)
	}

	index := Render("")
	if !contains(index, "moul") {
		t.Fatalf("Render('') missing handle in index: %s", index)
	}

	missing := Render("/nobody")
	if !contains(missing, "No handle named") {
		t.Fatalf("Render(/nobody) should report missing handle: %s", missing)
	}
}

func contains(s, substr string) bool {
	for i := 0; i+len(substr) <= len(s); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
