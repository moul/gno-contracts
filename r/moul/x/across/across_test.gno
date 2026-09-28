package across

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"

	"gno.land/r/moul/x/daily/erc20/v0"
	"gno.land/r/moul/x/daily/streak/v0"
	"gno.land/r/moul/x/pairs/aaa/v0"
	"gno.land/r/moul/x/pairs/bbb/v0"
)

// seeded is the address the mutation tests build state for. Everything after
// TestReportReadsCrossRealmState sees whatever they left in the imported
// realms, which is the whole point of the demo but also makes test order load
// bearing: nothing below may assume a clean source realm for this address.
var seeded = testutils.TestAddress("across-seeded")

// fresh is never written to by anything here, so every source answers it with
// its zero value. ExampleRender pins that page.
var fresh = testutils.TestAddress("across-fresh")

func TestSourceCount(t *testing.T) {
	// The package doc and the rendered prose both say fifteen. If this fails,
	// one of them is now a lie.
	uassert.Equal(t, 15, Sources())
}

// Report must never name a realm that sourceRealms does not list, or the index
// table silently stops covering what the report reads.
func TestSourcesCoverReport(t *testing.T) {
	known := map[string]bool{}
	for _, s := range sourceRealms {
		known[s] = true
	}
	for _, f := range Report(fresh) {
		uassert.True(t, known[f.source], "report names an unlisted source: "+f.source)
	}
}

// Every source answers, and no source panics. The count is asserted rather
// than the values, so this stays true as the sources gain state.
func TestReportAnswersFromEverySource(t *testing.T) {
	facts := Report(fresh)
	uassert.Equal(t, 18, len(facts))

	seen := map[string]bool{}
	for _, f := range facts {
		seen[f.source] = true
	}
	// amm is the one listed source that contributes to the index only.
	uassert.Equal(t, 14, len(seen))
	uassert.False(t, seen["r/moul/x/amm/v0"], "amm must not be read per address")
}

// The load-bearing test: write to four realms that know nothing about this one,
// then read all four back through Report. Break any of the four reads and this
// goes red.
func TestReportReadsCrossRealmState(cur realm, t *testing.T) {
	// SetRealm governs only the crossing calls made from this frame, so the
	// switch has to stay inline with the calls it is meant to cover.
	testing.SetRealm(testing.NewUserRealm(seeded))
	erc20.Mint(cross(cur), seeded, 4_200)
	aaa.Faucet(cross(cur))
	bbb.Faucet(cross(cur))
	days := streak.CheckIn(cross(cur))
	uassert.Equal(t, 1, days, "first check-in is day 1")

	got := map[string]string{}
	for _, f := range Report(seeded) {
		if f.zero {
			continue
		}
		got[f.source+" "+f.what] = f.value
	}

	uassert.Equal(t, "4200 "+erc20.Symbol(), got["r/moul/x/daily/erc20/v0 balance"])
	uassert.Equal(t, "1 day(s)", got["r/moul/x/daily/streak/v0 current streak"])
	uassert.Equal(t, "1 day(s)", got["r/moul/x/daily/streak/v0 best streak"])
	uassert.True(t, got["r/moul/x/pairs/aaa/v0 balance"] != "", "aaa faucet must show up")
	uassert.True(t, got["r/moul/x/pairs/bbb/v0 balance"] != "", "bbb faucet must show up")
}

// The rendered page for the seeded address must carry the same four facts, and
// must hide the reads that came back empty rather than printing a wall of zeros.
func TestRenderAddressShowsOnlyLiveFacts(t *testing.T) {
	out := Render(seeded.String())

	uassert.True(t, strings.Contains(out, "4200 "+erc20.Symbol()), "erc20 balance on the page")
	uassert.True(t, strings.Contains(out, "current streak"), "streak on the page")
	uassert.True(t, strings.Contains(out, "r/moul/x/pairs/aaa/v0"), "aaa on the page")
	uassert.True(t, strings.Contains(out, "reads came back empty and are hidden"), "quiet rows hidden")
	uassert.False(t, strings.Contains(out, "vesting grant"), "an empty grant must not render")
}

// An address-shaped path that is not an address must not reach a source realm.
func TestRenderRejectsNonAddress(t *testing.T) {
	out := Render("not-an-address")
	uassert.True(t, strings.Contains(out, "is not a valid address"), "explicit refusal")
	uassert.False(t, strings.Contains(out, "## Answers"), "no report for a bad path")
}

// The index reads a global from every source. Pinned by Contains rather than by
// an example, because most of those globals move with chain state.
func TestRenderIndexReadsEverySource(t *testing.T) {
	out := Render("")
	for _, s := range sourceRealms {
		uassert.True(t, strings.Contains(out, s), "index must list "+s)
	}
	uassert.True(t, strings.Contains(out, "pool(s), index only"), "amm is flagged index-only")
	uassert.True(t, strings.Contains(out, "roll(s) all time"), "dice global is read")
	uassert.True(t, strings.Contains(out, "page(s) reacted to"), "reactions global is read")
}

// ExampleRender pins the report for an address no test writes to. Every value
// in it comes from a source realm's zero state, except the rate limiter, which
// answers a full bucket for an address it has never seen: absence and a fresh
// allowance are the same thing there, and the report says so rather than
// pretending the read was empty.
func ExampleRender() {
	print(Render(fresh.String()))
	// Output:
	// # across: `g1v93hymmnwvkkvun9wd597h6lta047h6l220muq`
	//
	// What 15 independently deployed realms say about this address. None of them was changed to answer.
	//
	// ## Answers
	//
	// | source | fact | value |
	// | --- | --- | --- |
	// | [`r/moul/x/daily/ratelimitdemo/v0`](/r/moul/x/daily/ratelimitdemo/v0) | rate-limit tokens left | 5 |
	//
	// 17 of 18 reads came back empty and are hidden.
	//
	// [back to the index](/r/moul/x/across/v0)
}
