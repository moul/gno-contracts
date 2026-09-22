package mygnoscan

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// mainnet is what a Scanner looks like on the chain that matters. Tests build
// it explicitly rather than calling Default(), because the test harness runs
// with chain-id "dev", which NetworkFor maps to no network at all: pinning
// Default()'s output would pin the absence of the parameter and prove nothing
// about the case every real link is in.
func mainnet() Scanner { return New(DefaultBase).WithNetwork("mainnet") }

func TestNetworkFor(t *testing.T) {
	tests := []struct {
		chainID string
		want    string
	}{
		{"gnoland-1", "mainnet"},
		{"pearl-1", "pearl"},
		{"sapphire-1", "sapphire"},
		{"staging", "staging"},
		{"dev", ""},          // gnodev, and what `gno test` reports
		{"", ""},             // no chain at all
		{"gnoland1", ""},     // the upstream default instance's id, not a chain-id
		{"test3", ""},        // a retired testnet
		{"mainnet", ""},      // the network id, fed back in by mistake
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, NetworkFor(tt.chainID), "NetworkFor("+tt.chainID+")")
	}
}

func TestTrimDomain(t *testing.T) {
	tests := []struct {
		in   string
		want string
	}{
		{"gno.land/r/moul/home", "r/moul/home"},
		{"r/moul/home", "r/moul/home"},
		{"/r/moul/home", "r/moul/home"},
		{"gno.land/p/moul/mygnoscan/v0", "p/moul/mygnoscan/v0"},
		{"gno.land/r/gnoland/blog", "r/gnoland/blog"},
		{"", ""},
		{"gno.land/", ""},
		// A path whose own name starts with the domain is only trimmed once,
		// so a realm cannot be linked out of its own namespace by its name.
		{"gno.land/r/moul/gno.land", "r/moul/gno.land"},
		// Anything not shaped like a package path comes back empty, so the
		// caller falls back to a list page instead of emitting it.
		{"r/moul/home)", ""},
		{"r/moul/ho me", ""},
		{"r/moul//home", ""},
		{"r/moul/home\n", ""},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, TrimDomain(tt.in), "TrimDomain("+tt.in+")")
	}
}

func TestBaseNormalisation(t *testing.T) {
	uassert.Equal(t, DefaultBase, New(DefaultBase+"/").Base())
	uassert.Equal(t, DefaultBase, New(DefaultBase).Base())
	uassert.Equal(t, "https://scan.example.com", New("https://scan.example.com/").Base())
}

func TestTargets(t *testing.T) {
	s := mainnet()
	const b = DefaultBase
	tests := []struct {
		name string
		got  string
		want string
	}{
		{"home", s.Home(), b + "/?network=mainnet"},
		{"page", s.Page(PageTxs), b + "/txs?network=mainnet"},
		{"page nested", s.Page(PageGasRealms), b + "/gas/realms?network=mainnet"},
		{"page slashed", s.Page("/blocks/"), b + "/blocks?network=mainnet"},
		{"realm qualified", s.Realm("gno.land/r/moul/home"), b + "/realm/r/moul/home?network=mainnet"},
		{"realm bare", s.Realm("r/moul/home"), b + "/realm/r/moul/home?network=mainnet"},
		{"realm tab", s.Realm("r/moul/home", TabSource), b + "/realm/r/moul/home?network=mainnet&tab=source"},
		// TabInfo is the tab the explorer lands on, so asking for it adds nothing.
		{"realm tab info", s.Realm("r/moul/home", TabInfo), b + "/realm/r/moul/home?network=mainnet"},
		{"realm empty", s.Realm(""), b + "/?network=mainnet"},
		{"realm func", s.RealmFunc("r/moul/config", "Set"), b + "/realm/r/moul/config?fn=Set&network=mainnet&tab=source"},
		{"realm file", s.RealmFile("r/moul/home", "render.gno", 42), b + "/realm/r/moul/home?file=render.gno&line=42&network=mainnet&tab=source"},
		{"realm file no line", s.RealmFile("r/moul/home", "render.gno", 0), b + "/realm/r/moul/home?file=render.gno&network=mainnet&tab=source"},
		{"address", s.Address("g1manfred47kzduec920z88wfr64ylksmdcedlf5"), b + "/address/g1manfred47kzduec920z88wfr64ylksmdcedlf5?network=mainnet"},
		{"address empty", s.Address(""), b + "/accounts?network=mainnet"},
		{"block", s.Block(80618), b + "/block/80618?network=mainnet"},
		{"block zero", s.Block(0), b + "/blocks?network=mainnet"},
		{"validator", s.Validator("g1manfred47kzduec920z88wfr64ylksmdcedlf5"), b + "/validator/g1manfred47kzduec920z88wfr64ylksmdcedlf5?network=mainnet"},
		{"proposal", s.Proposal(7), b + "/govdao/7?network=mainnet"},
		{"proposal negative", s.Proposal(-1), b + "/govdao/proposals?network=mainnet"},
		{"token empty", s.Token(""), b + "/grc20?network=mainnet"},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, tt.got, tt.name)
	}
}

// TestEscaping covers the two routes whose argument is not URL-safe. Both are
// read back with decodeURIComponent by the explorer, so percent-escaping the
// whole segment is what round-trips; leaving the slashes alone would split the
// segment and land on a different route entirely.
func TestEscaping(t *testing.T) {
	s := mainnet()

	// A 32-byte hash in the base64 form the indexer and gnokey print, picked
	// to carry all three of the characters that make base64 awkward in a URL.
	// Everything outside the unreserved set moves, which is what the
	// explorer's decodeURIComponent undoes byte for byte.
	uassert.Equal(t,
		DefaultBase+"/tx/BppSxd7qRiAPsMHzDx5mys%2BYpeDCMUzxI1qeb%2FEhaYc%3D?network=mainnet",
		s.Tx("BppSxd7qRiAPsMHzDx5mys+YpeDCMUzxI1qeb/EhaYc="))
	uassert.Equal(t, DefaultBase+"/txs?network=mainnet", s.Tx(""))

	// A GRC20 ledger key carries both slashes and dots.
	uassert.Equal(t,
		DefaultBase+"/grc20/gno.land%2Fr%2Fgnoswap%2Fgns.GNS.0000000?network=mainnet",
		s.Token("gno.land/r/gnoswap/gns.GNS.0000000"))
}

func TestURLQuery(cur realm, t *testing.T) {
	s := mainnet()

	uassert.Equal(t, DefaultBase+"/anything?network=mainnet", s.URL("anything"))
	uassert.Equal(t, DefaultBase+"/anything?network=mainnet", s.URL("/anything"))
	uassert.Equal(t, DefaultBase+"/a?k=v&network=mainnet", s.URL("/a", "k", "v"))

	// An empty key or value is dropped, so an optional parameter needs no
	// branch at the call site.
	uassert.Equal(t, DefaultBase+"/a?network=mainnet", s.URL("/a", "k", ""))
	uassert.Equal(t, DefaultBase+"/a?network=mainnet", s.URL("/a", "", "v"))

	uassert.PanicsWithMessage(t, cur, "mygnoscan: odd number of query arguments", func() {
		s.URL("/a", "k")
	})
}

// TestNoNetwork pins what a Scanner emits when it does not know the chain:
// nothing. The explorer then answers for every chain it indexes at once, which
// is a real answer to a different question, so this is worth being explicit
// about rather than discovering from a plausible-looking page.
func TestNoNetwork(t *testing.T) {
	s := New(DefaultBase).WithNetwork("")
	uassert.Equal(t, "", s.Network())
	uassert.Equal(t, DefaultBase+"/realm/r/moul/home", s.Realm("r/moul/home"))
	uassert.Equal(t, DefaultBase+"/realm/r/moul/home?tab=calls", s.Realm("r/moul/home", TabCalls))
	uassert.Equal(t, DefaultBase+"/", s.Home())
}

// TestDefaultUnderTest pins Default() as the test harness sees it: chain-id
// "dev" is indexed nowhere, so the links carry no network. A realm rendering
// under gnodev gets exactly this, which is why a local preview link is not
// proof that the mainnet one is right.
func TestDefaultUnderTest(t *testing.T) {
	s := Default()
	uassert.Equal(t, DefaultBase, s.Base())
	uassert.Equal(t, "", s.Network())
	uassert.Equal(t, DefaultBase+"/realm/r/moul/home", s.Realm("gno.land/r/moul/home"))
}

func TestTabArity(cur realm, t *testing.T) {
	s := mainnet()
	uassert.PanicsWithMessage(t, cur, "mygnoscan: at most one tab", func() {
		s.Realm("r/moul/home", TabSource, TabCalls)
	})
}

func TestLink(t *testing.T) {
	uassert.Equal(t, "[text](https://example.com)", Link("text", "https://example.com"))
}

func TestRealmFooter(t *testing.T) {
	s := mainnet()
	const want = "[explorer](https://mygnoscan.moul.p2p.team/realm/r/moul/home?network=mainnet)" +
		" · [source](https://mygnoscan.moul.p2p.team/realm/r/moul/home?network=mainnet&tab=source)" +
		" · [calls](https://mygnoscan.moul.p2p.team/realm/r/moul/home?network=mainnet&tab=calls)" +
		" · [deps](https://mygnoscan.moul.p2p.team/realm/r/moul/home?network=mainnet&tab=deps)"
	uassert.Equal(t, want, s.RealmFooter("gno.land/r/moul/home"))
	uassert.Equal(t, want, s.RealmFooter("r/moul/home"))
	uassert.Equal(t, "", s.RealmFooter(""))
}

// TestOtherInstance is the whole reason base and network are separate knobs:
// a second instance serving the same chain under a different id.
func TestOtherInstance(t *testing.T) {
	s := New("https://scan.example.com").WithNetwork("gnoland1")
	uassert.Equal(t,
		"https://scan.example.com/realm/r/moul/home?network=gnoland1",
		s.Realm("gno.land/r/moul/home"))
}

// TestMarkdownBreakout is the reason safePath and escapeSegment exist. A realm
// that links a path or a hash a caller typed would otherwise let that caller
// close the markdown link early and write page text of their choosing.
//
// url.PathEscape is not enough on its own: "(" and ")" are legal URL
// sub-delims and it leaves both alone.
func TestMarkdownBreakout(t *testing.T) {
	s := mainnet()

	// A path is refused outright, because escaping its separators would break
	// the route. The caller gets the front page, not a broken link.
	uassert.Equal(t, DefaultBase+"/?network=mainnet",
		s.Realm("r/evil/x)](https://evil.example.com"))
	uassert.Equal(t, "", s.RealmFooter("r/evil/x)](https://evil.example.com"))

	// A hash and a token key are opaque, so they are escaped rather than
	// refused, and the parentheses move.
	uassert.Equal(t,
		DefaultBase+"/tx/x%29%5D%28evil?network=mainnet",
		s.Tx("x)](evil"))
	uassert.Equal(t,
		DefaultBase+"/grc20/x%29%5D%28evil?network=mainnet",
		s.Token("x)](evil"))

	// An address is a string type; nothing stops a realm casting into it.
	uassert.Equal(t,
		DefaultBase+"/address/g1%29%5D%28evil?network=mainnet",
		s.Address(address("g1)](evil")))

	// A page name that is not a page name lands on the front page, rather
	// than on the explorer's own unknown-path-renders-home behaviour, which
	// would look identical and mean something else.
	uassert.Equal(t, DefaultBase+"/?network=mainnet", s.Page("txs)](evil"))
	uassert.Equal(t, DefaultBase+"/?network=mainnet", s.Page(""))
}

func TestSafePath(t *testing.T) {
	tests := []struct {
		in   string
		want bool
	}{
		{"r/moul/home", true},
		{"p/moul/mygnoscan/v0", true},
		{"gas/realms", true},
		{"a", true},
		{"a.b-c_d", true},
		{"", false},
		{"a//b", false},
		{"a/", false},
		{"a b", false},
		{"a)b", false},
		{"a(b", false},
		{"a]b", false},
		{"a\nb", false},
		{"a?b", false},
		{"a#b", false},
		{"a%b", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, safePath(tt.in), "safePath("+tt.in+")")
	}
}

func TestSubViews(t *testing.T) {
	s := mainnet()
	uassert.Equal(t, DefaultBase+"/packages?network=mainnet&pv=inert", s.Packages(PackagesInert))
	uassert.Equal(t, DefaultBase+"/packages?network=mainnet", s.Packages(""))
	uassert.Equal(t, DefaultBase+"/accounts?av=balances&network=mainnet", s.Accounts(AccountsBalances))
	uassert.Equal(t, DefaultBase+"/accounts?network=mainnet", s.Accounts(""))
}
