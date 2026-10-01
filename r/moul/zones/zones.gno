// untrusted-render: slugs, chain ids, URLs and peer addresses are charset-checked
// at write time by p/moul/zones; titles, descriptions, labels and reasons are a
// caller's free text and go through ui.Inline or ui.Cell at every call site.

// Package zones is a curated registry of gno.land networks: mainnet, the
// testnets, staging chains, anybody's gnodev. Each zone carries what a node or a
// wallet needs to join it (chain id, RPC, gnoweb, genesis) plus a growing list of
// endpoints that anyone can register: RPCs, seeds and peers, indexers, faucets,
// explorers.
//
// Curation is the point. Anybody may propose a zone and register endpoints on
// it; a curator approves or rejects a proposal, retires a zone that stopped
// running, and verifies or flags an endpoint. Every decision is recorded with
// who made it and when, and a rejection, a retirement, a flag or an edit to an
// approved zone must also say why, on the zone's page. Nothing is hidden while
// it waits: proposals and unverified endpoints are listed, and labelled.
//
// This realm only manages the information and answers questions about it. The
// read helpers (GetZone, ListZones, ListEndpoints, ListAddresses) take plain
// strings so they work from `gnokey query vm/qeval` as well as from another
// realm, and turning them into a node's config.toml is a separate realm's job.
//
// The model, its validation and its state machine are p/moul/zones. This realm
// owns only who may write.
package zones

import (
	"chain/runtime"
	"strconv"
	"strings"

	"gno.land/p/moul/addrset/v1"
	"gno.land/p/moul/zones/v0"
)

// Admin is the first curator. More are invited with AddCurator and become
// curators when they accept.
const Admin address = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"

var (
	reg      = zones.NewRegistry()
	curators addrset.Set
	invited  addrset.Set // invited by a curator, not yet accepted
)

func init() {
	curators.Add(Admin)
	seed()
}

// ---- proposing and curating zones

// ProposeZone files a new zone for review. Anybody may; it is listed as a
// proposal until a curator approves or rejects it.
//
// kind is mainnet, testnet, devnet or local. gnowebURL and genesisURL may be
// empty; rpcURL may not.
func ProposeZone(cur realm, slug, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL string) {
	who := caller(cur)
	in := info(chainID, title, description, kind, gnowebURL, rpcURL, genesisURL)
	must(reg.Propose(who, runtime.ChainHeight(), strings.TrimSpace(slug), in))
}

// EditZone replaces a zone's description. A curator may edit any zone; the
// proposer may edit their own while it is still pending. Once a curator has
// approved the zone, an edit needs a reason, and it replaces the review on
// record: the page then names who changed the values, and why. A rejected or
// retired zone cannot be edited.
func EditZone(cur realm, slug, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL, reason string) {
	who := caller(cur)
	slug = strings.TrimSpace(slug)
	z := mustZone(slug)
	if !curators.Has(who) && !(z.Status == zones.Pending && z.Proposer == who) {
		panic("zones: only a curator, or the proposer while it is pending, may edit " + slug)
	}
	must(reg.Edit(slug, info(chainID, title, description, kind, gnowebURL, rpcURL, genesisURL),
		who, runtime.ChainHeight(), reason))
}

// ApproveZone makes a zone official. The reason is optional.
func ApproveZone(cur realm, slug, reason string) {
	review(cur, slug, zones.Approved, reason)
}

// RejectZone turns a proposal down. The reason is required, and public.
func RejectZone(cur realm, slug, reason string) {
	review(cur, slug, zones.Rejected, reason)
}

// RetireZone marks an official zone as no longer running. The reason is
// required: it is what an operator still holding the chain id will read.
func RetireZone(cur realm, slug, reason string) {
	review(cur, slug, zones.Retired, reason)
}

// RemoveZone deletes a pending or rejected zone and its endpoints: a curator
// may remove any, the proposer their own. A zone that was ever official is
// never removed, by anybody: an approved one is retired, and a retired one is
// kept on record.
func RemoveZone(cur realm, slug string) {
	who := caller(cur)
	slug = strings.TrimSpace(slug)
	z := mustZone(slug)
	own := z.Proposer == who && (z.Status == zones.Pending || z.Status == zones.Rejected)
	if !curators.Has(who) && !own {
		panic("zones: only a curator, or the proposer while it is pending or rejected, may remove " + slug)
	}
	// The storage deposit comes back to whoever signs the transaction that
	// frees it, so a proposer removing a zone that carries somebody else's
	// endpoints would collect the deposits those registrants paid. They take
	// back only what they alone put there; anything else waits for its
	// registrants, or for a curator.
	if !curators.Has(who) {
		for _, e := range reg.Endpoints(zones.EndpointFilter{Zone: slug}) {
			if e.Registrant != who {
				panic("zones: " + slug + " carries endpoint #" + strconv.FormatInt(e.ID, 10) +
					" registered by " + e.Registrant.String() + "; it must be removed first")
			}
		}
	}
	must(reg.RemoveZone(slug))
}

// ---- registering and curating endpoints

// RegisterEndpoint lists an endpoint on a pending or approved zone and returns
// its id. Anybody may; it shows as unverified until a curator checks it.
//
// kind is rpc, gnoweb, seed, peer, indexer, faucet or explorer. addr is a
// URL, or <node id>@<host>:<port> for a seed or a peer. label is optional:
// who runs it, in your words.
func RegisterEndpoint(cur realm, slug, kind, addr, label string) int64 {
	who := caller(cur)
	k, err := zones.ParseEndpointKind(kind)
	must(err)
	id, err := reg.Register(who, runtime.ChainHeight(), strings.TrimSpace(slug), k, addr, label)
	must(err)
	return id
}

// VerifyEndpoint marks an endpoint as checked. The reason is optional.
func VerifyEndpoint(cur realm, id int64, reason string) {
	reviewEndpoint(cur, id, zones.Verified, reason)
}

// FlagEndpoint tells readers not to use an endpoint. The reason is required.
func FlagEndpoint(cur realm, id int64, reason string) {
	reviewEndpoint(cur, id, zones.Flagged, reason)
}

// UnverifyEndpoint puts an endpoint back to unverified, for one that changed
// hands or needs checking again.
func UnverifyEndpoint(cur realm, id int64, reason string) {
	reviewEndpoint(cur, id, zones.Unverified, reason)
}

// RemoveEndpoint deletes an endpoint. Its registrant or a curator may.
func RemoveEndpoint(cur realm, id int64) {
	who := caller(cur)
	e, ok := reg.Endpoint(id)
	if !ok {
		panic("zones: no endpoint #" + strconv.FormatInt(id, 10))
	}
	if !curators.Has(who) && e.Registrant != who {
		panic("zones: only a curator or its registrant may remove endpoint #" + strconv.FormatInt(id, 10))
	}
	must(reg.RemoveEndpoint(id))
}

// ---- curators

// AddCurator invites another address to curate. Only a curator may. The
// address becomes a curator when it calls AcceptCurator itself.
//
// Two steps, deliberately: a curator set is the one thing a mistake here can
// lose for good. With a one-step add, a sole curator who invites a mistyped
// address and then steps down leaves a registry nobody controls; accepting is
// the proof that somebody holds the key.
func AddCurator(cur realm, addr address) {
	assertCurator(caller(cur))
	if !addr.IsValid() {
		panic("zones: not a valid address: " + addr.String())
	}
	if curators.Has(addr) {
		panic("zones: " + addr.String() + " is already a curator")
	}
	if !invited.Add(addr) {
		panic("zones: " + addr.String() + " is already invited")
	}
}

// AcceptCurator makes the caller a curator, if a curator invited it.
func AcceptCurator(cur realm) {
	who := caller(cur)
	if !invited.Has(who) {
		panic("zones: " + who.String() + " has no curator invitation")
	}
	invited.Remove(who)
	curators.Add(who)
}

// RemoveCurator revokes a curator, or withdraws an invitation. Only a curator
// may, and the last curator cannot be removed: a registry nobody can curate
// can never retire a dead zone.
func RemoveCurator(cur realm, addr address) {
	assertCurator(caller(cur))
	if invited.Remove(addr) {
		return
	}
	if !curators.Has(addr) {
		panic("zones: " + addr.String() + " is not a curator")
	}
	if curators.Size() == 1 {
		panic("zones: " + addr.String() + " is the last curator")
	}
	curators.Remove(addr)
}

// ---- reads: plain arguments, so `gnokey query vm/qeval` can call them

// GetZone returns the zone under slug, and whether there is one.
func GetZone(slug string) (zones.Zone, bool) {
	return reg.Zone(slug)
}

// ListZones returns the zones with that status and kind, in the order they
// were proposed. "" matches any; "approved" is the official list.
func ListZones(status, kind string) []zones.Zone {
	st, err := zones.ParseStatus(status)
	must(err)
	k, err := zones.ParseKind(kind)
	must(err)
	return reg.Zones(zones.ZoneFilter{Status: st, Kind: k})
}

// GetEndpoint returns the endpoint with that id, and whether there is one.
func GetEndpoint(id int64) (zones.Endpoint, bool) {
	return reg.Endpoint(id)
}

// ListEndpoints returns a zone's endpoints of that kind and verification,
// oldest first. "" matches any kind or verdict, so ("onyx", "", "") is
// everything on onyx and ("onyx", "peer", "verified") is what a cautious node
// should dial. The zone is required: one zone is at most MaxEndpointsPerZone
// rows, every zone together is a response no node should be asked for.
func ListEndpoints(slug, kind, status string) []zones.Endpoint {
	return reg.Endpoints(endpointFilter(slug, kind, status))
}

// ListAddresses is ListEndpoints reduced to the addresses, which is what a
// config file wants: ListAddresses("onyx", "peer", "verified").
func ListAddresses(slug, kind, status string) []string {
	out := []string{}
	for _, e := range reg.Endpoints(endpointFilter(slug, kind, status)) {
		out = append(out, e.Address)
	}
	return out
}

// IsInvited reports whether addr holds a curator invitation it has not
// accepted yet.
func IsInvited(addr address) bool { return invited.Has(addr) }

// IsCurator reports whether addr may curate.
func IsCurator(addr address) bool { return curators.Has(addr) }

// Curators returns every curator, in address order.
func Curators() []address {
	out := []address{}
	curators.IterateByOffset(0, curators.Size(), func(a address) bool {
		out = append(out, a)
		return false
	})
	return out
}

// ---- helpers

func review(cur realm, slug string, to zones.Status, reason string) {
	who := caller(cur)
	assertCurator(who)
	must(reg.ReviewZone(strings.TrimSpace(slug), to, who, runtime.ChainHeight(), reason))
}

func reviewEndpoint(cur realm, id int64, to zones.Verification, reason string) {
	who := caller(cur)
	assertCurator(who)
	must(reg.ReviewEndpoint(id, to, who, runtime.ChainHeight(), reason))
}

func endpointFilter(slug, kind, status string) zones.EndpointFilter {
	slug = strings.TrimSpace(slug)
	if slug == "" {
		panic("zones: name a zone; ListZones lists them")
	}
	k, err := zones.ParseEndpointKind(kind)
	must(err)
	v, err := zones.ParseVerification(status)
	must(err)
	return zones.EndpointFilter{Zone: slug, Kind: k, Status: v}
}

func info(chainID, title, description, kind, gnowebURL, rpcURL, genesisURL string) zones.Info {
	k, err := zones.ParseKind(kind)
	must(err)
	return zones.Info{
		ChainID:     chainID,
		Title:       title,
		Description: description,
		Kind:        k,
		GnowebURL:   gnowebURL,
		RPCURL:      rpcURL,
		GenesisURL:  genesisURL,
	}
}

// caller is the one place this realm decides who is acting: the realm token is
// checked before it is walked, because an unchecked token is not a caller.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("zones: spoofed realm")
	}
	return cur.Previous().Address()
}

func assertCurator(who address) {
	if !curators.Has(who) {
		panic("zones: " + who.String() + " is not a curator")
	}
}

func mustZone(slug string) zones.Zone {
	z, ok := reg.Zone(slug)
	if !ok {
		panic("zones: no zone " + strconv.Quote(slug))
	}
	return z
}

func must(err error) {
	if err != nil {
		panic(err.Error())
	}
}
