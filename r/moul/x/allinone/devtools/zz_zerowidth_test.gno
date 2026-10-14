package devtools

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

func TestZeroWidthNoteIsRefused(cur realm, t *testing.T) {
	// Reset, not reset: the author board is what ExampleRender would see.
	Reset(cross(cur))
	for _, s := range zwBlank {
		if revive(func() { Add(cross(cur), s) }) == nil {
			t.Errorf("Add accepted note %q, which is stored escaped as blank", s)
		}
	}
	for _, s := range zwOK {
		if r := revive(func() { Add(cross(cur), s) }); r != nil {
			t.Errorf("Add refused note %q: %v", s, r)
		}
	}
	if notes.Size() != len(zwOK) {
		t.Errorf("%d note(s), want %d", notes.Size(), len(zwOK))
	}
	// Not deferred: a crossing call cannot be.
	Reset(cross(cur))
}
