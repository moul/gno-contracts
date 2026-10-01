// untrusted-render: slugs, chain ids, URLs and peer addresses are charset-checked
// at write time by p/moul/zones; titles, descriptions, labels and reasons are a
// caller's free text and go through ui.Inline or ui.Cell at every call site.

// Package zones is a curated registry of gno.land networks: mainnet, the
// testnets, staging chains, anybody's gnodev. Each zone carries what a node or a
// wallet needs to join it (chain id, RPC, gnoweb, genesis) plus a growing list of
// endpoints: RPCs, seeds and peers, indexers, faucets, explorers.
//
// Curation is the point. Anybody may propose a zone and register endpoints on
// an approved one (on a pending one, its proposer or a curator); a curator
// approves or rejects a proposal, retires a zone that stopped
// running, and verifies or flags an endpoint. Every decision is recorded with
// who made it and when, and a rejection, a retirement, a flag or an edit to an
// approved zone must also say why, on the zone's page. Nothing is hidden while
// it waits: proposals and unverified endpoints are listed, and labelled.
//
// This realm only manages the information and answers questions about it. The
// read helpers (GetZone, ListZones, GetEndpoint, ListEndpoints, ListAddresses,
// IsCurator, Curators, IsInvited, Invited) take plain values so they work from
// `gnokey query vm/qeval` as well as from another realm, and turning them into a
// node's config.toml is a separate realm's job.
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

// ProposerEditCooldown is how many blocks must pass after a zone was proposed
// or last edited (by anybody) before its proposer may edit or withdraw it, and
// after an endpoint was registered before its registrant may withdraw it. Every
// edit bumps the revision a curator's decision must name, and a withdrawal plus
// a fresh proposal or registration does the same with a new revision or id, so
// without a wait a proposer or a registrant acting every block would keep their
// entry out of every curator's reach. Curators are not limited.
const ProposerEditCooldown = 100

// MaxCurators bounds curators and open invitations together. The curator list
// renders on the index page, and only curators can grow it, but a bound costs
// nothing and an unbounded list on a public page is a page someone can break.
const MaxCurators = 16

var (
	reg      = zones.NewRegistry()
	curators addrset.Set
	invited  addrset.Set             // invited by a curator, not yet accepted
	inviter  = map[address]address{} // invitee -> the curator who invited them; lookups only
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
// empty; rpcURL may not, and is <scheme>://<host>[:<port>] with no path, which
// is what gnokey -remote takes.
func ProposeZone(cur realm, slug, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL string) {
	who := caller(cur)
	in := info(chainID, title, description, kind, gnowebURL, rpcURL, genesisURL)
	must(reg.Propose(who, runtime.ChainHeight(), strings.TrimSpace(slug), in))
}

// EditZone replaces a zone's Info, every field but its slug and status. A
// curator may edit any pending or approved zone; the proposer may edit their
// own while it is pending. revision is the zone's Revision the edit was
// written against: it fails if the zone changed in between, its content or its
// status. Every edit bumps the revision, so a decision prepared against the old
// one fails too. A proposer edits only ProposerEditCooldown blocks after the
// zone was proposed or last edited, and an edit that changes nothing is
// refused. On a pending zone the reason
// must be empty; on an approved one it is required and replaces the review on
// record, so the page names who changed the values, and why. A new chain id
// sends the zone's verified endpoints back to unverified. A rejected or retired
// zone cannot be edited.
func EditZone(cur realm, slug string, revision int64, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL, reason string) {
	who := caller(cur)
	slug = strings.TrimSpace(slug)
	z := mustZone(slug)
	if !curators.Has(who) {
		if z.Status != zones.Pending || z.Proposer != who {
			panic("zones: only a curator, or the proposer while it is pending, may edit " + slug)
		}
		assertCooled(slug, z)
	}
	must(reg.Edit(slug, revision, info(chainID, title, description, kind, gnowebURL, rpcURL, genesisURL),
		who, runtime.ChainHeight(), reason))
}

// ApproveZone makes a zone official. revision is the zone's Revision as you
// read it (the zone page's Approve link carries it): if the zone changed since,
// its content or its status, the approval fails and you read it again. The
// reason is optional.
func ApproveZone(cur realm, slug string, revision int64, reason string) {
	review(cur, slug, zones.Approved, revision, reason)
}

// RejectZone turns a proposal down. The reason is required, and public.
// revision is the zone's Revision you read, as for ApproveZone.
func RejectZone(cur realm, slug string, revision int64, reason string) {
	review(cur, slug, zones.Rejected, revision, reason)
}

// RetireZone marks an official zone as no longer running, and sends its
// verified endpoints back to unverified. The reason is required: it is what an
// operator still holding the chain id will read. revision is the zone's
// Revision you read.
func RetireZone(cur realm, slug string, revision int64, reason string) {
	review(cur, slug, zones.Retired, revision, reason)
}

// RemoveZone deletes a pending or rejected zone and its endpoints. revision is
// the zone's Revision you read: a removal meant for one proposal fails on
// another proposed again under the same slug. A curator may remove any pending
// or rejected zone. The proposer may withdraw their own only while it is
// pending, ProposerEditCooldown blocks after it was proposed or last edited
// (so withdrawing and proposing again cannot dodge the edit wait), while every
// endpoint on it is theirs (the deposit is refunded to whoever signs the
// removal, so removing somebody else's endpoints would collect what they paid)
// and none is verified or flagged (removing and proposing it again would wipe
// the verdict). A rejected zone is the curators' record: only a curator removes
// it, or newer rejections push it out, and the rejection's deposit, paid by the
// curator, is not the proposer's to collect. A zone that was ever official is
// never removed this way: an approved one is retired, and a retired one is kept
// until newer retirements push it out.
func RemoveZone(cur realm, slug string, revision int64) {
	who := caller(cur)
	slug = strings.TrimSpace(slug)
	z := mustZone(slug)
	if !curators.Has(who) {
		if z.Proposer != who || z.Status != zones.Pending {
			panic("zones: only a curator, or the proposer while it is pending, may remove " + slug)
		}
		assertCooled(slug, z)
		// From the index counts first: nothing is read to answer it.
		if _, total := reg.Count(slug); reg.OwnerCount(slug, who) != total {
			panic("zones: " + slug + " carries endpoints somebody else registered; they must be removed first")
		}
		// Every endpoint is the proposer's, so at most MaxEndpointsPerAddress.
		for _, e := range reg.Endpoints(zones.EndpointFilter{Zone: slug}) {
			if e.Status != zones.Unverified {
				panic("zones: " + slug + " carries endpoint #" + strconv.FormatInt(e.ID, 10) + ", " +
					string(e.Status) + " by a curator; only a curator may remove the zone now")
			}
		}
	}
	must(reg.RemoveZone(slug, revision))
}

// ---- registering and curating endpoints

// RegisterEndpoint lists an endpoint on a zone and returns its id. On an
// approved zone anybody may; on a pending one only the proposer or a curator,
// so a stranger cannot pin a proposal the proposer then cannot withdraw. It
// shows as unverified until a curator checks it.
//
// kind is rpc, gnoweb, seed, peer, indexer, faucet or explorer. addr is a
// URL, or <node id>@<host>:<port> for a seed or a peer. label is optional:
// who runs it, in your words.
func RegisterEndpoint(cur realm, slug, kind, addr, label string) int64 {
	who := caller(cur)
	slug = strings.TrimSpace(slug)
	z := mustZone(slug)
	if z.Status == zones.Pending && z.Proposer != who && !curators.Has(who) {
		panic("zones: " + slug + " is pending; only its proposer or a curator may register on it")
	}
	k, err := zones.ParseEndpointKind(kind)
	must(err)
	id, err := reg.Register(who, runtime.ChainHeight(), slug, k, addr, label)
	must(err)
	return id
}

// VerifyEndpoint marks an endpoint as checked against its zone. revision is the
// zone's Revision you checked it against: if the zone changed since, its
// content (its chain id, say) or its status, the verdict fails. The reason is
// optional.
func VerifyEndpoint(cur realm, id int64, revision int64, reason string) {
	reviewEndpoint(cur, id, zones.Verified, revision, reason)
}

// FlagEndpoint tells readers not to use an endpoint. The reason is required.
func FlagEndpoint(cur realm, id int64, reason string) {
	reviewEndpoint(cur, id, zones.Flagged, 0, reason)
}

// UnverifyEndpoint puts an endpoint back to unverified, for one that changed
// hands or needs checking again.
func UnverifyEndpoint(cur realm, id int64, reason string) {
	reviewEndpoint(cur, id, zones.Unverified, 0, reason)
}

// RemoveEndpoint deletes an endpoint. A curator may remove any. Its registrant
// may remove it only while it is unverified (a verified endpoint is a record
// other people rely on, and a flagged one is a warning, and removing and
// registering it again would wipe either one), and only ProposerEditCooldown
// blocks after registering it (removing and registering again every block
// would give it a new id faster than a curator could flag the old one).
func RemoveEndpoint(cur realm, id int64) {
	who := caller(cur)
	e, ok := reg.Endpoint(id)
	if !ok {
		panic("zones: no endpoint #" + strconv.FormatInt(id, 10))
	}
	if !curators.Has(who) {
		if e.Registrant != who {
			panic("zones: only a curator or its registrant may remove endpoint #" + strconv.FormatInt(id, 10))
		}
		if e.Status != zones.Unverified {
			panic("zones: endpoint #" + strconv.FormatInt(id, 10) + " is " + string(e.Status) +
				"; only a curator may remove it now")
		}
		if wait := e.RegisteredAt + ProposerEditCooldown - runtime.ChainHeight(); wait > 0 {
			panic("zones: endpoint #" + strconv.FormatInt(id, 10) + " was registered at block " +
				strconv.FormatInt(e.RegisteredAt, 10) + "; its registrant may withdraw it in " +
				strconv.FormatInt(wait, 10) + " blocks, so curators can review it")
		}
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
// the proof that somebody holds the key. An invitation dies with its inviter:
// removing a curator withdraws every invitation they sent.
func AddCurator(cur realm, addr address) {
	who := caller(cur)
	assertCurator(who)
	if !zones.ValidAddress(addr) {
		panic("zones: not a valid lowercase address: " + addr.String())
	}
	if curators.Has(addr) {
		panic("zones: " + addr.String() + " is already a curator")
	}
	if invited.Has(addr) {
		panic("zones: " + addr.String() + " is already invited")
	}
	if curators.Size()+invited.Size() >= MaxCurators {
		panic("zones: " + strconv.Itoa(MaxCurators) + " curators and invitations already; remove one first")
	}
	invited.Add(addr)
	inviter[addr] = who
}

// AcceptCurator makes the caller a curator, if a curator invited it.
func AcceptCurator(cur realm) {
	who := caller(cur)
	if !invited.Has(who) {
		panic("zones: " + who.String() + " has no curator invitation")
	}
	invited.Remove(who)
	delete(inviter, who)
	curators.Add(who)
}

// RemoveCurator revokes a curator, along with every invitation they sent, or
// withdraws one invitation. Only a curator may, and the last curator cannot be
// removed: a registry nobody can curate can never retire a dead zone.
//
// Curators are equals: any one may remove any other, the admin included. That
// is the trust a curator set is, and it is why there are few of them.
func RemoveCurator(cur realm, addr address) {
	assertCurator(caller(cur))
	if invited.Remove(addr) {
		delete(inviter, addr)
		return
	}
	if !curators.Has(addr) {
		panic("zones: " + addr.String() + " is not a curator")
	}
	if curators.Size() == 1 {
		panic("zones: " + addr.String() + " is the last curator")
	}
	curators.Remove(addr)
	for _, a := range Invited() {
		if inviter[a] == addr {
			invited.Remove(a)
			delete(inviter, a)
		}
	}
}

// ---- reads: plain arguments, so `gnokey query vm/qeval` can call them

// GetZone returns the zone under slug, and whether there is one.
func GetZone(slug string) (zones.Zone, bool) {
	return reg.Zone(strings.TrimSpace(slug))
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
	es := reg.Endpoints(endpointFilter(slug, kind, status))
	out := make([]string, 0, len(es))
	for _, e := range es {
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
func Curators() []address { return members(&curators) }

// Invited returns every open curator invitation, in address order.
func Invited() []address { return members(&invited) }

func members(set *addrset.Set) []address {
	out := make([]address, 0, set.Size())
	set.IterateByOffset(0, set.Size(), func(a address) bool {
		out = append(out, a)
		return false
	})
	return out
}

// ---- helpers

func review(cur realm, slug string, to zones.Status, revision int64, reason string) {
	who := caller(cur)
	assertCurator(who)
	must(reg.ReviewZone(strings.TrimSpace(slug), to, revision, who, runtime.ChainHeight(), reason))
}

func reviewEndpoint(cur realm, id int64, to zones.Verification, revision int64, reason string) {
	who := caller(cur)
	assertCurator(who)
	must(reg.ReviewEndpoint(id, to, revision, who, runtime.ChainHeight(), reason))
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

// assertCooled refuses a proposer's edit or withdrawal of a pending zone
// sooner than ProposerEditCooldown blocks after it was proposed or last edited,
// by anybody.
func assertCooled(slug string, z zones.Zone) {
	last := z.ProposedAt
	if z.EditedAt > last {
		last = z.EditedAt
	}
	if wait := last + ProposerEditCooldown - runtime.ChainHeight(); wait > 0 {
		panic("zones: " + slug + " was changed at block " + strconv.FormatInt(last, 10) +
			"; its proposer may act on it again in " + strconv.FormatInt(wait, 10) + " blocks, so curators can review it")
	}
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
