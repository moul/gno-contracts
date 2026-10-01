// Package zones is the content model of a curated registry of gno.land
// networks: what a zone is, what an endpoint on one is, which strings each
// field accepts, and the curation states both move through.
//
// A zone is one network a person can point a node or a wallet at: mainnet, a
// testnet, a staging chain, somebody's gnodev. An endpoint is one way in: an
// RPC, a gnoweb, a seed or persistent peer, an indexer, a faucet, an explorer.
// Anybody may propose a zone or register an endpoint; a curator decides which
// zones are official and which endpoints are verified, always with a reason
// the public can read.
//
// The package decides nothing about WHO may act. Every write takes the acting
// address and the height as arguments, and the realm holding the [Registry]
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
	// out why nothing answers.
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
	RPC      EndpointKind = "rpc"      // a tm2 JSON-RPC, what gnokey -remote takes
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

	// The latest curator decision, empty until there is one.
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

// Reviewed reports whether a curator has decided anything about the zone.
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
}

// ParseStatus reads a status from a caller's string. "" is the zero Status,
// which a filter reads as "any".
func ParseStatus(s string) (Status, error) {
	switch st := Status(strings.TrimSpace(s)); st {
	case "", Pending, Approved, Rejected, Retired:
		return st, nil
	}
	return "", errors.New("zones: unknown status " + strconv.Quote(s) + ", want approved, pending, rejected or retired")
}

// ParseKind reads a zone kind. "" is the zero Kind, "any" to a filter.
func ParseKind(s string) (Kind, error) {
	switch k := Kind(strings.TrimSpace(s)); k {
	case "", Mainnet, Testnet, Devnet, Local:
		return k, nil
	}
	return "", errors.New("zones: unknown kind " + strconv.Quote(s) + ", want mainnet, testnet, devnet or local")
}

// ParseEndpointKind reads an endpoint kind. "" is "any" to a filter.
func ParseEndpointKind(s string) (EndpointKind, error) {
	switch k := EndpointKind(strings.TrimSpace(s)); k {
	case "", RPC, Gnoweb, Seed, Peer, Indexer, Faucet, Explorer:
		return k, nil
	}
	return "", errors.New("zones: unknown endpoint kind " + strconv.Quote(s) +
		", want rpc, gnoweb, seed, peer, indexer, faucet or explorer")
}

// ParseVerification reads an endpoint verdict. "" is "any" to a filter.
func ParseVerification(s string) (Verification, error) {
	switch v := Verification(strings.TrimSpace(s)); v {
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
	if in.Kind == "" {
		return errors.New("zones: a zone needs a kind: mainnet, testnet, devnet or local")
	}
	if _, err := ParseKind(string(in.Kind)); err != nil {
		return err
	}
	if err := checkURL("rpc url", in.RPCURL, rpcSchemes); err != nil {
		return err
	}
	if in.GnowebURL != "" {
		if err := checkURL("gnoweb url", in.GnowebURL, webSchemes); err != nil {
			return err
		}
	}
	if in.GenesisURL != "" {
		if err := checkURL("genesis url", in.GenesisURL, webSchemes); err != nil {
			return err
		}
	}
	return nil
}

// ValidateEndpoint checks an endpoint's address against the shape its kind
// needs: a URL for everything but a seed or a peer, which are id@host:port.
func ValidateEndpoint(kind EndpointKind, addr string) error {
	switch kind {
	case RPC:
		return checkURL("rpc address", addr, rpcSchemes)
	case Gnoweb, Indexer, Faucet, Explorer:
		return checkURL(string(kind)+" address", addr, webSchemes)
	case Seed, Peer:
		return checkPeer(addr)
	case "":
		return errors.New("zones: an endpoint needs a kind")
	}
	_, err := ParseEndpointKind(string(kind))
	return err
}

// ValidateLabel accepts an optional single line of up to 64 characters.
func ValidateLabel(s string) error { return checkText("label", s, 0, MaxLabelLen) }

// ValidateReason accepts an optional single line of up to 280 characters.
// Whether a reason is REQUIRED depends on the decision; see [Registry].
func ValidateReason(s string) error { return checkText("reason", s, 0, MaxReasonLen) }

var (
	rpcSchemes = []string{"https", "http", "wss", "ws", "tcp"}
	webSchemes = []string{"https", "http"}
)

// checkText bounds a free-text field by runes and refuses control characters,
// newlines included: every free-text field here renders on one line.
func checkText(field, s string, min, max int) error {
	n := 0
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return errors.New("zones: the " + field + " contains a control character")
		}
		n++
	}
	if n < min || n > max {
		if min > 0 {
			return errors.New("zones: the " + field + " is " + strconv.Itoa(min) + " to " +
				strconv.Itoa(max) + " characters, got " + strconv.Itoa(n))
		}
		return errors.New("zones: the " + field + " is at most " + strconv.Itoa(max) +
			" characters, got " + strconv.Itoa(n))
	}
	return nil
}

// checkURL accepts scheme://host[:port][/path], printable ASCII only, with no
// character that could close a markdown link or open a new construct around
// it. Narrower than RFC 3986 on purpose: these URLs are rendered as links and
// copied into config files, and neither wants a quote or a bracket.
func checkURL(field, s string, schemes []string) error {
	if s == "" {
		return errors.New("zones: the " + field + " is empty")
	}
	if len(s) > MaxURLLen {
		return errors.New("zones: the " + field + " is longer than " + strconv.Itoa(MaxURLLen) + " bytes")
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c <= ' ' || c >= 0x7f || strings.IndexByte("<>\"'`()[]{}|\\^", c) >= 0 {
			return errors.New("zones: the " + field + " contains " + strconv.Quote(string(c)) + ": " + strconv.Quote(s))
		}
	}
	scheme, rest, ok := strings.Cut(s, "://")
	if !ok {
		return errors.New("zones: the " + field + " needs a scheme (" + strings.Join(schemes, ", ") + "): " + strconv.Quote(s))
	}
	known := false
	for _, sc := range schemes {
		if scheme == sc {
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

// checkHost accepts a DNS name or a dotted IPv4 address: [A-Za-z0-9.-].
// Bracketed IPv6 is refused, deliberately: it is the one host shape that needs
// characters every other field here refuses, and no zone needs it yet.
func checkHost(host string) error {
	if len(host) > MaxURLLen {
		return errors.New("host too long")
	}
	for _, r := range host {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '.', r == '-':
		default:
			return errors.New("bad host")
		}
	}
	return nil
}

// checkPort accepts 1 to 65535, in decimal, with no leading zero.
func checkPort(port string) error {
	p, err := strconv.Atoi(port)
	if err != nil || p < 1 || p > 65535 || port[0] == '0' {
		return errors.New("bad port")
	}
	return nil
}

// Canonical is the form two addresses are compared in: the scheme and the
// host lowercased, because both are case-insensitive, and everything after the
// host kept as typed, because a path and a query are not. A peer's node id is
// bech32, already lowercase, so a peer lowercases whole.
func Canonical(kind EndpointKind, addr string) string {
	if kind == Seed || kind == Peer {
		return strings.ToLower(addr)
	}
	scheme, rest, ok := strings.Cut(addr, "://")
	if !ok {
		return addr
	}
	i := strings.IndexAny(rest, "/?#")
	if i < 0 {
		i = len(rest)
	}
	return strings.ToLower(scheme) + "://" + strings.ToLower(rest[:i]) + rest[i:]
}

// checkPeer accepts a tm2 p2p address: <node id>@<host>:<port>, where the node
// id is the node's g1 address, as `gnoland secrets get node_id` prints it.
func checkPeer(s string) error {
	id, hostport, ok := strings.Cut(s, "@")
	if !ok {
		return errors.New("zones: a peer is <node id>@<host>:<port>, got " + strconv.Quote(s))
	}
	if !address(id).IsValid() {
		return errors.New("zones: a peer's node id is a g1 address, got " + strconv.Quote(id))
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
