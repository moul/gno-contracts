package gns

import (
	"testing"
)

func TestNormalize(t *testing.T) {
	reset()

	cases := []struct {
		in  string
		out string
		ok  bool
	}{
		{"alice", "alice", true},
		{"ALICE", "alice", true},
		{"Wallet.Alice", "wallet.alice", true},
		{"a", "a", true},
		{"a1-b", "a1-b", true},
		{"-alice", "", false}, // leading hyphen
		{"alice-", "", false}, // trailing hyphen
		{"", "", false},       // empty
		{"a..b", "", false},   // empty label (double dot)
		{"al ice", "", false}, // space
		{"café", "", false},   // non-ASCII
		{"a_b", "", false},    // underscore not allowed
	}
	for _, tc := range cases {
		got, err := Normalize(tc.in)
		if tc.ok {
			noErr(t, err, "normalize "+tc.in)
			eqStr(t, tc.out, got, "normalize "+tc.in)
		} else {
			isErr(t, err, "expected error for "+tc.in)
		}
	}
}

func TestNormalizeDepthAndLength(t *testing.T) {
	reset()

	deep := "a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a" // 17 labels > maxDepth
	_, err := Normalize(deep)
	isErr(t, err, "excessive depth rejected")

	long := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" // 64 > 63
	_, err = Normalize(long)
	isErr(t, err, "excessive label length rejected")
}

func TestStatusAndOwnerLifecycle(cur realm, t *testing.T) {
	reset()

	eqStr(t, string(StatusAvailable), string(Status("alice")), "initial status")
	isFalse(t, Exists("alice"), "not exists initially")

	doRegister(cur, "alice", alice, 1000)

	eqStr(t, string(StatusActive), string(Status("alice")), "post-register status")
	isTrue(t, Exists("alice"), "exists after register")

	owner, ok := OwnerOf("alice")
	isTrue(t, ok, "ownerOf ok")
	eqStr(t, alice.String(), owner, "owner is alice")

	view, ok := GetName("alice")
	isTrue(t, ok, "getName ok")
	eqInt(t, 1, int64(view.Generation), "generation 1")
	eqStr(t, "alice", view.Canonical, "canonical")

	// advance past expiry, into grace (expiry ≈ +1000s, grace ends ≈ +1100s)
	testing.SkipHeights(210) // +1050s
	eqStr(t, string(StatusGrace), string(Status("alice")), "grace status")
	_, ok = OwnerOf("alice")
	isTrue(t, ok, "owner known during grace")

	// advance well past grace -> Expired
	testing.SkipHeights(200) // +1000s more, far beyond grace end
	eqStr(t, string(StatusExpired), string(Status("alice")), "expired status")
	isFalse(t, Exists("alice"), "not exists after grace")
}

func TestExpiredOwnerLosesAuthority(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 1000)

	testing.SkipHeights(300) // beyond grace
	eqStr(t, string(StatusExpired), string(Status("alice")), "expired")

	// Invariant 2: an expired name grants no owner mutation authority. Tested
	// against the single authorization gate directly (mutations funnel through
	// it, then panic on the returned error).
	n := getRaw("alice")
	isTrue(t, n != nil, "raw name present")
	errIs(t, authorize(alice, n, PermManageRecords), errUnauthorized, "expired owner authorize")
	errIs(t, authorize(alice, n, PermTransfer), errUnauthorized, "expired owner transfer")
}
