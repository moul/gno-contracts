package curated

import "testing"

// Finding 325-input-validation-1 (review run 001-cd0b6a9).
//
// A validator that calls a field required must agree with the escaper its own
// render runs. strings.TrimSpace uses unicode.IsSpace, which does NOT include
// U+200B and the rest of the bidi and zero-width set, while every escaper on
// the output side runs chain/markdown.StripBidiAndZeroWidth, which does. So a
// value made only of those characters passes validation and renders as
// nothing: a required field that is blank on the page.
//
// The cases below are the invariant, not the implementation. A value the
// validator accepts must still be non-empty after the stripper.
func TestValidatorsAgreeWithTheEscaper(t *testing.T) {
	// One per class the stripper removes, so a fix that handles only
	// U+200B does not pass.
	blank := []string{
		"\u200b\u200b\u200b",   // ZWSP
		"\u200d",                // ZWJ
		"\u200e",                // LRM
		"\u202e",                // RLO
		"\u2066\u2069",          // LRI PDI
		"\ufeff",                // BOM
		" \u200b \u200b ",        // mixed with real spaces
	}
	// These must stay valid: the stripper removes the marks and leaves text.
	ok := []string{
		"a",
		"a\u200bb",
		"  padded  ",
	}

	for _, s := range blank {
		if ValidDescription(s) {
			t.Errorf("ValidDescription(%q) is true, but the render strips it to empty", s)
		}
	}
	for _, s := range ok {
		if !ValidDescription(s) {
			t.Errorf("ValidDescription(%q) is false, but it renders as real text", s)
		}
	}

}
