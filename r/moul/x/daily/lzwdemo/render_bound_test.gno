package lzwdemo

import (
	"strings"
	"testing"

	"gno.land/p/moul/x/daily/lzw/v0"
)

// TestRenderInputIsBoundedByMaxLen pins where the URL input is clamped. The
// realm has no limit of its own: the text goes straight to lzw.Encode, which
// refuses anything over lzw.MaxLen before a single row is built. So the
// largest page this realm can produce is one MaxLen-byte input, and one byte
// more is a one-line error rather than a table.
func TestRenderInputIsBoundedByMaxLen(t *testing.T) {
	over := Render("/" + strings.Repeat("x", lzw.MaxLen+1))
	if !strings.Contains(over, lzw.ErrTooLong.Error()) {
		t.Errorf("a %d-byte input should render ErrTooLong, got %q", lzw.MaxLen+1, over[:80])
	}
	if strings.Contains(over, "| # |") {
		t.Errorf("a %d-byte input rendered a table", lzw.MaxLen+1)
	}

	at := Render("/" + strings.Repeat("x", lzw.MaxLen))
	if strings.Contains(at, lzw.ErrTooLong.Error()) {
		t.Errorf("a %d-byte input is within MaxLen and should render", lzw.MaxLen)
	}
	if !strings.Contains(at, "| # | code | bits | means |") {
		t.Errorf("a %d-byte input should render its code table", lzw.MaxLen)
	}
}
