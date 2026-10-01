package polls

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// A question and its options are the creator's text: escaped.
func TestQuestionAndOptionsAreEscaped(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("escaper")))
	id := CreatePoll(cross(cur), "[claim](https://evil.example)", "[claim](https://evil.example)"+",no")
	page := Render(itoaTest(id))
	uassert.False(t, strings.Contains(page, "[claim](https://evil.example)"), page)
	uassert.False(t, strings.Contains(Render(""), "[claim](https://evil.example)"), Render(""))
}
