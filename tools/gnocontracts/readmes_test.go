package main

import (
	"strings"
	"testing"
)

// The footer is the only part of a package README the tooling owns, so it is
// the only place a badge row can live and still be maintained rather than
// copied. These assert what ends up inside the managed markers.
func TestPkgBadges(t *testing.T) {
	tests := []struct {
		name string
		c    Contract
		want []string
		none bool
	}{
		{
			name: "a realm gets the four measures and a link to its page",
			c:    Contract{PkgPath: "gno.land/r/moul/home", Dir: "r/moul/home", Kind: "r"},
			want: []string{
				"https://gnoscope.com/_badges/shield/status/r/moul/home?network=mainnet",
				"https://gnoscope.com/_badges/shield/txs/r/moul/home?network=mainnet",
				"https://gnoscope.com/_badges/shield/users/r/moul/home?network=mainnet",
				"https://gnoscope.com/_badges/shield/version/r/moul/home?network=mainnet",
				"](https://gnoscope.com/realm/r/moul/home)",
			},
		},
		{
			name: "a versioned path keeps its version segment",
			c:    Contract{PkgPath: "gno.land/r/moul/faucet/v1", Dir: "r/moul/faucet/v1", Kind: "r"},
			want: []string{"/_badges/shield/status/r/moul/faucet/v1?", "/realm/r/moul/faucet/v1)"},
		},
		{
			// A pure package is imported, never called, so every count is zero
			// by construction and a row of grey zeroes would read as data.
			name: "a pure package gets none",
			c:    Contract{PkgPath: "gno.land/p/moul/svg/v0", Dir: "p/moul/svg/v0", Kind: "p"},
			none: true,
		},
		{
			name: "an archived version gets none",
			c:    Contract{PkgPath: "gno.land/r/moul/old/v0", Dir: "r/moul/old/v0", Kind: "r", Ignored: true},
			none: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := pkgBadges(tt.c)
			if tt.none {
				if got != "" {
					t.Fatalf("want no badges, got:\n%s", got)
				}
				return
			}
			for _, w := range tt.want {
				if !strings.Contains(got, w) {
					t.Errorf("missing %q in:\n%s", w, got)
				}
			}
			// gno.land/ is the explorer's own prefix and passing it through
			// would ask for gno.land/gno.land/r/….
			if strings.Contains(got, "shield/status/gno.land/") {
				t.Errorf("the path kept its gno.land/ prefix:\n%s", got)
			}
		})
	}
}

// The badges have to be inside the managed block, or the next `make readmes`
// leaves a stale copy above it and the README says two things.
func TestPkgFooterCarriesTheBadges(t *testing.T) {
	c := Contract{PkgPath: "gno.land/r/moul/home", Dir: "r/moul/home", Kind: "r"}
	f := pkgFooter(c)

	begin := strings.Index(f, pkgFooterBegin)
	end := strings.Index(f, pkgFooterEnd)
	at := strings.Index(f, "**On mainnet:**")
	if at < 0 {
		t.Fatalf("no badge row in the footer:\n%s", f)
	}
	if !(begin < at && at < end) {
		t.Errorf("badge row at %d is outside the managed block (%d..%d)", at, begin, end)
	}

	// And a pure package's footer is unchanged by all of this.
	if strings.Contains(pkgFooter(Contract{PkgPath: "gno.land/p/moul/svg/v0", Dir: "p/moul/svg/v0", Kind: "p"}), "On mainnet") {
		t.Error("a pure package footer grew a badge row")
	}
}
