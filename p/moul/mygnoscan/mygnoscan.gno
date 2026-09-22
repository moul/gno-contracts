// Package mygnoscan builds links into a mygnoscan block explorer.
//
// A realm knows things a reader cannot see from its Render output: which chain
// it is on, what its address is, which block it was last written at. Turning
// any of those into a link means knowing the explorer's route table, and a
// route table hand-written into thirty realms is thirty places to fix when it
// moves. This package is the one place.
//
// # The routes are measured, not guessed
//
// Every path below was read out of the explorer's own router (its single-page
// frontend, `route()`), not inferred from the UI, on 2026-09-22. Two of them
// are retired and deliberately absent: `?tab=graph` (folded into `deps`, still
// redirected) and `?tab=inert` (folded into the default tab, silently dropped).
//
// # An unknown path renders the home page
//
// The explorer's router falls through to `home` rather than to a 404, so a
// misspelled route is not visible as an error: the link works, it just goes
// somewhere else. That is why the page names here are constants and why Page
// is the only door to them.
//
// # The network is per instance, not per chain
//
// The explorer takes `?network=<id>`, and the ids are chosen by whoever runs
// the instance: moul's names mainnet `mainnet`, while the upstream default
// config names the same chain `gnoland1`. NetworkFor maps a chain-id to the
// ids DefaultBase serves. Point Scanner at another instance and you very
// likely also want WithNetwork.
//
// Omitting the parameter is not the same as asking for mainnet: the explorer
// then blends every chain it indexes, which looks plausible and is wrong. A
// Scanner whose network is empty emits no parameter, so New on a chain nobody
// indexes produces a link to the blend. Set it explicitly when it matters.
//
// # Usage
//
// The whole point is a realm footer that stays right when the chain changes:
//
//	func Render(path string) string {
//		return body + "\n\n---\n\n" + mygnoscan.Default().CurrentRealmFooter()
//	}
//
// and, for a realm that wants to hand out sharper links:
//
//	s := mygnoscan.Default()
//	s.Address(someAddr)                              // an account
//	s.Block(runtime.ChainHeight())                   // the block we are at
//	s.Realm("gno.land/r/moul/home", mygnoscan.TabSource)
//	s.RealmFunc("gno.land/r/moul/config", "Set")     // straight at one function
//
// Nothing here reads chain state except ChainDomain, ChainID and ChainHeight,
// and nothing here writes. Building a link is free.
package mygnoscan

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"net/url"
	"strconv"
	"strings"
)

// DefaultBase is moul's instance, the one the rest of this repo links to.
const DefaultBase = "https://mygnoscan.moul.p2p.team"

// The realm-page tabs, as the explorer's own tabNames list has them. An
// unknown tab name lands on the default tab rather than erroring, so these
// exist to keep a typo out of a deployed realm.
const (
	TabInfo    = "info"    // the default; passing it emits no parameter
	TabDocs    = "docs"    // exported symbols
	TabSource  = "source"  // the .gno files as deployed
	TabCalls   = "calls"   // transactions that called this realm
	TabEvents  = "events"  // events it emitted
	TabStorage = "storage" // what it pays to store
	TabDefi    = "defi"    // balances and token positions
	TabDeps    = "deps"    // imports, dependents and the graph over them
)

// The explorer's list pages. Page takes one of these.
const (
	PageRealms     = "realms"
	PagePackages   = "packages"
	PageContracts  = "contracts"
	PageApps       = "apps"
	PageTxs        = "txs"
	PageBlocks     = "blocks"
	PageAccounts   = "accounts"
	PageDefi       = "defi"
	PageCoins      = "coins"
	PageGRC20      = "grc20"
	PageValidators = "validators"
	PageGovDAO     = "govdao"
	PageProposals  = "govdao/proposals"
	PageVoters     = "govdao/voters"
	PageOptions    = "govdao/options"
	PageParams     = "params"
	PageEvents     = "events"
	PageGas        = "gas"
	PageGasRealms  = "gas/realms"
	PageGasUsers   = "gas/users"
	PageGasTxs     = "gas/txs"
	PageStorage    = "storage"
	PageAnalytics  = "analytics"
	PageDashboards = "dashboards"
	PageSanity     = "sanity"
	PageWatch      = "watch"
)

// The sub-views of the packages and accounts pages, the only two list pages
// that restore a view from the URL.
//
// Every other list page writes its state into the query string (?by=, ?page=,
// ?status=, ?window=, ?section=, ?failed=, ?storage=, ?txs=) and does NOT read
// any of it back on load: a link carrying one of those opens the page on its
// default view instead, silently. So there are no helpers for them here.
// Measured against the explorer's router on 2026-09-22.
const (
	PackagesAll      = "all"      // every package
	PackagesInert    = "inert"    // the parked queue: submitted, not yet approved
	AccountsActivity = "activity" // ranked by what they have done
	AccountsBalances = "balances" // ranked by what they hold
)

// Scanner is one explorer instance plus the network its links should open on.
// It is a value: copying one is free and there is nothing to close.
type Scanner struct {
	base    string
	network string
}

// Default returns a Scanner pointed at DefaultBase, on whichever network
// answers for the running chain.
func Default() Scanner { return New(DefaultBase) }

// New returns a Scanner pointed at base, on whichever network answers for the
// running chain. A trailing slash on base is dropped so New("…/") and New("…")
// build the same links.
func New(base string) Scanner {
	return Scanner{
		base:    strings.TrimSuffix(base, "/"),
		network: NetworkFor(runtime.ChainID()),
	}
}

// WithNetwork returns a copy of s whose links carry ?network=id. The empty
// string removes the parameter, which asks the explorer for every chain at
// once rather than for this one.
func (s Scanner) WithNetwork(id string) Scanner {
	s.network = id
	return s
}

// Base returns the instance root, without a trailing slash.
func (s Scanner) Base() string { return s.base }

// Network returns the network id these links carry, empty when they carry none.
func (s Scanner) Network() string { return s.network }

// NetworkFor maps a chain-id to the network id DefaultBase serves it under, or
// "" when that instance does not index the chain (a gnodev, a local test).
//
// Verified against DefaultBase's /api/networks on 2026-09-22: it serves
// mainnet, pearl and staging. sapphire is mapped because the chain exists and
// an instance configured for it uses that id; DefaultBase currently answers
// for it with the blend, which is the same failure mode as an unknown chain
// and is why the caller can override with WithNetwork.
func NetworkFor(chainID string) string {
	switch chainID {
	case "gnoland-1":
		return "mainnet"
	case "pearl-1":
		return "pearl"
	case "sapphire-1":
		return "sapphire"
	case "staging":
		return "staging"
	default:
		return ""
	}
}

// URL is the one place a link is assembled: an absolute link to path on this
// instance, carrying query as key/value pairs plus the network. A pair with an
// empty key or value is dropped, so an optional parameter needs no branch at
// the call site.
//
// Prefer the typed helpers below; this is the escape hatch for a route added
// to the explorer after this package was last touched.
func (s Scanner) URL(path string, query ...string) string {
	if len(query)%2 != 0 {
		panic("mygnoscan: odd number of query arguments")
	}
	if path == "" {
		path = "/"
	} else if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}

	v := url.Values{}
	for i := 0; i < len(query); i += 2 {
		if query[i] == "" || query[i+1] == "" {
			continue
		}
		v.Set(query[i], query[i+1])
	}
	if s.network != "" {
		v.Set("network", s.network)
	}

	out := s.base + path
	if len(v) > 0 {
		out += "?" + v.Encode()
	}
	return out
}

// Home links the explorer's front page on this network.
func (s Scanner) Home() string { return s.URL("/") }

// Page links one of the Page* list pages. A name that is not shaped like one
// falls back to the front page rather than to the explorer's own
// unknown-path-renders-home behaviour, which would look identical and mean
// something else.
func (s Scanner) Page(name string) string {
	n := strings.Trim(name, "/")
	if !safePath(n) {
		return s.Home()
	}
	return s.URL("/" + n)
}

// Packages links the package list, on the PackagesAll or PackagesInert view.
// The empty string takes the page's own default, which is PackagesAll.
func (s Scanner) Packages(view string) string {
	return s.URL("/"+PagePackages, "pv", view)
}

// Accounts links the account list, on the AccountsActivity or AccountsBalances
// view. The empty string takes the page's own default, which is
// AccountsActivity.
func (s Scanner) Accounts(view string) string {
	return s.URL("/"+PageAccounts, "av", view)
}

// Realm links a package or realm page, optionally opening one tab.
//
// pkgPath is accepted either fully qualified ("gno.land/r/moul/home") or bare
// ("r/moul/home"): TrimDomain normalises it. Passing TabInfo, or no tab at
// all, emits no tab parameter.
func (s Scanner) Realm(pkgPath string, tab ...string) string {
	p := TrimDomain(pkgPath)
	if p == "" {
		return s.Home()
	}
	return s.URL("/realm/"+p, "tab", oneTab(tab))
}

// CurrentRealm links the page of the realm that called into this package.
//
// It stack-walks (unsafe.CurrentRealm), so it names whichever realm was
// current when it ran. For a plain read like this one that is the BORROWER,
// which is the wanted answer: a realm asking for "my page" gets its own, and
// so does one asking through a shared config realm, because a borrowed call
// opens no realm frame. Measured in the test harness on 2026-09-22.
//
// Inside a CROSSING function it names that function's realm instead. That is
// also correct and rarely what a link wants, so pass the path explicitly
// there. Never branch on it for authorisation either way.
func (s Scanner) CurrentRealm(tab ...string) string {
	return s.Realm(unsafe.CurrentRealm().PkgPath(), tab...)
}

// RealmFunc links a realm's source tab scrolled to one exported function.
func (s Scanner) RealmFunc(pkgPath, fn string) string {
	p := TrimDomain(pkgPath)
	if p == "" || fn == "" {
		return s.Realm(pkgPath)
	}
	return s.URL("/realm/"+p, "tab", TabSource, "fn", fn)
}

// RealmFile links a realm's source tab scrolled to one line of one file.
// A line of 0 or less links the file without an anchor.
func (s Scanner) RealmFile(pkgPath, file string, line int) string {
	p := TrimDomain(pkgPath)
	if p == "" || file == "" {
		return s.Realm(pkgPath)
	}
	if line <= 0 {
		return s.URL("/realm/"+p, "tab", TabSource, "file", file)
	}
	return s.URL("/realm/"+p, "tab", TabSource, "file", file, "line", strconv.Itoa(line))
}

// Address links an account page: its balance, its transactions, what it deployed.
//
// The address is escaped rather than trusted. `address` is a string type and
// nothing stops a realm casting a caller's input into one, so a value reaching
// here is not necessarily bech32.
func (s Scanner) Address(addr address) string {
	if addr == "" {
		return s.Page(PageAccounts)
	}
	return s.URL("/address/" + escapeSegment(addr.String()))
}

// Tx links one transaction. The hash is the base64 form the indexer and gnokey
// print, which carries "+", "/" and "="; the whole segment is percent-escaped
// so the explorer's decodeURIComponent gives it back byte for byte.
func (s Scanner) Tx(hash string) string {
	if hash == "" {
		return s.Page(PageTxs)
	}
	return s.URL("/tx/" + escapeSegment(hash))
}

// Block links one block by height.
func (s Scanner) Block(height int64) string {
	if height <= 0 {
		return s.Page(PageBlocks)
	}
	return s.URL("/block/" + strconv.FormatInt(height, 10))
}

// CurrentBlock links the block this call is executing in.
func (s Scanner) CurrentBlock() string { return s.Block(runtime.ChainHeight()) }

// Validator links one validator by address.
func (s Scanner) Validator(addr address) string {
	if addr == "" {
		return s.Page(PageValidators)
	}
	return s.URL("/validator/" + escapeSegment(addr.String()))
}

// Proposal links one GovDAO proposal by id.
func (s Scanner) Proposal(id int) string {
	if id < 0 {
		return s.Page(PageProposals)
	}
	return s.URL("/govdao/" + strconv.Itoa(id))
}

// Token links one GRC20 asset by its ledger key, which looks like
// "gno.land/r/gnoswap/gns.GNS.0000000". That key carries both slashes and
// dots, and neither is a route separator, so it is percent-escaped whole.
func (s Scanner) Token(key string) string {
	if key == "" {
		return s.Page(PageGRC20)
	}
	return s.URL("/grc20/" + escapeSegment(key))
}

// TrimDomain strips the chain domain from a package path, so both
// "gno.land/r/moul/home" and "r/moul/home" become "r/moul/home". A path that
// is not shaped like a package path (see safePath) comes back empty, and every
// caller here treats empty as "no such target" and falls back to a list page.
//
// It tries the running chain's domain first, then the literal "gno.land/",
// because the explorer's own realm route reassembles the path by prepending
// "gno.land/" unconditionally: on a chain whose domain is something else, a
// bare path is still what the link must carry.
func TrimDomain(pkgPath string) string {
	p := strings.TrimPrefix(pkgPath, runtime.ChainDomain()+"/")
	p = strings.TrimPrefix(p, "gno.land/")
	p = strings.Trim(p, "/")
	if !safePath(p) {
		return ""
	}
	return p
}

// escapeSegment percent-encodes everything outside the RFC 3986 unreserved
// set, which is exactly what JavaScript's encodeURIComponent does and
// therefore exactly what the explorer's decodeURIComponent round-trips.
//
// url.PathEscape is the obvious choice and is wrong here twice: it leaves '/'
// alone in some modes and, more importantly, it never escapes '(' or ')',
// which are legal URL sub-delims and which close a markdown link early. Since
// every link this package builds may end up inside one, the segment escaper
// has to be stricter than the URL spec requires.
func escapeSegment(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9',
			c == '-', c == '_', c == '.', c == '~':
			b.WriteByte(c)
		default:
			b.WriteByte('%')
			b.WriteByte(hex[c>>4])
			b.WriteByte(hex[c&0x0f])
		}
	}
	return b.String()
}

// safePath reports whether p is shaped like a package path: [A-Za-z0-9._/-],
// and no empty segment.
//
// This is a rendering guard, not a validity check. Everything built here ends
// up inside a markdown link, so a path carrying ')' would close the link early
// and the rest would render as page text; a path carrying a space or a newline
// breaks it differently. Percent-escaping cannot be the answer because '(' and
// ')' are legal sub-delims in a URL path and url.PathEscape leaves them alone,
// and escaping the separators would break the route. So the characters are
// refused instead.
//
// It matters because a realm may well pass a path a caller typed (a registry,
// a directory, a "link to my realm" form), and this package cannot tell.
func safePath(p string) bool {
	if p == "" {
		return false
	}
	lastSlash := true // a leading slash was already trimmed, so no empty first segment
	for i := 0; i < len(p); i++ {
		c := p[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
			lastSlash = false
		case c == '.', c == '-', c == '_':
			lastSlash = false
		case c == '/':
			if lastSlash {
				return false // "" or "a//b"
			}
			lastSlash = true
		default:
			return false
		}
	}
	return !lastSlash // no trailing slash left over
}

// Link renders a markdown link. Neither argument is escaped: everything this
// package builds is a path or a constant, never text a caller typed. Passing a
// user-supplied label through here would let it break out of the link.
func Link(text, target string) string { return "[" + text + "](" + target + ")" }

// RealmFooter is the line a realm appends under its Render output: the four
// views of itself worth one click, separated by middots.
//
// Deliberately plain markdown with no leading rule, so the caller decides
// where it sits and what separates it from the body.
func (s Scanner) RealmFooter(pkgPath string) string {
	p := TrimDomain(pkgPath)
	if p == "" {
		return ""
	}
	return Link("explorer", s.Realm(p)) +
		" · " + Link("source", s.Realm(p, TabSource)) +
		" · " + Link("calls", s.Realm(p, TabCalls)) +
		" · " + Link("deps", s.Realm(p, TabDeps))
}

// CurrentRealmFooter is RealmFooter for the realm that called in. It carries
// the same stack-walking caveat as CurrentRealm.
func (s Scanner) CurrentRealmFooter() string {
	return s.RealmFooter(unsafe.CurrentRealm().PkgPath())
}

// oneTab reads the optional tab argument. More than one is a call-site bug and
// panics rather than silently using the first, and TabInfo is dropped because
// it is the default the explorer lands on anyway.
func oneTab(tab []string) string {
	switch len(tab) {
	case 0:
		return ""
	case 1:
		if tab[0] == TabInfo {
			return ""
		}
		return tab[0]
	default:
		panic("mygnoscan: at most one tab")
	}
}
