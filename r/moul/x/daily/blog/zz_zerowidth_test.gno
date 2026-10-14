package blog

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

func TestZeroWidthTitleAndBodyAreRefused(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))
	before := PostCount()
	for _, s := range zwBlank {
		if revive(func() { Publish(cross(cur), s, "body") }) == nil {
			t.Errorf("Publish accepted title %q, which the render strips to blank", s)
		}
		if revive(func() { Publish(cross(cur), "title", s) }) == nil {
			t.Errorf("Publish accepted body %q, which the render strips to blank", s)
		}
	}
	for _, s := range zwOK {
		if r := revive(func() { Publish(cross(cur), s, s) }); r != nil {
			t.Errorf("Publish refused title and body %q: %v", s, r)
		}
	}
	if got := PostCount() - before; got != len(zwOK) {
		t.Errorf("%d post(s) published, want %d", got, len(zwOK))
	}
}
