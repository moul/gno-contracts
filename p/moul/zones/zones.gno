// Package zones is the content model of a curated registry of gno.land
// networks: what a zone is, what an endpoint on one is, which strings each
// field accepts, and the curation states both move through.
//
// A zone is one network a person can point a node or a wallet at: mainnet, a
// testnet, a staging chain, somebody's gnodev. An endpoint is one way in: an
// RPC, a gnoweb, a seed or persistent peer, an indexer, a faucet, an explorer.
// Anybody may propose a zone, and register endpoints as the holding realm
// allows; a curator decides which
// zones are official and which endpoints are verified. Every decision is
// recorded with who made it and when; a rejection, a retirement, a flag and an
// edit to an approved zone also require a reason, which the public reads.
//
// The package decides nothing about WHO may act. Every write that records a
// decision takes the acting address and the height as arguments (the two
// removals take neither), and the realm holding the [Registry]
// decides whether that address is a curator, the proposer, or nobody. That is
// the split that lets the same model move under a different authority later (a
// DAO, a system realm) without a line changing here.
//
// Live registry: r/moul/zones.
package zones

import (
	"errors"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Status is where a zone stands in curation.
type Status string

const (
	// Pending is a proposal nobody has reviewed yet. Every zone starts here.
	Pending Status = "pending"
	// Approved is an official zone: the one state a reader should trust.
	Approved Status = "approved"
	// Rejected is a proposal a curator turned down, with the reason kept.
	Rejected Status = "rejected"
	// Retired is a zone that was official and no longer runs. It stays
	// listed, because a node operator holding its chain id deserves to find
	// out why nothing answers, until MaxRetired newer retirements push it out.
	Retired Status = "retired"
)

// Kind says what sort of network a zone is.
type Kind string

const (
	Mainnet Kind = "mainnet"
	Testnet Kind = "testnet"
	Devnet  Kind = "devnet"
	Local   Kind = "local"
)

// EndpointKind says what an endpoint is for, and therefore which address
// shape it accepts.
type EndpointKind string

const (
	RPC      EndpointKind = "rpc"      // a tm2 JSON-RPC: http(s) and tcp for gnokey, ws(s) for a subscriber
	Gnoweb   EndpointKind = "gnoweb"   // a gnoweb frontend
	Seed     EndpointKind = "seed"     // a p2p seed, for p2p.seeds
	Peer     EndpointKind = "peer"     // a p2p node, for p2p.persistent_peers
	Indexer  EndpointKind = "indexer"  // a tx-indexer GraphQL endpoint
	Faucet   EndpointKind = "faucet"   // a faucet page or API
	Explorer EndpointKind = "explorer" // a block explorer
)

// Verification is a curator's verdict on an endpoint.
type Verification string

const (
	// Unverified is every endpoint until a curator looks at it. Listed, and
	// labelled as such, never hidden: an unverified RPC is still an RPC.
	Unverified Verification = "unverified"
	// Verified means a curator checked it answers for this zone.
	Verified Verification = "verified"
	// Flagged means a curator says do not use it, and says why.
	Flagged Verification = "flagged"
)

// Statuses, Kinds, EndpointKinds and Verifications list every value of each
// enum in display order, for a Render that wants one section per value.
func Statuses() []Status { return []Status{Approved, Pending, Rejected, Retired} }

func Kinds() []Kind { return []Kind{Mainnet, Testnet, Devnet, Local} }

func EndpointKinds() []EndpointKind {
	return []EndpointKind{RPC, Gnoweb, Seed, Peer, Indexer, Faucet, Explorer}
}

func Verifications() []Verification { return []Verification{Verified, Unverified, Flagged} }

// Bounds on every caller-supplied string. A bound rather than none: every
// stored byte locks a storage deposit, and an unbounded field is a bill a
// stranger chooses the size of.
const (
	MinSlugLen        = 2
	MaxSlugLen        = 32
	MaxChainIDLen     = 50 // tm2's own limit on a chain id
	MaxTitleLen       = 64
	MaxDescriptionLen = 512
	MaxURLLen         = 256
	MaxLabelLen       = 64
	MaxReasonLen      = 280
)

// Info is everything a proposer describes about a zone. It is the part that
// can be edited; the slug, the status and the history cannot.
type Info struct {
	ChainID     string // what a node's genesis and a signer's -chainid say
	Title       string
	Description string
	Kind        Kind
	GnowebURL   string // optional: a local chain may not run one
	RPCURL      string // required: the one endpoint every tool needs
	GenesisURL  string // optional: where to download genesis.json
}

// Zone is a network, as the registry holds it.
//
// Flat on purpose: every field is a scalar. A nested struct inside a persisted
// object is stored as an object of its own, and `gnokey query vm/qeval` prints
// it as an opaque ref(...) instead of its fields, so a reader asking a node for
// a zone would get the slug and nothing they came for. [Zone.Info] gives the
// editable part back as one value.
type Zone struct {
	Slug        string // the key: [a-z0-9-], stable, and what a URL carries
	ChainID     string
	Title       string
	Description string
	Kind        Kind
	GnowebURL   string
	RPCURL      string
	GenesisURL  string

	Status     Status
	Proposer   address
	ProposedAt int64

	// Revision changes on every edit of the zone's Info, on every status
	// change and on every restated decision, and is never reused,
	// not even by a zone removed and proposed again under the same slug. A
	// curator acting on a zone names the revision they read, so an edit that
	// lands between their reading and their decision makes the decision fail
	// instead of attaching their name to text they never saw.
	Revision int64
	EditedBy address // who last edited the Info; empty if nobody has
	EditedAt int64
	Entered  int64 // when it entered its current status, in registry order: eviction goes oldest first

	// The latest curator decision, empty until there is one. A curator's edit
	// to an approved zone is a decision too, and replaces these.
	ReviewedBy address
	ReviewedAt int64
	Reason     string
}

// Info returns the part of the zone a proposer described.
func (z Zone) Info() Info {
	return Info{
		ChainID:     z.ChainID,
		Title:       z.Title,
		Description: z.Description,
		Kind:        z.Kind,
		GnowebURL:   z.GnowebURL,
		RPCURL:      z.RPCURL,
		GenesisURL:  z.GenesisURL,
	}
}

// Reviewed reports whether a curator has decided anything about the zone,
// including an edit made after its first review.
func (z Zone) Reviewed() bool { return z.ReviewedBy != "" }

func (z *Zone) setInfo(in Info) {
	z.ChainID = in.ChainID
	z.Title = in.Title
	z.Description = in.Description
	z.Kind = in.Kind
	z.GnowebURL = in.GnowebURL
	z.RPCURL = in.RPCURL
	z.GenesisURL = in.GenesisURL
}

// Endpoint is one way into a zone, as the registry holds it. Flat for the same
// reason as [Zone].
type Endpoint struct {
	ID           int64
	Zone         string // the zone's slug
	Kind         EndpointKind
	Address      string // a URL, or id@host:port for a seed or a peer
	Label        string // who runs it, or what it is, in the registrant's words
	Registrant   address
	RegisteredAt int64

	Status     Verification
	ReviewedBy address
	ReviewedAt int64
	Reason     string
	// Revision is bumped, from the registry-wide counter zones use, when the
	// endpoint is registered, on every verdict and on every reset. A verdict
	// and a removal name it, so either fails on an endpoint that changed
	// after it was read.
	Revision int64
	// Exempt marks an endpoint registered through RegisterExempt, by a
	// reviewer the holder trusts: never clearable as a never-reviewed one,
	// whoever is a reviewer later.
	Exempt bool
}

// Clearable reports whether nobody has ruled on the endpoint and it was not a
// reviewer's own registration: no verdict (every verdict names its
// reviewer), no reset (every reset leaves a reason), not Exempt. It is what
// a bulk clear of a flood may remove.
func (e Endpoint) Clearable() bool { return !e.Exempt && e.ReviewedBy == "" && e.Reason == "" }

// ParseStatus reads a status from a caller's string. "" is the zero Status,
// which a filter reads as "any".
func ParseStatus(s string) (Status, error) {
	switch st := Status(TrimSpaces(s)); st {
	case "", Pending, Approved, Rejected, Retired:
		return st, nil
	}
	return "", errors.New("zones: unknown status " + strconv.Quote(s) + ", want approved, pending, rejected or retired")
}

// ParseKind reads a zone kind. "" is the zero Kind, "any" to a filter.
func ParseKind(s string) (Kind, error) {
	switch k := Kind(TrimSpaces(s)); k {
	case "", Mainnet, Testnet, Devnet, Local:
		return k, nil
	}
	return "", errors.New("zones: unknown kind " + strconv.Quote(s) + ", want mainnet, testnet, devnet or local")
}

// ParseEndpointKind reads an endpoint kind. "" is "any" to a filter.
func ParseEndpointKind(s string) (EndpointKind, error) {
	switch k := EndpointKind(TrimSpaces(s)); k {
	case "", RPC, Gnoweb, Seed, Peer, Indexer, Faucet, Explorer:
		return k, nil
	}
	return "", errors.New("zones: unknown endpoint kind " + strconv.Quote(s) +
		", want rpc, gnoweb, seed, peer, indexer, faucet or explorer")
}

// ParseVerification reads an endpoint verdict. "" is "any" to a filter.
func ParseVerification(s string) (Verification, error) {
	switch v := Verification(TrimSpaces(s)); v {
	case "", Unverified, Verified, Flagged:
		return v, nil
	}
	return "", errors.New("zones: unknown verification " + strconv.Quote(s) + ", want verified, unverified or flagged")
}

// ValidateSlug accepts 2 to 32 characters of [a-z0-9-], starting and ending
// with a letter or a digit.
//
// Checked at write time rather than escaped at render time, deliberately: the
// slug is also an index key and a URL path segment, so one carrying a slash or
// a pipe would break the link and the table as well as the page.
func ValidateSlug(s string) error {
	if len(s) < MinSlugLen || len(s) > MaxSlugLen {
		return errors.New("zones: a slug is " + strconv.Itoa(MinSlugLen) + " to " +
			strconv.Itoa(MaxSlugLen) + " characters, got " + strconv.Quote(s))
	}
	for i, r := range s {
		alnum := (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9')
		if alnum || (r == '-' && i > 0 && i < len(s)-1) {
			continue
		}
		return errors.New("zones: a slug is [a-z0-9-] and starts and ends alphanumeric, got " + strconv.Quote(s))
	}
	return nil
}

// ValidateChainID accepts what tm2 accepts for a chain id: 1 to 50
// characters, here narrowed to [A-Za-z0-9._-] so it is safe raw in a table.
func ValidateChainID(s string) error {
	if s == "" || len(s) > MaxChainIDLen {
		return errors.New("zones: a chain id is 1 to " + strconv.Itoa(MaxChainIDLen) + " characters")
	}
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '.', r == '_', r == '-':
		default:
			return errors.New("zones: a chain id is [A-Za-z0-9._-], got " + strconv.Quote(s))
		}
	}
	return nil
}

// ValidateInfo checks every field of a zone's description, and returns the
// first problem it finds.
func ValidateInfo(in Info) error {
	if err := ValidateChainID(in.ChainID); err != nil {
		return err
	}
	if err := checkText("title", in.Title, 1, MaxTitleLen); err != nil {
		return err
	}
	if err := checkText("description", in.Description, 0, MaxDescriptionLen); err != nil {
		return err
	}
	// Exact values only: ParseKind trims, and a Kind(" testnet ") stored as
	// written would match no filter.
	switch in.Kind {
	case Mainnet, Testnet, Devnet, Local:
	case "":
		return errors.New("zones: a zone needs a kind: mainnet, testnet, devnet or local")
	default:
		return errors.New("zones: unknown kind " + strconv.Quote(string(in.Kind)) + ", want mainnet, testnet, devnet or local")
	}
	if err := checkURL("rpc url", in.RPCURL, primarySchemes); err != nil {
		return err
	}
	// gnokey's -remote is <scheme>://<host>[:<port>] and reads anything after
	// :// as the socket address: a path, a query, a fragment, even a lone
	// trailing slash, prints a command that cannot dial (https://host/ dials
	// "host/:443"). An rpc ENDPOINT may still carry a path.
	if _, rest, _ := strings.Cut(in.RPCURL, "://"); strings.IndexAny(rest, "/?#") >= 0 {
		return errors.New("zones: the rpc url is <scheme>://<host>[:<port>], what gnokey -remote takes, with no path, not even a trailing slash: " +
			strconv.Quote(in.RPCURL))
	}
	// A zone's own URLs carry no empty tail an endpoint would be stored
	// without: the zone's URL and its own listing must key alike, or a flag on
	// the listing would miss the URL it is about.
	for _, u := range [][2]string{{"gnoweb url", in.GnowebURL}, {"genesis url", in.GenesisURL}} {
		if u[1] == "" {
			continue
		}
		if err := checkURL(u[0], u[1], webSchemes); err != nil {
			return err
		}
		if trimEmptyTail(u[1]) != u[1] {
			return errors.New("zones: the " + u[0] + " ends in an empty query or a bare \"/\"; drop it: " + strconv.Quote(u[1]))
		}
	}
	// A loopback or private address names a different machine for every
	// reader. Fine for a local zone, which is exactly that; on any other kind
	// it points a config generator at whatever answers inside the reader's own
	// network.
	if in.Kind != Local {
		for _, u := range []string{in.RPCURL, in.GnowebURL, in.GenesisURL} {
			if u != "" && IsPrivateHost(HostOf(RPC, u)) {
				return errors.New("zones: " + strconv.Quote(u) + " names a private or special-use host; only a local zone lists those")
			}
		}
	}
	return nil
}

// HostOf returns the host of an endpoint address: the part between :// and
// the port or path of a URL, or between @ and the port of a peer. It assumes
// an address that already passed validation.
func HostOf(kind EndpointKind, addr string) string {
	if kind == Seed || kind == Peer {
		_, hostport, _ := strings.Cut(addr, "@")
		if i := strings.LastIndexByte(hostport, ':'); i >= 0 {
			return hostport[:i]
		}
		return hostport
	}
	_, rest, _ := strings.Cut(addr, "://")
	if i := strings.IndexAny(rest, "/?"); i >= 0 {
		rest = rest[:i]
	}
	if i := strings.LastIndexByte(rest, ':'); i >= 0 {
		rest = rest[:i]
	}
	return rest
}

// IsPrivateHost reports whether host names a machine that is different for
// every reader, or no machine at all:
//
//   - a name with no dot (resolved through the reader's own search domain), or
//     one under a suffix reserved for local or private use, or that public DNS
//     does not delegate: .localhost, .local (mDNS), .internal, .localdomain,
//     .test, .example, .invalid, .lan, .home, .corp, .mail, .intranet,
//     .private, .alt, .onion and .i2p, the service-discovery and container names
//     .consul, .lxd, .incus, .docker, .podman, .localnet and .svc, and every
//     .arpa name, which is infrastructure
//     and never a public service (.home.arpa, ipv4only.arpa,
//     default.service.arpa). Hosts files' localhost4, localhost6,
//     ip6-localhost and ip6-loopback have no dot and fall under the first rule;
//   - an IPv4 address in a loopback, private, link-local, carrier-grade NAT,
//     "this network", IETF-protocol, documentation, benchmarking, 6to4 relay
//     anycast, multicast or reserved range;
//   - anything else shaped like a number but not a valid dotted quad, so an
//     outside caller is not told 127.1 is public (validation refuses it anyway).
//
// It fails closed: anything but a bare host ([A-Za-z0-9.-] only) is private
// to it. It looks at the string only; a public name that resolves to a private
// address is beyond what a registry can know.
func IsPrivateHost(host string) bool {
	// Fail closed: anything but a bare host (a port, a path, a stray
	// character) is not one this can vouch for.
	for i := 0; i < len(host); i++ {
		if c := host[i]; !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '.' || c == '-') {
			return true
		}
	}
	h := strings.ToLower(strings.TrimSuffix(host, "."))
	if !strings.Contains(h, ".") {
		return true
	}
	for _, suffix := range []string{".localhost", ".local", ".internal", ".arpa", ".localdomain",
		".test", ".example", ".invalid", ".lan", ".home", ".corp", ".mail", ".intranet", ".private", ".onion", ".alt",
		".consul", ".lxd", ".incus", ".docker", ".podman", ".localnet", ".svc", ".i2p"} {
		if strings.HasSuffix(h, suffix) {
			return true
		}
	}
	labels := strings.Split(h, ".")
	last := labels[len(labels)-1]
	numeric := strings.Trim(last, "0123456789") == "" || strings.HasPrefix(last, "0x")
	if !numeric {
		return false
	}
	if checkIPv4(h) != nil {
		return true
	}
	a, _ := strconv.Atoi(labels[0])
	b, _ := strconv.Atoi(labels[1])
	c, _ := strconv.Atoi(labels[2])
	switch {
	case a == 0, a == 10, a == 127, a >= 224:
		return true
	case a == 169 && b == 254, a == 192 && b == 168:
		return true
	case a == 172 && b >= 16 && b <= 31, a == 100 && b >= 64 && b <= 127:
		return true
	case a == 192 && b == 0 && c == 0, a == 198 && (b == 18 || b == 19), a == 192 && b == 88 && c == 99:
		return true
	case a == 192 && b == 0 && c == 2, a == 198 && b == 51 && c == 100, a == 203 && b == 0 && c == 113:
		return true // documentation ranges
	}
	return false
}

// ValidateEndpoint checks an endpoint's address against the shape its kind
// needs: a URL for everything but a seed or a peer, which are id@host:port.
func ValidateEndpoint(kind EndpointKind, addr string) error {
	switch kind {
	case RPC:
		if err := checkURL("rpc address", addr, rpcSchemes); err != nil {
			return err
		}
		// gnokey dials a tcp:// remote as host:port, path and all, so one with
		// a path is undialable, and Canonical would read it as an http URL
		// that is a different resource.
		if scheme, rest, _ := strings.Cut(addr, "://"); strings.EqualFold(scheme, "tcp") &&
			strings.IndexAny(rest, "/?") >= 0 {
			return errors.New("zones: a tcp:// rpc address is host and port only, no path or query")
		}
		return nil
	case Indexer:
		// A tx-indexer serves GraphQL subscriptions over a websocket too.
		return checkURL("indexer address", addr, rpcSchemes[:4])
	case Gnoweb, Faucet, Explorer:
		return checkURL(string(kind)+" address", addr, webSchemes)
	case Seed, Peer:
		return checkPeer(addr)
	case "":
		return errors.New("zones: an endpoint needs a kind")
	}
	// Exact values only. The Parse functions trim a caller's string, so an
	// EndpointKind(" rpc ") would parse, be stored as written, and then match
	// no filter: refused here rather than normalised behind the caller's back.
	return errors.New("zones: unknown endpoint kind " + strconv.Quote(string(kind)) +
		", want rpc, gnoweb, seed, peer, indexer, faucet or explorer")
}

// ValidateLabel accepts an optional single line of up to 64 characters.
func ValidateLabel(s string) error { return checkText("label", s, 0, MaxLabelLen) }

// ValidateReason accepts an optional single line of up to 280 characters.
// Whether a reason is REQUIRED depends on the decision; see [Registry].
func ValidateReason(s string) error { return checkText("reason", s, 0, MaxReasonLen) }

var (
	// rpcSchemes is what an rpc ENDPOINT may be: a websocket subscriber is a
	// real consumer of one.
	rpcSchemes = []string{"https", "http", "wss", "ws", "tcp"}
	// primarySchemes is what a zone's main RPC may be, narrower on purpose: it
	// is what every tool is pointed at first, gnokey's -remote included, and
	// gnokey's query client dials http, https and tcp only, so a wss:// main
	// RPC would print a command that cannot run.
	primarySchemes = []string{"https", "http", "tcp"}
	webSchemes     = []string{"https", "http"}
)

// ValidAddress reports whether a is a valid g1 address in the one spelling the
// chain uses for it: lowercase. bech32 also decodes an all-uppercase string, so
// IsValid accepts G1ABC…, but every comparison here (curators, proposers,
// registrants, node ids) is on the string, and an uppercase spelling of a real
// address would be a second identity for it.
func ValidAddress(a address) bool {
	return a.IsValid() && string(a) == strings.ToLower(string(a))
}

// HasVisible reports whether s has at least one character a reader can see:
// not a space, not a combining mark, not an invisible format character, not a
// blank filler. A
// required title or reason must, or it passes the "needs a reason" check and
// renders blank.
func HasVisible(s string) bool {
	for _, r := range s {
		if !unicode.IsSpace(r) && !unicode.IsMark(r) && !unicode.Is(unicode.Cf, r) && !isBlankFiller(r) {
			return true
		}
	}
	return false
}

// isBlankFiller is the handful of characters that are letters or symbols by
// category and still draw nothing: the Hangul fillers, the blank Braille cell,
// the musical null notehead, the Egyptian hieroglyph blanks, and the Khmer
// inherent vowels and the Khitan filler (marks by category, drawn as nothing). Unicode does not class them as format
// characters, so they need naming.
func isBlankFiller(r rune) bool {
	switch r {
	case 0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800, 0x1D159, 0x17B4, 0x17B5,
		0x13441, 0x13442, 0x16FE4:
		return true
	}
	return false
}

// isSelector is the variation selectors, all three blocks (U+180E, inside the
// Mongolian range, is a format character and refused as one): invisible on their
// own, and an invisible difference between two spellings of a name.
func isSelector(r rune) bool {
	return (r >= 0xFE00 && r <= 0xFE0F) || (r >= 0xE0100 && r <= 0xE01EF) || (r >= 0x180B && r <= 0x180F)
}

// selects reports whether a variation selector modifies the character before
// it, the one place it is text rather than an invisible difference: the
// emoji and text presentation selectors after a symbol (a phone writes ❤️ as
// U+2764 U+FE0F), the Mongolian free variation selectors after a Mongolian
// letter, and an ideographic variation sequence after a Han ideograph. A
// selector cannot make a badge: every symbol that looks like one is refused on
// its own.
func selects(base, sel rune) bool {
	switch {
	case sel == 0xFE0E || sel == 0xFE0F:
		// The symbols, and the five emoji whose base is punctuation or a
		// letter by category: ‼ ⁉ ℹ 〰 〽.
		return unicode.In(base, unicode.So, unicode.Sm) ||
			base == 0x203C || base == 0x2049 || base == 0x2139 || base == 0x3030 || base == 0x303D
	case sel >= 0x180B && sel <= 0x180F && sel != 0x180E:
		return base >= 0x1820 && base <= 0x18AA
	case sel >= 0xE0100 && sel <= 0xE01EF:
		return unicode.Is(unicode.Han, base)
	}
	return false
}

// isBadge is the status glyphs Render draws, and their look-alikes, refused in
// free text so a title cannot claim "✔ official" beside a pending badge.
func isBadge(r rune) bool {
	switch r {
	case 0x2705, 0x26A0, 0x23F3, 0x274C, 0x23F9, // ✅ ⚠ ⏳ ❌ ⏹, what Render draws
		0x2713, 0x2714, 0x2611, 0x1F5F8, 0x1F5F9, 0x1F197, // check marks, 🆗
		0x2716, 0x2717, 0x2718, 0x2715, 0x274E, 0x2612, 0x1F6AB, 0x26D4, 0x1F6D1, // crosses, no-entry
		0x1F5F4, 0x1F5F5, 0x1F5F6, 0x1F5F7, // ballot x and ballot box with x
		0x231B, 0x23F8, 0x23FA, // ⌛ ⏸ ⏺
		0x1FBB1, 0x237B, 0x10102, // more check marks
		0x1F5D9, 0x2A2F, 0x2573, 0x2BBD, 0x2BBE, 0x2BBF, // more crosses and ballot boxes
		0x29D6, 0x29D7, // hourglasses
		0x2613, 0x2A09, // saltire, n-ary times (× itself is everyday text: 1920×1080)
		0x22A0, 0x2327, 0x1F147, 0x1F187, 0x2297, 0x2A02, 0x1F167, // boxed and circled crosses
		0x1F6C7, 0x2298, 0x29B8, // prohibition signs
		0x24CD, 0x24E7, 0x24B3, 0x1F127, 0x29BB, 0x2A34, 0x2A35, 0x2A37, 0x292B, 0x292C, // circled, parenthesized and crossing x
		0x1F532, 0x1F533, // square buttons, beside ⏹
		0x26DD, 0x1F5BE, 0x2B59, 0x2A36, 0x26D2, 0x1FBC0, 0x1D145, 0x26CC, 0x2A3B, // more boxed, circled and heavy crosses
		0x1FBBD, 0x1F6AD, 0x1F6AF, 0x1F6B1, 0x1F6B3, 0x1F6B7, 0x1F4F5, 0x1F51E, 0x1F10D, 0x1F10F, 0x1F16E: // more no-entry signs
		return true
	}
	return r >= 0x1F7A8 && r <= 0x1F7AE // the geometric crosses beside ✖
}

// checkText bounds a free-text field by runes (so at most four times as many
// bytes) and keeps it to one line of text that shows what it stores:
//
//   - no control character: C0, DEL, C1, U+2028, U+2029. Several are line
//     breaks that ui.Inline folds to a space, the rest draw nothing; either
//     way the text shown would not be the text stored.
//   - no invisible or undrawable character: every format character (Unicode
//     Cf, which covers the bidi controls and isolates, the zero-width
//     characters, U+061C, word joiners, tags), every character that is not
//     graphic (private use, unassigned, noncharacters), the blank fillers, a
//     variation selector except right after a base it modifies (selects), the
//     combining grapheme joiner. A title made of them
//     would pass the length check and render blank or as a box.
//   - no enclosing mark, which draws a badge's frame around any character,
//     and no run of more than four nonspacing marks, which stack over
//     neighbouring lines (a spacing mark takes its own width and ends a run,
//     so Devanagari, Gurmukhi, Burmese and Tibetan words pass), and none of
//     the status glyphs a Render draws.
//   - valid UTF-8, because the page would show U+FFFD for a byte stored raw.
//
// Refused rather than stripped, so what is stored is what is shown.
func checkText(field, s string, min, max int) error {
	// No rune is more than four bytes: anything longer cannot be within max
	// characters, and is refused before a per-rune scan the writer pays for.
	if len(s) > 4*max {
		return errors.New("zones: the " + field + " is longer than " + strconv.Itoa(max) + " characters")
	}
	n, marks, prev := 0, 0, rune(0)
	for i, r := range s {
		if r == utf8.RuneError {
			if _, size := utf8.DecodeRuneInString(s[i:]); size <= 1 {
				return errors.New("zones: the " + field + " is not valid UTF-8")
			}
		}
		if r < 0x20 || (r >= 0x7f && r <= 0x9f) || r == 0x2028 || r == 0x2029 {
			return errors.New("zones: the " + field + " contains a control character")
		}
		if unicode.Is(unicode.Cf, r) || isBlankFiller(r) || r == 0x034F || (isSelector(r) && !selects(prev, r)) {
			return errors.New("zones: the " + field + " contains an invisible or bidi character")
		}
		if !unicode.IsGraphic(r) && !unicode.IsSpace(r) {
			// The chain's unicode tables are Unicode 15.0, so a character
			// assigned since then is refused here even where gno test (which
			// uses the host's newer tables) accepts it.
			return errors.New("zones: the " + field + " contains " + strconv.QuoteToASCII(string(r)) +
				", which this chain does not draw: private use, a noncharacter, or unassigned in its Unicode 15.0 tables")
		}
		if isBadge(r) {
			return errors.New("zones: the " + field + " contains a status glyph a Render draws, or a look-alike of one: " + strconv.Quote(string(r)))
		}
		if unicode.Is(unicode.Me, r) {
			// An enclosing mark draws a frame around what precedes it: !\u20E4
			// is a warning triangle, v\u20DE a checked box. No living script
			// needs one, and keycaps need U+FE0F, refused above.
			return errors.New("zones: the " + field + " contains an enclosing mark, which draws a status glyph's frame")
		}
		if unicode.Is(unicode.Mn, r) {
			marks++
			if marks > 4 {
				return errors.New("zones: the " + field + " stacks more than four combining marks")
			}
		} else {
			marks = 0
		}
		prev = r
		n++
		if n > max {
			break // refused below; no need to classify the rest
		}
	}
	if n > max {
		return errors.New("zones: the " + field + " is longer than " + strconv.Itoa(max) + " characters")
	}
	if n < min {
		return errors.New("zones: the " + field + " is " + strconv.Itoa(min) + " to " +
			strconv.Itoa(max) + " characters, got " + strconv.Itoa(n))
	}
	if s != "" && !HasVisible(s) {
		return errors.New("zones: the " + field + " has nothing visible in it")
	}
	return nil
}

// checkURL accepts scheme://host[:port][/path][?query], in visible ASCII (no
// space, no control), with no character that could close a markdown link or
// open a new construct around it. Narrower than RFC 3986 on purpose: these
// URLs are rendered as links and copied into config files, and neither wants
// a quote or a bracket. Also refused:
//
//   - a fragment (#): it is never sent to the server, so every #1, #2 would be
//     another listing of the same endpoint.
//   - a % not followed by two hex digits, and an &name; shape: the link
//     sanitizer re-encodes both, so the href would differ from the text shown.
func checkURL(field, s string, schemes []string) error {
	if s == "" {
		return errors.New("zones: the " + field + " is empty")
	}
	if len(s) > MaxURLLen {
		return errors.New("zones: the " + field + " is longer than " + strconv.Itoa(MaxURLLen) + " bytes")
	}
	n := len(s)
	for i := 0; i < n; i++ {
		c := s[i]
		if c <= ' ' || c >= 0x7f || isURLForbidden(c) {
			r, _ := utf8.DecodeRuneInString(s[i:]) // the character, not its first byte
			return errors.New("zones: the " + field + " contains " + strconv.QuoteRune(r) + ": " + strconv.Quote(s))
		}
		if c == '%' && (i+2 >= n || !isHex(s[i+1]) || !isHex(s[i+2])) {
			return errors.New("zones: the " + field + " has a % that is not followed by two hex digits: " + strconv.Quote(s))
		}
		if c == '%' && isUnreserved(unhex(s[i+1])<<4|unhex(s[i+2])) {
			// %7E and ~ are the same URL (RFC 3986): one spelling, so two
			// listings cannot be the same endpoint.
			return errors.New("zones: the " + field + " escapes a character that needs no escaping: " + strconv.Quote(s))
		}
		if c == '&' && isEntity(s[i+1:]) {
			return errors.New("zones: the " + field + " contains an HTML entity shape: " + strconv.Quote(s))
		}
	}
	scheme, rest, ok := strings.Cut(s, "://")
	if !ok {
		return errors.New("zones: the " + field + " needs a scheme (" + strings.Join(schemes, ", ") + "): " + strconv.Quote(s))
	}
	// A scheme is case-insensitive, so HTTPS:// is https://; Canonical lowercases
	// it the same way, which is what makes the two one endpoint.
	known := false
	for _, sc := range schemes {
		if strings.ToLower(scheme) == sc {
			known = true
			break
		}
	}
	if !known {
		return errors.New("zones: the " + field + " scheme is " + strconv.Quote(scheme) + ", want one of " +
			strings.Join(schemes, ", "))
	}
	authority := rest
	if i := strings.IndexAny(authority, "/?#"); i >= 0 {
		authority = authority[:i]
		// A "." or ".." path segment is resolved away by every browser and by
		// RFC 3986, so it would be a second spelling of another URL.
		path := rest[i:]
		if j := strings.IndexByte(path, '?'); j >= 0 {
			path = path[:j]
		}
		for _, seg := range strings.Split(path, "/") {
			if seg == "." || seg == ".." {
				return errors.New("zones: the " + field + " has a . or .. path segment: " + strconv.Quote(s))
			}
		}
	}
	if strings.Contains(authority, "@") {
		return errors.New("zones: the " + field + " carries credentials: " + strconv.Quote(s))
	}
	host, port := authority, ""
	if i := strings.LastIndexByte(authority, ':'); i >= 0 {
		host, port = authority[:i], authority[i+1:]
		if err := checkPort(port); err != nil {
			return errors.New("zones: the " + field + "'s port is 1 to 65535, got " + strconv.Quote(port))
		}
	}
	if host == "" {
		return errors.New("zones: the " + field + " has no host: " + strconv.Quote(s))
	}
	if err := checkHost(host); err != nil {
		return errors.New("zones: the " + field + "'s host is a DNS name or an IPv4 address, got " + strconv.Quote(host))
	}
	return nil
}

// checkHost accepts a DNS name or a dotted IPv4 address.
//
// A DNS name is labels of 1 to 63 characters of [A-Za-z0-9-], alphanumeric at
// both ends, at most 253 characters in all, with one optional terminal dot.
// Anything a browser would parse as IPv4 must BE a valid dotted-quad address:
// under the WHATWG URL parser a host whose last label is numeric (decimal, or
// 0x hex) is an IPv4 address, so 0x7f.1 opens 127.0.0.1 and a.1 is no URL at
// all. Bracketed IPv6 is refused, deliberately: it is the one host shape that
// needs characters every other field here refuses, and no zone needs it yet.
func checkHost(host string) error {
	name := strings.TrimSuffix(host, ".")
	if name == "" || len(name) > 253 {
		return errors.New("bad host")
	}
	labels := strings.Split(name, ".")
	last := strings.ToLower(labels[len(labels)-1])
	if strings.Trim(last, "0123456789") == "" || strings.HasPrefix(last, "0x") {
		// No terminal dot on an address: browsers accept 1.2.3.4. but Go's
		// dialer, so gnokey and tm2, look it up as a name and fail.
		if name != host {
			return errors.New("bad ipv4")
		}
		return checkIPv4(name)
	}
	for _, label := range labels {
		if label == "" || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return errors.New("bad host")
		}
		for _, r := range label {
			switch {
			case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-':
			default:
				return errors.New("bad host")
			}
		}
	}
	return nil
}

func checkIPv4(s string) error {
	parts := strings.Split(s, ".")
	if len(parts) != 4 {
		return errors.New("bad ipv4")
	}
	for _, p := range parts {
		if p == "" || len(p) > 3 || strings.Trim(p, "0123456789") != "" || (len(p) > 1 && p[0] == '0') {
			return errors.New("bad ipv4")
		}
		if n, _ := strconv.Atoi(p); n > 255 {
			return errors.New("bad ipv4")
		}
	}
	return nil
}

// checkPort accepts 1 to 65535, decimal digits only, no leading zero. Digits
// only because strconv.Atoi takes a sign, and +443 is no port to url.Parse,
// to a browser, or to tm2's peer parser.
func checkPort(port string) error {
	if port == "" || strings.Trim(port, "0123456789") != "" || port[0] == '0' || len(port) > 5 {
		return errors.New("bad port")
	}
	if p, _ := strconv.Atoi(port); p > 65535 {
		return errors.New("bad port")
	}
	return nil
}

// isURLForbidden is the visible ASCII a URL here may not carry: what could
// close a markdown link or open a construct around it, and a fragment.
func isURLForbidden(c byte) bool {
	switch c {
	case '<', '>', '"', '\'', '`', '(', ')', '[', ']', '{', '}', '|', '\\', '^', '#':
		return true
	}
	return false
}

func isHex(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

func unhex(c byte) byte {
	switch {
	case c >= '0' && c <= '9':
		return c - '0'
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10
	}
	return c - 'A' + 10
}

// isUnreserved is RFC 3986's unreserved set: what a URL never needs to escape.
func isUnreserved(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
		c == '-' || c == '.' || c == '_' || c == '~'
}

// isEntity reports whether s starts with what an HTML entity would follow an
// ampersand with: a run of [A-Za-z0-9#] closed by a semicolon.
func isEntity(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == ';':
			return i > 0
		case (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '#':
		default:
			return false
		}
	}
	return false
}

// TrimSpaces trims ordinary spaces and tabs from both ends, and nothing else.
// strings.TrimSpace also strips line separators (U+2028, U+0085) and other
// Unicode space, which free text refuses: trimmed first, they would be
// accepted silently, changed. What a caller types that is not a plain space
// reaches the validator and is refused there.
func TrimSpaces(s string) string { return strings.Trim(s, " \t") }

// lowerAuthority lowercases a URL's scheme and host, both case-insensitive,
// and leaves the path and query as typed. Stored that way because gno's link
// sanitizer is not case-insensitive (an HTTPS:// link would render with an
// empty href), and so every later lowercasing of the host (Canonical,
// IsPrivateHost) finds nothing to change: a scan, no copy. ASCII only, see
// asciiLower.
func lowerAuthority(addr string) string {
	scheme, rest, ok := strings.Cut(addr, "://")
	if !ok {
		return addr
	}
	host, tail := rest, ""
	if i := strings.IndexAny(rest, "/?"); i >= 0 {
		host, tail = rest[:i], rest[i:]
	}
	return asciiLower(scheme) + "://" + asciiLower(host) + tail
}

// trimEmptyTail drops an empty tail from a URL, by Canonical's own rules: an
// empty query's "?" (when it is the tail's only "?") and a bare "/". gnokey
// would dial a host with them attached, so an endpoint is not stored with them
// (a zone's own URLs are refused with them instead, ValidateInfo). Canonical
// drops both too, so Canonical(trimEmptyTail(x)) == Canonical(x), and a check
// made on what a caller typed holds for what is stored. A path is kept as
// typed otherwise ("/?q" stays: Canonical reads it as "?q", a browser too).
func trimEmptyTail(addr string) string {
	scheme, rest, ok := strings.Cut(addr, "://")
	if !ok {
		return addr
	}
	i := strings.IndexAny(rest, "/?")
	if i < 0 {
		return addr
	}
	authority, tail := rest[:i], rest[i:]
	if strings.HasSuffix(tail, "?") && strings.Count(tail, "?") == 1 {
		tail = tail[:len(tail)-1]
	}
	if tail == "/" {
		tail = ""
	}
	return scheme + "://" + authority + tail
}

// asciiLower lowercases A to Z and nothing else. strings.ToLower also folds
// a few non-ASCII letters into ASCII ones (U+212A KELVIN SIGN to k, U+0130 to
// i), which would turn a URL validation refuses into one it accepts, under a
// spelling the caller never typed.
func asciiLower(s string) string {
	for i := 0; i < len(s); i++ {
		if c := s[i]; c >= 'A' && c <= 'Z' {
			b := []byte(s)
			for j := i; j < len(b); j++ {
				if b[j] >= 'A' && b[j] <= 'Z' {
					b[j] += 'a' - 'A'
				}
			}
			return string(b)
		}
	}
	return s
}

// Canonical is the form two addresses are compared in, so one endpoint cannot
// be listed twice under two spellings: the scheme and the host lowercased (both
// are case-insensitive), the host's terminal dot dropped, the scheme's default
// port dropped (:443 for https and wss, :80 for http and ws), an empty path
// before a query dropped, an empty query's "?" and a bare "/" dropped, the hex
// digits of every %XX escape uppercased, and for an rpc endpoint tcp:// read as
// http://, which is how gnokey dials it. A path or a query that says something
// is kept as typed: those are case-sensitive and name different resources. A
// peer is lowercased whole and loses its host's terminal dot: its node id is
// lowercase bech32 and its host is a name.
func Canonical(kind EndpointKind, addr string) string {
	if kind == Seed || kind == Peer {
		id, hostport, ok := strings.Cut(asciiLower(addr), "@")
		if !ok {
			return asciiLower(addr)
		}
		if i := strings.LastIndexByte(hostport, ':'); i >= 0 {
			hostport = strings.TrimSuffix(hostport[:i], ".") + hostport[i:]
		}
		return id + "@" + hostport
	}
	scheme, rest, ok := strings.Cut(addr, "://")
	if !ok {
		return addr
	}
	scheme = asciiLower(scheme)
	if kind == RPC && scheme == "tcp" {
		scheme = "http"
	}
	i := strings.IndexAny(rest, "/?")
	if i < 0 {
		i = len(rest)
	}
	authority, tail := asciiLower(rest[:i]), rest[i:]
	host, port := authority, ""
	if j := strings.LastIndexByte(authority, ':'); j >= 0 {
		host, port = authority[:j], authority[j+1:]
	}
	host = strings.TrimSuffix(host, ".")
	switch {
	case port == "443" && (scheme == "https" || scheme == "wss"),
		port == "80" && (scheme == "http" || scheme == "ws"):
		port = ""
	}
	if port != "" {
		host += ":" + port
	}
	if strings.HasSuffix(tail, "?") && strings.Count(tail, "?") == 1 {
		tail = tail[:len(tail)-1] // an empty query, not a query ending in "?"
	}
	if strings.HasPrefix(tail, "/?") {
		tail = tail[1:]
	}
	if tail == "/" {
		tail = ""
	}
	return scheme + "://" + host + upperEscapes(tail)
}

// upperEscapes uppercases the two hex digits of every %XX in s.
func upperEscapes(s string) string {
	if !strings.Contains(s, "%") {
		return s
	}
	b := []byte(s)
	for i := 0; i+2 < len(b); i++ {
		if b[i] == '%' {
			b[i+1] = toUpperHex(b[i+1])
			b[i+2] = toUpperHex(b[i+2])
		}
	}
	return string(b)
}

func toUpperHex(c byte) byte {
	if c >= 'a' && c <= 'f' {
		return c - 'a' + 'A'
	}
	return c
}

// checkPeer accepts a tm2 p2p address: <node id>@<host>:<port>, where the node
// id is the node's g1 address, as `gnoland secrets get node_id` prints it.
func checkPeer(s string) error {
	id, hostport, ok := strings.Cut(s, "@")
	if !ok {
		return errors.New("zones: a peer is <node id>@<host>:<port>, got " + strconv.Quote(s))
	}
	if len(s) > MaxURLLen {
		return errors.New("zones: a peer is longer than " + strconv.Itoa(MaxURLLen) + " bytes")
	}
	// Lowercase only: bech32 also decodes an all-uppercase id, but tm2 compares
	// node ids byte for byte when it dials, so an uppercase one never connects.
	if !ValidAddress(address(id)) {
		return errors.New("zones: a peer's node id is a lowercase g1 address, got " + strconv.Quote(id))
	}
	i := strings.LastIndexByte(hostport, ':')
	if i <= 0 {
		return errors.New("zones: a peer needs a port: " + strconv.Quote(s))
	}
	host, port := hostport[:i], hostport[i+1:]
	if err := checkPort(port); err != nil {
		return errors.New("zones: a peer's port is 1 to 65535, got " + strconv.Quote(port))
	}
	if err := checkHost(host); err != nil {
		return errors.New("zones: a peer's host is a DNS name or an IPv4 address, got " + strconv.Quote(host))
	}
	return nil
}
