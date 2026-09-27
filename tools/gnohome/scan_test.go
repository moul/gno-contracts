package main

import "testing"

// The expected strings are the ones p/moul/mygnoscan produces, and all three
// live shapes were confirmed to answer 200 on the real instance on 2026-09-28.
// If this file and r/moul/home/scan.gno ever disagree, the realm is right and
// this mirror is the bug: preview is the approximation, the chain is not.
func TestScanPlaceholders(t *testing.T) {
	const (
		realm = "gno.land/r/moul/home"
		owner = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
		base  = "https://mygnoscan.moul.p2p.team"
	)

	for _, tc := range []struct {
		name string
		got  string
		want string
	}{
		{"realm on mainnet", scanRealm("gnoland-1", realm), base + "/realm/r/moul/home?network=mainnet"},
		{"realm strips the domain", scanRealm("gnoland-1", "gno.land/r/moul/blog"), base + "/realm/r/moul/blog?network=mainnet"},
		{"address", scanAddress("gnoland-1", owner), base + "/address/" + owner + "?network=mainnet"},
		{"block", scanBlock("gnoland-1", 281000), base + "/block/281000?network=mainnet"},

		// A chain the instance does not index emits no network, rather than
		// guessing one: that is NetworkFor's contract and gnodev hits it on
		// every preview.
		{"unknown chain drops the network", scanRealm("dev", realm), base + "/realm/r/moul/home"},

		// Degenerate inputs fall back to a list page rather than building a
		// link to nothing. Height 0 is what preview passes with no chain.
		{"height zero lists blocks", scanBlock("gnoland-1", 0), base + "/blocks?network=mainnet"},
		{"empty address lists accounts", scanAddress("gnoland-1", ""), base + "/accounts?network=mainnet"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if tc.got != tc.want {
				t.Errorf("got  %s\nwant %s", tc.got, tc.want)
			}
		})
	}
}

// escapeSegment is encodeURIComponent, not url.PathEscape. No bech32 address
// exercises the difference, which is exactly why it is pinned here: the next
// caller may not pass an address.
func TestEscapeSegmentIsEncodeURIComponent(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"g1manfred47kzduec920z88wfr64ylksmdcedlf5", "g1manfred47kzduec920z88wfr64ylksmdcedlf5"},
		{"a-b_c.d~e", "a-b_c.d~e"},
		{"a+b/c=d", "a%2Bb%2Fc%3Dd"},
		{"a:b$c&d,e", "a%3Ab%24c%26d%2Ce"},
	} {
		if got := escapeSegment(tc.in); got != tc.want {
			t.Errorf("escapeSegment(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// The layout shipped in content/ must only reference placeholders render can
// actually fill, or the page shows a literal ":slug:" to every visitor.
func TestShippedLayoutHasNoUnresolvedPlaceholder(t *testing.T) {
	slots, err := loadSlots("../../r/moul/home/content")
	if err != nil {
		t.Fatalf("loading slots: %v", err)
	}
	out := render(slots, env{
		owner:   "g1manfred47kzduec920z88wfr64ylksmdcedlf5",
		realm:   "gno.land/r/moul/home",
		chainID: "gnoland-1",
		height:  281000,
		rev:     9,
	})
	for _, bad := range []string{":scan", ":bio:", ":now:", ":layout:", ":previously:"} {
		if contains(out, bad) {
			t.Errorf("rendered page still contains %q", bad)
		}
	}
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
