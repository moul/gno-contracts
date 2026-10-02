package collatz

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// The leaderboard links each n to this realm's own sequence page. It once
// linked to the malformed gno.land/r:<n>.
func TestLeaderboardLinksNameThisRealm(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("linker")))
	Compute(cross(cur), 7)
	out := Render("")
	uassert.True(t, strings.Contains(out, "](/r/moul/x/daily/collatz/v1:7)"), out)
}
