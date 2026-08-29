package asciiart

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	gallery = avl.Tree{}
	nextID = 0
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

func TestPadID(t *testing.T) {
	if padID(1) != "000001" {
		t.Fatalf("padID(1) = %q, want 000001", padID(1))
	}
	if padID(42) != "000042" {
		t.Fatalf("padID(42) = %q, want 000042", padID(42))
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
	if nextID != 1 {
		t.Fatalf("nextID = %d, want 1", nextID)
	}

	v, ok := gallery.Get(padID(1))
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
