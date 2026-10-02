package handles

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// The index links each handle to this realm's own page, and a missing
// handle links back to the index. Both once resolved to gno.land itself.
func TestLinksNameThisRealm(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("linker")))
	Register(cross(cur), "linker")
	idx := Render("")
	uassert.True(t, strings.Contains(idx, "[linker](/r/moul/x/daily/handles/v1:linker)"), idx)
	miss := Render("nobodyhere")
	uassert.True(t, strings.Contains(miss, "[← all handles](/r/moul/x/daily/handles/v1)"), miss)
}
