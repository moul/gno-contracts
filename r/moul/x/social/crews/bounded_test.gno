package crews

import (
	"strconv"
	"strings"
	"testing"
)

// Finding 325-cost-at-caps-1. A crew's page rendered every proposal the crew
// had ever had. Proposing is open to every member and nothing deletes one, so
// the cost every reader of that page paid grew without a bound anybody
// controls.
//
// Both comparison points are above the cap on purpose: comparing a count below
// it with one above measures the cap arriving, not the page being bounded.
func TestACrewPageIsBoundedByWhatItShows(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, 1000000, "the crew")

	for i := 0; i < 40; i++ {
		testing.SetRealm(testing.NewUserRealm(alice))
		Propose(cross(cur), id, "proposal number "+strconv.Itoa(i))
	}
	small := Render("crew/" + strconv.FormatInt(id, 10))

	for i := 40; i < 200; i++ {
		testing.SetRealm(testing.NewUserRealm(alice))
		Propose(cross(cur), id, "proposal number "+strconv.Itoa(i))
	}
	big := Render("crew/" + strconv.FormatInt(id, 10))

	rowsSmall := strings.Count(small, "\n|")
	rowsBig := strings.Count(big, "\n|")
	if rowsSmall == 0 {
		t.Fatal("no table rows rendered at all, so this test is measuring nothing")
	}
	if rowsBig > rowsSmall {
		t.Errorf("the crew page grew from %d rows to %d when the proposals went from 40 to 200: "+
			"every reader pays for every proposal the crew has ever had", rowsSmall, rowsBig)
	}
}
