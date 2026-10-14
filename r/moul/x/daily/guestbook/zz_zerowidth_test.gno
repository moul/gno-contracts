package guestbook

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

func zwPanics(f func()) (p bool) {
	defer func() {
		if recover() != nil {
			p = true
		}
	}()
	f()
	return false
}

func TestZeroWidthMessageIsRefused(t *testing.T) {
	resetState()
	defer resetState()
	for _, s := range zwBlank {
		if !zwPanics(func() { addEntry("g1alice", s, 1) }) {
			t.Errorf("addEntry(%q) accepted a message the render strips to blank", s)
		}
	}
	for _, s := range zwOK {
		if zwPanics(func() { addEntry("g1alice", s, 1) }) {
			t.Errorf("addEntry(%q) refused a message that renders as text", s)
		}
	}
	if Count() != len(zwOK) {
		t.Errorf("Count = %d, want %d", Count(), len(zwOK))
	}
}
