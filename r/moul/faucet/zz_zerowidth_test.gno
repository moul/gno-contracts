package faucet

import (
	"testing"
)

// zwBlank holds one input per rune range chain/markdown.StripBidiAndZeroWidth
// removes (U+200B..U+200F, U+202A..U+202E, U+2066..U+2069, U+FEFF), plus a mix
// with real spaces. strings.TrimSpace keeps every one of them and the render
// strips them all, so each must be refused.
var zwBlank = []string{
	"\u200b\u200b\u200b", // ZWSP
	"\u200d",             // ZWJ
	"\u200e",             // LRM
	"\u202e",             // RLO
	"\u2066\u2069",       // LRI PDI
	"\ufeff",             // BOM
	" \u200b \u200b ",    // mixed with real spaces
}

// zwOK must stay accepted: the stripper removes the marks and leaves text.
var zwOK = []string{"a", "a\u200bb", "  padded  "}

func TestZeroWidthReasonIsRefused(cur realm, t *testing.T) {
	reset()
	defer reset()
	testing.SetRealm(testing.NewUserRealm(carl))
	for _, s := range zwBlank {
		if revive(func() { Request(cross(cur), zoe.String(), 1_000_000, s) }) == nil {
			t.Errorf("Request accepted reason %q, which the render strips to blank", s)
		}
	}
	for _, s := range zwOK {
		if r := revive(func() { Request(cross(cur), zoe.String(), 1_000_000, s) }); r != nil {
			t.Errorf("Request refused reason %q: %v", s, r)
		}
	}
	if Requests() != len(zwOK) {
		t.Errorf("Requests = %d, want %d", Requests(), len(zwOK))
	}
}

func TestZeroWidthDenyReasonIsRefused(cur realm, t *testing.T) {
	reset()
	defer reset()
	testing.SetRealm(testing.NewUserRealm(carl))
	id := Request(cross(cur), zoe.String(), 1_000_000, "to try the chain")
	testing.SetRealm(testing.NewUserRealm(Owner))
	for _, s := range zwBlank {
		if revive(func() { Deny(cross(cur), id, s) }) == nil {
			t.Errorf("Deny accepted reason %q, which the render strips to blank", s)
		}
	}
	if Status(id) != StatusPending {
		t.Fatalf("Status = %q after blank denials, want %q", Status(id), StatusPending)
	}
	for _, s := range zwOK {
		testing.SetRealm(testing.NewUserRealm(carl))
		id := Request(cross(cur), zoe.String(), 1_000_000, "to try the chain")
		testing.SetRealm(testing.NewUserRealm(Owner))
		if r := revive(func() { Deny(cross(cur), id, s) }); r != nil {
			t.Errorf("Deny refused reason %q: %v", s, r)
		}
		if Status(id) != StatusDenied {
			t.Errorf("Status = %q, want %q", Status(id), StatusDenied)
		}
	}
}
