package blog

import (
	"strconv"
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

func TestZeroWidthTitleIsRefused(cur realm, t *testing.T) {
	reset()
	defer reset()
	testing.SetRealm(testing.NewUserRealm(author))
	for i, s := range zwBlank {
		slug := "zw" + strconv.Itoa(i)
		if revive(func() { Set(cross(cur), slug, s, "2026-10-14", "", "body") }) == nil {
			t.Errorf("Set accepted title %q, which the render strips to blank", s)
		}
	}
	for i, s := range zwOK {
		slug := "ok" + strconv.Itoa(i)
		if r := revive(func() { Set(cross(cur), slug, s, "2026-10-14", "", "body") }); r != nil {
			t.Errorf("Set refused title %q: %v", s, r)
		}
	}
	if posts.Size() != len(zwOK) {
		t.Errorf("%d post(s), want %d", posts.Size(), len(zwOK))
	}
}
