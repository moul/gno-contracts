package vault

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// A key and a value are the owner's text, written into table cells: a pipe
// must not open a column and a link must not go live.
func TestKeysAndValuesAreTableSafe(cur realm, t *testing.T) {
	who := testutils.TestAddress("escaper")
	testing.SetRealm(testing.NewUserRealm(who))
	Set(cross(cur), "k | [claim](https://evil.example)", "[claim](https://evil.example)")
	page := Render(who.String())
	uassert.False(t, strings.Contains(page, "[claim](https://evil.example)"), page)
	uassert.False(t, strings.Contains(page, "| k | "), page)
}
