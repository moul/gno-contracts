package threads

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

// Finding 325-cost-at-caps-1 (review run 001-cd0b6a9).
//
// A Render is paid for by every reader, so its cost must be bounded by what it
// SHOWS, not by what anybody has ever written. Post and Reply are both
// permissionless and the page key is any string, so an attacker fills a page
// they do not own and every render of it inherits the cost. There is no delete
// path anywhere in threads, so it is irreversible.
//
// These tests are the invariant, not the implementation: the rendered output
// must stop growing once the collection is past the cap.

// fill posts n threads on page from n distinct addresses.
func fill(cur realm, t *testing.T, page string, n int) {
	t.Helper()
	for i := 0; i < n; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("filler" + strconv.Itoa(i))))
		Post(cross(cur), page, "thread number "+strconv.Itoa(i))
	}
}

func TestAPageRenderIsBoundedByWhatItShows(cur realm, t *testing.T) {
	reset(cur)
	const page = "gno.land/r/moul/home"

	fill(cur, t, page, 40)
	small := Render("page/" + page)

	fill(cur, t, page, 160) // 200 total
	big := Render("page/" + page)

	rowsSmall := strings.Count(small, "\n|")
	rowsBig := strings.Count(big, "\n|")

	if rowsBig > rowsSmall {
		t.Errorf("the page render grew from %d rows to %d when the board went from 40 threads to 200: "+
			"its cost is bounded by what has been written, not by what it shows", rowsSmall, rowsBig)
	}
	if rowsSmall == 0 {
		t.Fatal("no table rows rendered at all, so this test is measuring nothing")
	}
}

func TestAThreadRenderIsBoundedByWhatItShows(cur realm, t *testing.T) {
	reset(cur)
	const page = "gno.land/r/moul/home"

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Post(cross(cur), page, "a thread with many replies")

	for i := 0; i < 40; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("rep" + strconv.Itoa(i))))
		Reply(cross(cur), id, "reply "+strconv.Itoa(i))
	}
	small := Render("thread/" + strconv.FormatInt(id, 10))

	for i := 40; i < 200; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("rep" + strconv.Itoa(i))))
		Reply(cross(cur), id, "reply "+strconv.Itoa(i))
	}
	big := Render("thread/" + strconv.FormatInt(id, 10))

	rowsSmall := strings.Count(small, "\n|")
	rowsBig := strings.Count(big, "\n|")

	if rowsBig > rowsSmall {
		t.Errorf("the thread render grew from %d rows to %d when the replies went from 40 to 200: "+
			"every reader pays for every reply anybody ever wrote", rowsSmall, rowsBig)
	}
	if rowsSmall == 0 {
		t.Fatal("no table rows rendered at all, so this test is measuring nothing")
	}
}
