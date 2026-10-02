package connect4

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// The game list links each game to this realm's own page. It once linked
// to the malformed gno.land/r:<id>.
func TestListLinksNameThisRealm(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("red")))
	id := NewGame(cross(cur), testutils.TestAddress("yellow"))
	out := Render("")
	s := ""
	for n := id; n > 0; n /= 10 {
		s = string(rune(byte(n%10)+byte(48))) + s
	}
	uassert.True(t, strings.Contains(out, "](/r/moul/x/daily/connect4/v1:"+s+")"), out)
}
