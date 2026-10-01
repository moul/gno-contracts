package blog

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// Anyone may publish, so a title or a body is the caller's text and must not
// become live markdown on the realm's own pages.
func TestTitleAndBodyAreEscaped(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("escaper")))
	id := Publish(cross(cur), "[claim](https://evil.example)", "line one\n[claim](https://evil.example)")
	uassert.False(t, strings.Contains(Render(""), "[claim](https://evil.example)"), Render(""))
	page := Render("/" + itoaTest(id))
	uassert.False(t, strings.Contains(page, "[claim](https://evil.example)"), page)
}
