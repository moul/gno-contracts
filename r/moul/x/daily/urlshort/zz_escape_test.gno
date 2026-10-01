package urlshort

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// The note is escaped, and a target that could close its <autolink>, or is
// not http(s), is refused when it is written.
func TestNoteIsEscapedAndTargetChecked(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("escaper")))
	Shorten(cross(cur), "esc", "https://ok.example", "[claim](https://evil.example)")
	page := Render("esc")
	uassert.False(t, strings.Contains(page, "[claim](https://evil.example)"), page)
	uassert.AbortsContains(t, cur, "url must be http", func() { Shorten(cross(cur), "esc2", "https://a.example> [evil](https://b.example)", "") })
	uassert.AbortsContains(t, cur, "url must be http", func() { Shorten(cross(cur), "esc3", "javascript:alert(1)", "") })
}
