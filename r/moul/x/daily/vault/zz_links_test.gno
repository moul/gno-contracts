package vault

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// The index links each vault to this realm's own page. It once linked to
// the malformed gno.land/r:<address>.
func TestIndexLinksNameThisRealm(cur realm, t *testing.T) {
	who := testutils.TestAddress("linker")
	testing.SetRealm(testing.NewUserRealm(who))
	Set(cross(cur), "k", "v")
	out := Render("")
	uassert.True(t, strings.Contains(out, "](/r/moul/x/daily/vault/v1:"+who.String()+")"), out)
}
