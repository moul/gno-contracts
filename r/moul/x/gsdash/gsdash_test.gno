package gsdash

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"

	// GnoSwap's unversioned paths are proxies: the facade holds no logic and
	// panics with "implementation is not initialized" until some version has
	// registered itself. On chain that happened long ago; in a test VM nothing
	// has, so these blank imports run each implementation's init, which calls
	// RegisterInitializer, and the version manager activates the first one it
	// sees. Importing them here rather than from the realm keeps them out of
	// what gets deployed: the realm only ever names the proxy.
	_ "gno.land/r/gnoswap/pool/v1"
	_ "gno.land/r/gnoswap/position/v1"
	_ "gno.land/r/gnoswap/staker/v1"
)

// someone is a well-formed address with nothing on GnoSwap, which is what every
// address looks like in a fresh test VM.
const someone = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"

func TestRenderIndexReadsTheProxies(t *testing.T) {
	out := Render("")
	uassert.True(t, len(out) > 0, "index renders")
	uassert.True(t, strings.Contains(out, "# GnoSwap dashboard"), "index has its heading")
	// Reaching this line at all is the point: Size() and TotalSupply() are
	// cross-realm reads through two different GnoSwap proxies, so an index that
	// renders proves both resolved to a live implementation.
	uassert.True(t, strings.Contains(out, "Stored position records"), "index read the position proxy")
	uassert.True(t, strings.Contains(out, "Position NFTs in circulation"), "index read the gnft realm")
}

func TestRenderAddressWithNothing(t *testing.T) {
	out := Render(someone)
	uassert.True(t, strings.Contains(out, someone), "the page names the address in full")
	uassert.True(t, strings.Contains(out, "No positions in this window."), "an empty window says so")
}

func TestRenderRejectsAMalformedAddress(t *testing.T) {
	out := Render("not-an-address")
	uassert.True(t, strings.Contains(out, "Not a valid address"), "a bad address is refused")
	uassert.False(t, strings.Contains(out, "## Positions"), "and no scan is run for it")
}

func TestRenderEscapesWhatTheReaderTyped(t *testing.T) {
	// The path is attacker-controlled: whatever is after the colon in the URL.
	// It must come back inert, never as a live link.
	out := Render("[click](https://evil.example)")
	uassert.False(t, strings.Contains(out, "](https://evil.example)"), "no live link survives")
}

func TestParsePath(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		wantAddr   string
		wantOffset int
		wantOK     bool
	}{
		{"bare address", someone, someone, 0, true},
		{"with offset", someone + "/from/250", someone, 250, true},
		{"zero offset", someone + "/from/0", someone, 0, true},
		{"unknown segment", someone + "/nope", "", 0, false},
		{"offset not a number", someone + "/from/abc", "", 0, false},
		{"negative offset", someone + "/from/-1", "", 0, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			addr, offset, ok := parsePath(tt.path)
			uassert.Equal(t, tt.wantOK, ok)
			if !tt.wantOK {
				return
			}
			uassert.Equal(t, tt.wantAddr, addr)
			uassert.Equal(t, tt.wantOffset, offset)
		})
	}
}

func TestShortPool(t *testing.T) {
	tests := []struct {
		name string
		key  string
		want string
	}{
		{
			"a real pool key",
			"gno.land/r/gnoland/wugnot.wugnot:gno.land/r/gnoswap/gns.GNS:3000",
			"wugnot/GNS 3000",
		},
		{"not a pool key", "whatever", "whatever"},
		{"no symbol on a side", "a:b:100", "a/b 100"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			uassert.Equal(t, tt.want, shortPool(tt.key))
		})
	}
}

// ExampleRender pins the index as a fresh chain renders it: no positions, no
// NFTs, and the two proxy reads resolving to zero rather than panicking.
func ExampleRender() {
	println(Render(""))
	// Output:
	// # GnoSwap dashboard
	//
	// Everything one address has on GnoSwap, read live from the chain: GNS and xGNS balances, every liquidity position with what it holds right now, the fees it has accrued, and the emission rewards waiting to be collected.
	//
	// Open an address: `/r/moul/x/gsdash/v0:g1...`
	//
	// | What | Now |
	// | --- | --- |
	// | Stored position records | 0 |
	// | Position NFTs in circulation | 0 |
	// | Records walked per page | 250 |
	//
	// Records include burned positions, so the count is not a count of live liquidity.
}

// The offset comes from the path, so maxInt is free to ask for, and
// offset+scanWindow used to wrap negative into "Records N to -M".
func TestRenderClampsAnOverflowingOffset(t *testing.T) {
	out := Render(someone + "/from/9223372036854775807")
	uassert.False(t, strings.Contains(out, " to -"), out)
	uassert.False(t, strings.Contains(out, "9223372036854775807"), "the offset is clamped to what exists")
}
