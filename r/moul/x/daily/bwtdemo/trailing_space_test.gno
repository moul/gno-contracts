package bwtdemo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// TestRenderKeepsTrailingSpaceInCells pins the case that shipped broken:
// "hello world" transforms to "olhdrellwo ", and a bare table cell is trimmed,
// so the page showed "olhdrellwo" above a green round-trips check, and the
// matrix rendered rows 0 and 10 identically. Each value is now a padded code
// span, which CommonMark strips by exactly one space on each side.
func TestRenderKeepsTrailingSpaceInCells(t *testing.T) {
	got := Render("/hello world")
	uassert.True(t, strings.Contains(got, "| transformed | ` olhdrellwo  ` |\n"),
		"the transformed value keeps its trailing space")
	// The space is the first byte of "hello world"'s smallest rotation, so it
	// is also a last byte, and that cell must not render empty.
	uassert.True(t, strings.Contains(got, " | `   ` |\n"), "a space last byte renders as a space")

	// No two matrix rows may render the same: the rotations are distinct.
	seen := map[string]bool{}
	for _, line := range strings.Split(got, "\n") {
		if !strings.HasPrefix(line, "| ") || !strings.Contains(line, "`") {
			continue
		}
		cells := strings.SplitN(line, " | ", 3)
		if len(cells) < 3 || cells[0] == "| transformed" {
			continue
		}
		rotation := cells[1]
		uassert.False(t, seen[rotation], "matrix row rendered twice: "+strings.ReplaceAll(rotation, "%", "%%"))
		seen[rotation] = true
	}
	uassert.Equal(t, 11, len(seen))
}
