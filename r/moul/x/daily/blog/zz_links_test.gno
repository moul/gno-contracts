package blog

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// Every link the realm renders names its own absolute path. A dead link here
// once read /r/REPLACE_ADDR/blog, and a test that only checked "a back link
// exists" passed against it.
func TestLinksNameThisRealm(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("linker")))
	id := Publish(cross(cur), "Linked", "body")
	idx := Render("")
	uassert.True(t, strings.Contains(idx, "](/r/moul/x/daily/blog/v1:/"), idx)
	page := Render("/" + itoaTest(id))
	uassert.True(t, strings.Contains(page, "(/r/moul/x/daily/blog/v1)"), page)
}

func itoaTest(n int) string {
	if n == 0 {
		return "0"
	}
	s := ""
	for n > 0 {
		s = string(rune(byte(n%10)+byte(48))) + s
		n /= 10
	}
	return s
}
