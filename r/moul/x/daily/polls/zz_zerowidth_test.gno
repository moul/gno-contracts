package polls

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

func TestZeroWidthQuestionIsRefused(cur realm, t *testing.T) {
	resetState()
	defer resetState()
	testing.SetRealm(testing.NewUserRealm(alice))
	for _, s := range zwBlank {
		if revive(func() { CreatePoll(cross(cur), s, "x,y") }) == nil {
			t.Errorf("CreatePoll accepted question %q, which the render strips to blank", s)
		}
	}
	for _, s := range zwOK {
		if r := revive(func() { CreatePoll(cross(cur), s, "x,y") }); r != nil {
			t.Errorf("CreatePoll refused question %q: %v", s, r)
		}
	}
	if PollCount() != len(zwOK) {
		t.Errorf("PollCount = %d, want %d", PollCount(), len(zwOK))
	}
}

func TestZeroWidthOptionIsDropped(t *testing.T) {
	for _, s := range zwBlank {
		if got := parseOptions("x," + s); len(got) != 1 {
			t.Errorf("parseOptions kept option %q, which the render strips to blank: %q", s, got)
		}
	}
	for _, s := range zwOK {
		if got := parseOptions("x," + s); len(got) != 2 {
			t.Errorf("parseOptions dropped option %q, which renders as text: %q", s, got)
		}
	}
}
