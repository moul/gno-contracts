package wiki

import (
	"testing"

	"gno.land/p/nt/markdown/sanitize/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestParseTitle(t *testing.T) {
	cases := []struct {
		name    string
		in      string
		wantNS  Namespace
		want    string // canonical String(), "" when an error is expected
		wantErr error
	}{
		{"plain", "Gno land", NSMain, "Gno land", nil},
		{"underscores become spaces", "Gno_land", NSMain, "Gno land", nil},
		{"whitespace collapses", "  Gno   land  ", NSMain, "Gno land", nil},
		{"first letter is upper-cased", "gno land", NSMain, "Gno land", nil},
		{"namespace prefix", "Help:Gno land", NSHelp, "Help:Gno land", nil},
		{"namespace prefix is case-insensitive", "help:gno_land", NSHelp, "Help:Gno land", nil},
		{"category", "Category:Chains", NSCategory, "Category:Chains", nil},
		{"unknown prefix stays in the name", "Foo:Bar", NSMain, "Foo:Bar", nil},
		{"unicode letters are allowed", "Élysée", NSMain, "Élysée", nil},
		{"unicode is upper-cased too", "élysée", NSMain, "Élysée", nil},
		{"zero-width characters are stripped", "Gno​land", NSMain, "Gnoland", nil},
		{"empty", "", NSMain, "", ErrEmptyTitle},
		{"whitespace only", "   ", NSMain, "", ErrEmptyTitle},
		{"namespace with no name", "Help:", NSMain, "", ErrEmptyTitle},
		{"slash is rejected", "Gno/land", NSMain, "", ErrTitleChar},
		{"pipe is rejected", "Gno|land", NSMain, "", ErrTitleChar},
		{"markdown star is rejected", "Gno*land", NSMain, "", ErrTitleChar},
		{"bracket is rejected", "Gno[land", NSMain, "", ErrTitleChar},
		{"hash is rejected", "Gno#land", NSMain, "", ErrTitleChar},
	}
	for _, tc := range cases {
		got, err := ParseTitle(tc.in)
		if tc.wantErr != nil {
			uassert.ErrorIs(t, err, tc.wantErr, tc.name)
			continue
		}
		if !uassert.NoError(t, err, tc.name) {
			continue
		}
		uassert.Equal(t, tc.want, got.String(), tc.name)
		uassert.Equal(t, uint64(tc.wantNS), uint64(got.NS), tc.name+" (namespace)")
	}
}

func TestTitleTooLong(t *testing.T) {
	long := ""
	for i := 0; i <= MaxTitleLen; i++ {
		long += "a"
	}
	_, err := ParseTitle(long)
	uassert.ErrorIs(t, err, ErrTitleTooLong)
}

func TestTitleKeyOrdersByNamespace(t *testing.T) {
	// The avl key must group namespaces, and must keep doing so past nine
	// namespaces, which is why the code is a fixed-width string rather than
	// a ufmt-formatted number.
	uassert.Equal(t, "00:Gno land", MustParseTitle("Gno land").Key())
	uassert.Equal(t, "01:Gno land", MustParseTitle("User:Gno land").Key())
	uassert.True(t, MustParseTitle("Gno land").Key() < MustParseTitle("User:Alpha").Key(),
		"every main-namespace key must sort before every User key")
}

func TestTitleSlug(t *testing.T) {
	uassert.Equal(t, "Gno_land", MustParseTitle("Gno land").Slug())
	uassert.Equal(t, "User:Gno_land", MustParseTitle("User:Gno land").Slug())
	uassert.Equal(t, "Mercury_(planet)", MustParseTitle("Mercury (planet)").Slug())
}

// TestTitleSurvivesTheRenderPipeline pins the coupling between the title
// charset and the markdown sanitizer.
//
// Rendering escapes the whole body first and rewrites wikilinks second, so
// every title character has to survive that round trip: sanitize escapes it,
// ScanLinks finds the link in the escaped text, and unescapeInline hands
// ParseTitle the bytes the author typed. The sanitizer escapes with
// backslashes ("(" becomes "\(") which unescapeInline undoes, but a character
// escaped as an entity ("&" becomes "&amp;") would not survive, which is why
// the charset excludes those. This test fails the day either side changes.
func TestTitleSurvivesTheRenderPipeline(t *testing.T) {
	// The ASCII allowlist plus a couple of accepted non-ASCII letters; the
	// whole set has to fit in one title, so this is not every valid rune.
	chars := "Élysée東京"
	for r := rune(0); r < 0x80; r++ {
		if validTitleRune(r) && r != ' ' {
			chars += string(r)
		}
	}
	want := MustParseTitle(chars)

	escaped := sanitize.BlockRich("[[" + chars + "]]\n")
	links := ScanLinks(escaped, `\[\[`, `\]\]`)
	if !uassert.Equal(t, 1, len(links), "the escaped body must still contain exactly one link") {
		return
	}
	got, err := ParseTitle(unescapeInline(links[0].Target))
	uassert.NoError(t, err)
	uassert.Equal(t, want.String(), got.String())
}
