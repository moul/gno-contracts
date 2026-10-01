package handles

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// A bio is the caller's text: escaped on the handle page.
func TestBioIsEscaped(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("escaper")))
	Register(cross(cur), "escaper")
	SetBio(cross(cur), "[claim](https://evil.example)")
	page := Render("escaper")
	uassert.False(t, strings.Contains(page, "[claim](https://evil.example)"), page)
}
