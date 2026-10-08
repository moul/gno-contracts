package vouch

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

// Finding 325-cost-at-caps-1. Anyone can add a vouch edge to somebody else's
// page, with a zero bond, and nothing sweeps them. Both tables on an address
// page rendered every edge, so the cost every reader of that page paid was set
// by whoever had been most persistent.
//
// The loop is inline rather than in a helper on purpose: testing.SetRealm is
// call-frame scoped, so switching account inside a helper leaves the crossing
// call running as whoever the test body was, and every iteration records the
// same edge. The first version of this test did exactly that, recorded one
// voucher instead of two hundred, and still passed.
func TestAnAddressPageIsBoundedByWhatItShows(cur realm, t *testing.T) {
	reset()

	for i := 0; i < 40; i++ {
		fund(0)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("v" + strconv.Itoa(i))))
		Vouch(cross(cur), alice, "because "+strconv.Itoa(i))
	}
	small := Render("addr/" + alice.String())

	for i := 40; i < 200; i++ {
		fund(0)
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("v" + strconv.Itoa(i))))
		Vouch(cross(cur), alice, "because "+strconv.Itoa(i))
	}
	big := Render("addr/" + alice.String())

	if n := len(VouchedBy(alice)); n != 200 {
		t.Fatalf("only %d voucher(s) were recorded, so this test is measuring nothing", n)
	}

	rowsSmall := strings.Count(small, "\n|")
	rowsBig := strings.Count(big, "\n|")
	if rowsSmall == 0 {
		t.Fatal("no table rows rendered at all, so this test is measuring nothing")
	}
	if rowsBig > rowsSmall {
		t.Errorf("the address page grew from %d rows to %d when the vouchers went from 40 to 200: "+
			"anybody can set what every reader of this page pays", rowsSmall, rowsBig)
	}
}
