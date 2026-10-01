package linktree

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// The bio and a label are escaped, and a URL that could break out of its
// link destination, or is not http(s), is refused when it is written.
func TestProfileFieldsAreEscapedAndURLsChecked(cur realm, t *testing.T) {
	who := testutils.TestAddress("escaper")
	testing.SetRealm(testing.NewUserRealm(who))
	SetBio(cross(cur), "[claim](https://evil.example)")
	AddLink(cross(cur), "[claim](https://evil.example)", "https://ok.example/path")
	page := Render(who.String())
	uassert.False(t, strings.Contains(page, "[claim](https://evil.example)"), page)
	uassert.AbortsContains(t, cur, "url must be http", func() { AddLink(cross(cur), "x", "javascript:alert(1)") })
	uassert.AbortsContains(t, cur, "url must be http", func() { AddLink(cross(cur), "x", "https://a.example) [evil](https://b.example") })
}

// A path that names nothing is echoed back on the not-found page. It is the
// visitor's text, so a backtick in it must not close a code span and let a
// link through.
func TestNotFoundPathIsEscaped(t *testing.T) {
	out := Render("x` [claim](https://evil.example) `")
	uassert.False(t, strings.Contains(out, "[claim](https://evil.example)"), out)
}
