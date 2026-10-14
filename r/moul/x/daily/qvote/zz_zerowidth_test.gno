package qvote

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
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

func TestZeroWidthQuestionAndOptionAreRefused(cur realm, t *testing.T) {
	resetState()
	defer resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))
	for _, s := range zwBlank {
		if revive(func() { CreatePoll(cross(cur), s, "x,y") }) == nil {
			t.Errorf("CreatePoll accepted question %q, which the render strips to blank", s)
		}
		// With the blank option dropped, one option is left and the poll is refused.
		if revive(func() { CreatePoll(cross(cur), "q", "x,"+s) }) == nil {
			t.Errorf("CreatePoll kept option %q, which the render strips to blank", s)
		}
	}
	for _, s := range zwOK {
		if r := revive(func() { CreatePoll(cross(cur), s, "x,"+s) }); r != nil {
			t.Errorf("CreatePoll refused question and option %q: %v", s, r)
		}
	}
	if nextID != len(zwOK) {
		t.Errorf("%d poll(s) created, want %d", nextID, len(zwOK))
	}
}
