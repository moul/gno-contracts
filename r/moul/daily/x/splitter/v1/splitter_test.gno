package splitter

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

func reset() {
	groups = avl.Tree{}
	nextID = 0
}

func TestRegisterAndOwed(cur realm, t *testing.T) {
	// reset package state for a deterministic run
	reset()

	owner := testutils.TestAddress("owner")
	testing.SetRealm(testing.NewUserRealm(owner))

	a := testutils.TestAddress("alice").String()
	b := testutils.TestAddress("bob").String()

	id := cross(Register)(cur, a+","+b, "3,1")
	uassert.Equal(t, 0, id, "first group id should be 0")

	// pool 100, shares 3:1 -> alice 75, bob 25
	cross(RecordIncome)(cur, id, 100)

	out := Render("")
	uassert.True(t, strings.Contains(out, "Group #0"), "render shows group")
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

	id := cross(Register)(cur, a+","+b+","+c, "1,1,1")
	cross(RecordIncome)(cur, id, 100) // 100/3 = 33 each, remainder 1

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
	uassert.AbortsWithMessage(t, "splitter: payees and shares count mismatch", func() {
		cross(Register)(cur, a, "1,2")
	})

	// non-positive share aborts
	uassert.AbortsWithMessage(t, "splitter: share must be positive", func() {
		cross(Register)(cur, a, "0")
	})
}
