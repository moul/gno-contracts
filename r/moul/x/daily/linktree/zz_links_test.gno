package linktree

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// The index links each profile to this realm's own page. It once linked to
// /r/REPLACE_ADDR/linktree.
func TestIndexLinksNameThisRealm(cur realm, t *testing.T) {
	who := testutils.TestAddress("linker")
	testing.SetRealm(testing.NewUserRealm(who))
	SetBio(cross(cur), "links")
	out := Render("")
	uassert.True(t, strings.Contains(out, "](/r/moul/x/daily/linktree/v1:"+who.String()+")"), out)
}
