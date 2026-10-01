package polls

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// A poll page links back to this realm. It once linked to
// /r/REPLACE_ADDR/polls.
func TestPollPageLinksBackToThisRealm(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("linker")))
	id := CreatePoll(cross(cur), "Linked?", "yes,no")
	page := Render(itoaTest(id))
	uassert.True(t, strings.Contains(page, "[← all polls](/r/moul/x/daily/polls/v1)"), page)
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
