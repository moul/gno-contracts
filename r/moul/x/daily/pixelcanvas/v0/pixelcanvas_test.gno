package pixelcanvas

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// reset clears realm state between tests.
func reset() {
	for i := range cells {
		cells[i] = 0
		painters[i] = ""
	}
	tally = avl.NewTree()
	strokes = 0
	lastAt = 0
}

// paint runs a Paint as addr.
func paint(cur realm, addr address, x, y int, colour string) int {
	testing.SetRealm(testing.NewUserRealm(addr))
	return Paint(cross(cur), x, y, colour)
}

func TestPaintSetsCellAndPainter(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")

	uassert.Equal(t, 1, paint(cur, alice, 3, 7, "red"))
	uassert.Equal(t, "red", At(3, 7))
	uassert.Equal(t, alice.String(), PainterAt(3, 7))
	uassert.Equal(t, 1, Strokes())
}

// (x, y) is column, row — a paint at (3,7) must not land at (7,3).
func TestCoordinatesAreXThenY(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	paint(cur, alice, 3, 7, "blue")

	uassert.Equal(t, "blue", At(3, 7))
	uassert.Equal(t, "white", At(7, 3))
}

func TestLastWriteWins(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	paint(cur, alice, 0, 0, "red")
	paint(cur, bob, 0, 0, "green")

	uassert.Equal(t, "green", At(0, 0))
	uassert.Equal(t, bob.String(), PainterAt(0, 0))
	uassert.Equal(t, 2, Strokes()) // both strokes still counted
}

func TestOutOfBoundsPanics(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	cases := [][2]int{{-1, 0}, {0, -1}, {Size, 0}, {0, Size}}
	for _, c := range cases {
		testing.SetRealm(testing.NewUserRealm(alice))
		rec := revive(func() { Paint(cross(cur), c[0], c[1], "red") })
		uassert.True(t, rec != nil)
	}
	uassert.Equal(t, 0, Strokes())
}

func TestUnknownColourPanics(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	rec := revive(func() { Paint(cross(cur), 1, 1, "chartreuse") })
	uassert.True(t, rec != nil)
	uassert.Equal(t, 0, Strokes())
}

// Colour names are case- and space-insensitive.
func TestColourNameIsNormalised(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	paint(cur, alice, 2, 2, "  GREEN ")
	uassert.Equal(t, "green", At(2, 2))
}

func TestAtOutOfBoundsIsEmpty(t *testing.T) {
	reset()
	uassert.Equal(t, "", At(-1, 0))
	uassert.Equal(t, "", At(Size, 0))
	uassert.Equal(t, "", PainterAt(0, Size))
}

func TestUnpaintedCellIsWhiteWithNoPainter(t *testing.T) {
	reset()
	uassert.Equal(t, "white", At(5, 5))
	uassert.Equal(t, "", PainterAt(5, 5))
}

func TestTallyRanksPainters(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")
	// alice paints 3, bob 1
	paint(cur, alice, 0, 0, "red")
	paint(cur, alice, 1, 0, "red")
	paint(cur, alice, 2, 0, "red")
	paint(cur, bob, 3, 0, "blue")

	out := Render("")
	ai := strings.Index(out, alice.String())
	bi := strings.Index(out, bob.String())
	uassert.True(t, ai >= 0)
	uassert.True(t, bi >= 0)
	uassert.True(t, ai < bi) // alice ranks first
}

func TestRenderEmptyCanvas(t *testing.T) {
	reset()
	out := Render("")
	uassert.True(t, strings.Contains(out, "**0** strokes"))
	// a blank canvas is Size rows of Size white blocks
	uassert.Equal(t, Size*Size, strings.Count(out, "⬜"))
	uassert.False(t, strings.Contains(out, "Top painters"))
}

func TestRenderCellLookup(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	paint(cur, alice, 4, 9, "purple")

	out := Render("/4,9")
	uassert.True(t, strings.Contains(out, "Cell (4, 9)"))
	uassert.True(t, strings.Contains(out, "**purple**"))
	uassert.True(t, strings.Contains(out, alice.String()))
}

func TestRenderCellNeverPainted(t *testing.T) {
	reset()
	out := Render("/1,1")
	uassert.True(t, strings.Contains(out, "Never painted"))
}

func TestRenderRejectsBadCoord(t *testing.T) {
	reset()
	for _, q := range []string{"/nope", "/1", "/99,99", "/a,b"} {
		uassert.True(t, strings.Contains(Render(q), "Expected `x,y`"))
	}
}
