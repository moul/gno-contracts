package calc

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestPushAndAdd(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	Clear(cross(cur))
	Push(cross(cur), "5")
	Push(cross(cur), "3")
	Push(cross(cur), "+")

	uassert.Equal(t, 1, Depth())
	top, ok := Top()
	uassert.True(t, ok)
	uassert.Equal(t, 8, top)
}

func TestChainedOps(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("bob")))

	Clear(cross(cur))
	// (10 - 4) * 2 = 12
	Push(cross(cur), "10")
	Push(cross(cur), "4")
	Push(cross(cur), "-")
	Push(cross(cur), "2")
	Push(cross(cur), "*")

	top, ok := Top()
	uassert.True(t, ok)
	uassert.Equal(t, 12, top)
	uassert.Equal(t, 1, Depth())
}

func TestDivision(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("carol")))

	Clear(cross(cur))
	Push(cross(cur), "20")
	Push(cross(cur), "6")
	Push(cross(cur), "/")

	top, _ := Top()
	uassert.Equal(t, 3, top) // integer division
}

func TestDivideByZeroAborts(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("dave")))

	Clear(cross(cur))
	Push(cross(cur), "1")
	Push(cross(cur), "0")

	uassert.AbortsWithMessage(t, ErrDivByZero.Error(), func() {
		Push(cross(cur), "/")
	})
}

func TestUnderflowAborts(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("erin")))

	Clear(cross(cur))
	Push(cross(cur), "42")

	uassert.AbortsWithMessage(t, ErrUnderflow.Error(), func() {
		Push(cross(cur), "+")
	})
}

func TestClearEmpties(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("frank")))

	Push(cross(cur), "7")
	Push(cross(cur), "9")
	Clear(cross(cur))

	uassert.Equal(t, 0, Depth())
	_, ok := Top()
	uassert.False(t, ok)
}
