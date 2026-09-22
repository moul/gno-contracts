package splitter

import (
	"strings"
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func reset() {
	groups = store.Named("splitter: group")
}

func TestRegisterAndOwed(cur realm, t *testing.T) {
	// reset package state for a deterministic run
	reset()

	owner := testutils.TestAddress("owner")
	testing.SetRealm(testing.NewUserRealm(owner))

	a := testutils.TestAddress("alice").String()
	b := testutils.TestAddress("bob").String()

	id := Register(cross(cur), a+","+b, "3,1")
	// v1 ids start at 1: the store never assigns 0, so the zero id stays
	// usable as "absent". v0 handed out 0 for the first group.
	uassert.Equal(t, 1, id, "first group id should be 1")

	// pool 100, shares 3:1 -> alice 75, bob 25
	RecordIncome(cross(cur), id, 100)

	out := Render("")
	uassert.True(t, strings.Contains(out, "Group #1"), "render shows group")
	uassert.True(t, strings.Contains(out, "| 3 | 75 |"), "alice owed 75")
	uassert.True(t, strings.Contains(out, "| 1 | 25 |"), "bob owed 25")
	uassert.True(t, strings.Contains(out, "Pool: 100"), "pool shown")
}

func TestRoundingRemainder(cur realm, t *testing.T) {
	reset()

	owner := testutils.TestAddress("owner2")
	testing.SetRealm(testing.NewUserRealm(owner))

	a := testutils.TestAddress("a").String()
	b := testutils.TestAddress("b").String()
	c := testutils.TestAddress("c").String()

	id := Register(cross(cur), a+","+b+","+c, "1,1,1")
	RecordIncome(cross(cur), id, 100) // 100/3 = 33 each, remainder 1

	out := Render("")
	uassert.True(t, strings.Contains(out, "| 1 | 33 |"), "each owed 33")
	uassert.True(t, strings.Contains(out, "remainder"), "remainder row shown")
	uassert.True(t, strings.Contains(out, "| 1 |\n"), "remainder value 1")
}

func TestBadInputAborts(cur realm, t *testing.T) {
	reset()

	owner := testutils.TestAddress("owner3")
	testing.SetRealm(testing.NewUserRealm(owner))

	a := testutils.TestAddress("alice").String()

	// mismatched payees/shares count aborts
	uassert.AbortsWithMessage(t, cur, "splitter: payees and shares count mismatch", func() {
		Register(cross(cur), a, "1,2")
	})

	// non-positive share aborts
	uassert.AbortsWithMessage(t, cur, "splitter: share must be positive", func() {
		Register(cross(cur), a, "0")
	})
}
