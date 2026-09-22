package home

import (
	"testing"

	"gno.land/p/moul/mygnoscan/v0"
	"gno.land/p/nt/uassert/v0"
)

// TestScanPlaceholdersAreReserved is the one that actually protects the
// design: every placeholder scan.gno answers for must also be refused as a
// slot name, or a slot could take the name and the page would depend on which
// callback dynreplacer registered last.
func TestScanPlaceholdersAreReserved(t *testing.T) {
	for _, p := range scanPlaceholders {
		found := false
		for _, r := range reservedSlugs {
			if r == p {
				found = true
				break
			}
		}
		uassert.True(t, found, "scan placeholder not reserved: "+p)
	}
}

func TestScanSlugsAreWritableShapes(t *testing.T) {
	// A reserved slug still has to be a legal slug, or reserving it is a
	// no-op: an illegal name is refused for a different reason and the
	// reservation never gets exercised.
	for _, p := range scanPlaceholders {
		uassert.True(t, validSlug(p), "scan placeholder is not a valid slug: "+p)
	}
}

func TestSetRefusesScanSlugs(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))
	uassert.AbortsWithMessage(t, cur, "reserved slug: scan.realm is computed at render time", func() {
		Set(cross(cur), "scan.realm", "anything")
	})
}

// TestScanLinksFollowConfig is the end-to-end claim of this whole change: what
// the page renders follows gno.land/r/moul/config, so pointing moul's realms
// at a different explorer is a transaction and not a redeploy.
//
// It cannot set the config from here (that needs config's own authority and a
// crossing call into another realm), so it asserts the default path: unset
// config means mygnoscan.DefaultBase, in the page, for real.
func TestScanLinksFollowConfig(t *testing.T) {
	reset()
	seed("layout", ":scan.realm:")

	uassert.Equal(t,
		"[mygnoscan]("+mygnoscan.DefaultBase+"/realm/r/moul/home)",
		Render(""),
		"with nothing configured the page falls back to the package default")
}

// ExampleRender_scan pins the explorer footer as a layout would use it. The
// block link is deliberately absent: it moves with the chain, and an example
// that pins it would fail on whichever test ran SkipHeights before it.
func ExampleRender_scan() {
	reset()
	seed("layout", "# :owner:\n\n---\n\n:scan.realm: · :scan.me:\n")
	print(Render(""))
	// Output:
	// # g1manfred47kzduec920z88wfr64ylksmdcedlf5
	//
	// ---
	//
	// [mygnoscan](https://mygnoscan.moul.p2p.team/realm/r/moul/home) · [my account](https://mygnoscan.moul.p2p.team/address/g1manfred47kzduec920z88wfr64ylksmdcedlf5)
}

// ExampleRender_scanBase pins the raw base URL placeholder, which is what a
// slot uses to build a link this realm has no helper for.
func ExampleRender_scanBase() {
	reset()
	seed("layout", ":scan:\n")
	print(Render(""))
	// Output:
	// https://mygnoscan.moul.p2p.team
}
