package patron

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

// Finding 325-cost-at-caps-1. A plan page rendered every all-time supporter.
// Subscribe is permissionless and nothing ever removes a supporter, so the
// cheapest way to make somebody's page expensive was to subscribe from many
// addresses.
//
// Both comparison points are above the cap on purpose: comparing a count below
// it with one above it measures the cap arriving, not the page being bounded.
// The loops are inline because testing.SetRealm is call-frame scoped.
func TestAPlanPageIsBoundedByWhatItShows(cur realm, t *testing.T) {
	reset()
	id := open(cur, t)

	for i := 0; i < 40; i++ {
		pay(price)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("sub" + strconv.Itoa(i))))
		Subscribe(cross(cur), id)
	}
	small := Render("plan/" + strconv.FormatInt(id, 10))

	for i := 40; i < 200; i++ {
		pay(price)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("sub" + strconv.Itoa(i))))
		Subscribe(cross(cur), id)
	}
	big := Render("plan/" + strconv.FormatInt(id, 10))

	rowsSmall := strings.Count(small, "\n|")
	rowsBig := strings.Count(big, "\n|")
	if rowsSmall == 0 {
		t.Fatal("no table rows rendered at all, so this test is measuring nothing")
	}
	if rowsBig > rowsSmall {
		t.Errorf("the plan page grew from %d rows to %d when the supporters went from 40 to 200: "+
			"every reader pays for every address that ever subscribed", rowsSmall, rowsBig)
	}
}
