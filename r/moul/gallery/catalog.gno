package gallery

import (
	"gno.land/r/moul/demo/gnoface/v0"
	"gno.land/r/moul/demo/millipede/v0"
	"gno.land/r/moul/sapin/v0"
)

// piece is one entry in the index.
//
// The gallery stores no art. Every piece lives in somebody's realm and this is
// a pointer to it, which is why there is no package-level state anywhere in
// this realm and nothing here survives or needs to survive a redeploy.
type piece struct {
	Slug    string
	Title   string
	Author  string
	Origin  string // realm path, without the gno.land prefix
	License string
	Note    string

	// Draw renders the piece live, by importing its source. It is nil when the
	// source cannot be imported, which is the honest half of a curated index:
	// a private realm or a package this repo has not vendored can be pointed
	// at but not shown.
	Draw func() string
}

// Live reports whether this realm can render the piece itself.
func (p piece) Live() bool { return p.Draw != nil }

// catalog is built per call rather than held in a package-level var: a func
// value is not something to persist, and a realm that stores nothing should
// not be paying storage for its own index.
func catalog() []piece {
	return []piece{
		{
			Slug:    "gnoface",
			Title:   "gnoface",
			Author:  "moul",
			Origin:  "r/moul/demo/gnoface/v0",
			License: "see the source realm",
			Note:    "A face generated from a seed. Every seed is a different face, and none of them are stored.",
			Draw:    func() string { return gnoface.Draw(42) },
		},
		{
			Slug:    "millipede",
			Title:   "millipede",
			Author:  "moul",
			Origin:  "r/moul/demo/millipede/v0",
			License: "see the source realm",
			Note:    "A millipede of any length. The oldest piece here, and still the one that best explains why ASCII is the cheapest picture there is.",
			Draw:    func() string { return millipede.Draw(8) },
		},
		{
			Slug:    "sapin",
			Title:   "sapin",
			Author:  "moul",
			Origin:  "r/moul/sapin/v0",
			License: "see the source realm",
			Note:    "A fir tree, sized on request.",
			Draw:    func() string { return sapin.Sapin(6) },
		},
		{
			Slug:    "settler25",
			Title:   "Settler #25",
			Author:  "the Settlers",
			Origin:  "r/g17khqpukees4237dtn3astzapmp462vjhsz6st4/settlers/nft",
			License: "CC0 1.0",
			Note:    "moul's, soulbound, minted at block 409242. A 32x32 indexed sprite with 20 colours, which is what made it the test case for p/moul/art: a luminance ramp resolves those 20 to 9, and keying on the palette index keeps all 20.",
		},
		{
			Slug:    "asciiart",
			Title:   "asciiart",
			Author:  "moul",
			Origin:  "r/moul/x/daily/asciiart/v1",
			License: "see the source realm",
			Note:    "Patterns from short deterministic algorithms, plus everyone's generations. Declared private = true, so it can be linked but never imported: that is the constraint, not an omission.",
		},
		{
			Slug:    "pixelcanvas",
			Title:   "pixelcanvas",
			Author:  "moul",
			Origin:  "r/moul/x/daily/pixelcanvas/v0",
			License: "see the source realm",
			Note:    "A shared grid anyone can paint one pixel of.",
		},
	}
}

func find(slug string) (piece, bool) {
	for _, p := range catalog() {
		if p.Slug == slug {
			return p, true
		}
	}
	return piece{}, false
}
