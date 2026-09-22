package asciiart

import (
	"strings"
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	gallery = store.Named("piece")
}

func TestRenderDiamond(t *testing.T) {
	got := RenderDiamond(3)
	want := "  *\n ***\n*****\n ***\n  *"
	if got != want {
		t.Fatalf("RenderDiamond(3) =\n%s\nwant\n%s", got, want)
	}
}

func TestRenderPyramid(t *testing.T) {
	got := RenderPyramid(3)
	want := "  *\n ***\n*****"
	if got != want {
		t.Fatalf("RenderPyramid(3) =\n%s\nwant\n%s", got, want)
	}
}

func TestRenderSierpinski(t *testing.T) {
	got := RenderSierpinski(4)
	want := "####\n# # \n##  \n#   "
	if got != want {
		t.Fatalf("RenderSierpinski(4) =\n%s\nwant\n%s", got, want)
	}
}

func TestRenderSierpinskiRejectsNonPowerOfTwo(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for a non-power-of-two size")
		}
	}()
	RenderSierpinski(5)
}

func TestRenderChecker(t *testing.T) {
	got := RenderChecker(3)
	want := "#.#\n.#.\n#.#"
	if got != want {
		t.Fatalf("RenderChecker(3) =\n%s\nwant\n%s", got, want)
	}
}

func TestRenderPatternUnknown(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for an unknown pattern")
		}
	}()
	renderPattern("spiral", 3)
}

// v1 asserted that its own padID() padded to width 6. That is the narrowest
// ceiling in this repo: padID(10^6) is 7 characters and sorts before
// padID(10^6-1), so from the millionth piece on the gallery would have
// rendered out of order. The store key is 8 bytes for every id.
func TestPadID(t *testing.T) {
	if a, b := store.ID(2).Key(), store.ID(10).Key(); !(a < b) {
		t.Error("id 2 should sort before id 10")
	}
	if a, b := store.ID(999999).Key(), store.ID(1000000).Key(); !(a < b) {
		t.Error("ordering should survive one past v1's width-6 ceiling")
	}
}

// Crossing: Generate mutates realm state, so the test needs `cur realm`.
func TestGenerateAddsToGallery(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	art := Generate(cross(cur), "checker", 3)
	if art != RenderChecker(3) {
		t.Fatal("Generate should return the rendered art")
	}
	if gallery.LastID() != 1 {
		t.Fatalf("LastID = %s, want 1", gallery.LastID())
	}

	// The store's Get returns (value, ok), so a stored nil is distinguishable
	// from an absent id, which avl/v0's single-value Get cannot express.
	v, ok := gallery.Get(1)
	if !ok {
		t.Fatal("expected piece #1 to exist in the gallery")
	}
	p := v.(*piece)
	if p.Pattern != "checker" || p.Size != 3 || p.Author != alice {
		t.Fatalf("unexpected piece: %+v", p)
	}
}

func TestGenerateRejectsOutOfRangeSize(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	rec := revive(func() { Generate(cross(cur), "diamond", 0) })
	if rec == nil {
		t.Fatal("expected panic for size < 1")
	}
	rec = revive(func() { Generate(cross(cur), "diamond", maxSize+1) })
	if rec == nil {
		t.Fatal("expected panic for size > maxSize")
	}
}

// Non-crossing: Render is a plain read.
func TestRenderHomeEmptyGallery(t *testing.T) {
	resetState()
	out := Render("")
	if !strings.Contains(out, "nothing generated yet") {
		t.Fatal(`Render("") on an empty gallery should say so`)
	}
}

func TestRenderPieceNotFound(t *testing.T) {
	resetState()
	out := Render("99")
	if !strings.Contains(out, "No such piece") {
		t.Fatal(`Render("99") on a missing piece should say so`)
	}
}
