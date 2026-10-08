package grants

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

// Finding 325-cost-at-caps-1. The board's index rendered every request ever
// made. Apply is open to anyone and nothing removes a request, so the cost
// every reader of the board paid was set by whoever had applied the most.
//
// Both comparison points are above the cap on purpose: comparing a count below
// it with one above measures the cap arriving, not the page being bounded.
func TestTheBoardIndexIsBoundedByWhatItShows(t *testing.T) {
	p := NewProgram("ugnot", alice, bob, carol)
	rr := Renderer{
		Program: p, Title: "Board", Intro: "x",
		Path: "gno.land/r/example/board/v0", Link: "/r/example/board/v0",
		Treasury: testutils.TestAddress("treasury"), Balance: 0,
	}

	apply := func(from, to int) {
		for i := from; i < to; i++ {
			who := testutils.TestAddress("applicant" + strconv.Itoa(i))
			if _, err := p.Apply(who, "Request "+strconv.Itoa(i),
				"A body long enough to be accepted by the validator.",
				"one milestone:100", int64(1000+i)); err != nil {
				t.Fatalf("Apply(%d): %v", i, err)
			}
		}
	}

	apply(0, 40)
	small := rr.Render("")
	apply(40, 200)
	big := rr.Render("")

	rowsSmall := strings.Count(small, "\n|")
	rowsBig := strings.Count(big, "\n|")
	if rowsSmall == 0 {
		t.Fatal("no table rows rendered at all, so this test is measuring nothing")
	}
	if rowsBig > rowsSmall {
		t.Errorf("the board index grew from %d rows to %d when the requests went from 40 to 200: "+
			"anybody can set what every reader of this board pays", rowsSmall, rowsBig)
	}
}
