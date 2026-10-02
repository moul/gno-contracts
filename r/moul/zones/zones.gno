// untrusted-render: slugs, chain ids, URLs and peer addresses are charset-checked
// at write time by p/moul/zones; titles, descriptions, labels and reasons are a
// caller's free text and go through ui.Inline or ui.Cell at every call site.

// Package zones is a curated registry of gno.land networks: mainnet, the
// testnets, staging chains, anybody's gnodev. Each zone carries what a node or a
// wallet needs to join it (chain id, RPC, gnoweb, genesis) plus a growing list of
// endpoints: RPCs, seeds and peers, indexers, faucets, explorers.
//
// Curation is the point. Anybody may propose a zone and register endpoints on
// an approved one (on a pending one, its proposer or a curator; a zone's own
// main RPC and gnoweb, only them); a curator approves or rejects a proposal,
// retires a zone that stopped running, and verifies or flags an endpoint. The
// latest decision on each is recorded with who made it and when, and a rejection, a retirement, a flag or an edit to an
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

	"gno.land/p/moul/addrset/v1"
	"gno.land/p/moul/zones/v0"
)

// Admin is the first curator. More are invited with AddCurator and become
// curators when they accept.
const Admin address = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"

// ReviewWindow is how many blocks must pass before the author of a change may
// change it again, a rate bound rather than a review deadline (100 blocks is
// minutes): after a zone was proposed or last edited (by anybody) before its
// proposer may edit or withdraw it, and after an endpoint was registered before
// its registrant may withdraw it. Every edit bumps the revision a curator's
// decision must name, and a withdrawal plus a fresh proposal or registration
// does the same with a new revision or id, so without a wait a proposer or a
// registrant acting every block would keep their entry out of every curator's
// reach. Curators are not limited.
const ReviewWindow = 100

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
// proposal until a curator approves or rejects it. The review queue's caps
// (zones.MaxPending, zones.MaxPendingPerProposer) do not stop a curator, who
// also has the registry's last zones.ReservedForReviewers places, so neither a
// flood nor a full registry locks out the people who clear it.
//
// kind is mainnet, testnet, devnet or local. gnowebURL and genesisURL may be
// empty; rpcURL may not, and is <scheme>://<host>[:<port>] with no path, which
// is what gnokey -remote takes.
func ProposeZone(cur realm, slug, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL string) {
	who := caller(cur)
	in := info(chainID, title, description, kind, gnowebURL, rpcURL, genesisURL)
	if curators.Has(who) {
		// A flood that fills the review queue must not lock out the people
		// who clear it.
		must(reg.ProposeExempt(who, runtime.ChainHeight(), zones.TrimSpaces(slug), in))
		return
	}
	must(reg.Propose(who, runtime.ChainHeight(), zones.TrimSpaces(slug), in))
}

// EditZone replaces a zone's Info, every field but its slug and status. A
// curator may edit any pending or approved zone; the proposer may edit their
// own while it is pending. revision is the zone's Revision the edit was written
// against: it fails if the zone changed in between, its content or its status.
// Every edit bumps the revision, so a decision prepared against the old one
// fails too. A proposer edits only ReviewWindow blocks after the zone was
// proposed or last edited, and an edit that changes nothing is refused. On a
// pending zone the reason must be empty; on an approved one it is required and
// replaces the review on record, so the page names who changed the values, and
// why. A new chain id sends the zone's verified endpoints back to unverified.
// Leaving the local kind drops every endpoint on a private host, and is refused
// while one carries a curator's ruling (a verified one its registrant may
// withdraw first); the proposer's edit only drops endpoints that are theirs and
// that they could withdraw on their own (RemoveEndpoint), as for RemoveZone. A
// new main RPC or gnoweb a stranger (on an approved zone, its proposer too)
// already lists under its kind would make
// that listing the zone's own: on a curator's edit it is dropped if nobody
// ruled on it, and refuses the edit if a curator did; a proposer's edit
// refuses rather than drop what is not theirs; and a flagged listing refuses
// the edit whoever holds it. The registry validates the edit before it drops
// or resets anything, and a refusal reverts the edit with it. A rejected or
// retired zone cannot be edited.
func EditZone(cur realm, slug string, revision int64, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL, reason string) {
	who := caller(cur)
	slug = zones.TrimSpaces(slug)
	z := mustZone(slug)
	in := info(chainID, title, description, kind, gnowebURL, rpcURL, genesisURL)
	if !curators.Has(who) {
		if z.Status != zones.Pending || z.Proposer != who {
			panic("zones: only a curator, or the proposer while it is pending, may edit " + slug)
		}
		assertReviewWindow(slug, z)
		if z.Kind == zones.Local && in.Kind != zones.Local {
			// The edit would drop these; dropping is removing, under the
			// rules a removal by the proposer has.
			for _, e := range reg.PrivateEndpoints(slug) {
				if e.Registrant != who {
					panic("zones: leaving local would drop endpoint #" + strconv.FormatInt(e.ID, 10) +
						", which somebody else registered; a curator must remove it first")
				}
				assertWithdrawable(e)
			}
		}
	}
	must(reg.Edit(slug, revision, in, who, runtime.ChainHeight(), reason))
	// The reservation RegisterEndpoint keeps holds across an edit too: a new
	// main RPC or gnoweb already listed under its kind by a stranger would
	// make that listing, and its verdict, the zone's own. Checked only for a
	// URL the edit changed, after the edit, which has validated everything: a
	// refusal here reverts the edit with it, and an edit that cannot pass never
	// gets this far. On a curator's edit a stranger's listing nobody ruled on
	// is dropped, so listing a zone's likely next URL cannot hold its move
	// off; one a curator ruled on refuses the edit, and a curator removes it
	// first. A proposer's edit drops nothing that is not theirs.
	for _, own := range []struct {
		kind     zones.EndpointKind
		url, was string
	}{{zones.RPC, in.RPCURL, z.RPCURL}, {zones.Gnoweb, in.GnowebURL, z.GnowebURL}} {
		if own.url == "" || (own.was != "" && zones.Canonical(own.kind, own.url) == zones.Canonical(own.kind, own.was)) {
			continue
		}
		e, ok := reg.EndpointByAddress(slug, own.kind, own.url)
		if !ok {
			continue
		}
		if curators.Has(e.Registrant) || (z.Status == zones.Pending && e.Registrant == z.Proposer) {
			// Theirs to hold, but a flagged one would mark the zone's own URL
			// the moment it becomes one.
			if e.Status == zones.Flagged {
				panic("zones: " + own.url + " is listed under " + string(own.kind) + " as endpoint #" + strconv.FormatInt(e.ID, 10) +
					", flagged; a curator removes it or rules again before it becomes " + slug + "'s own")
			}
			continue
		}
		if !curators.Has(who) {
			// A proposer's edit (a pending zone) drops nothing that is not
			// theirs: the only other registrant there is a former curator.
			panic("zones: " + own.url + " is listed under " + string(own.kind) + " by " + e.Registrant.String() +
				" (endpoint #" + strconv.FormatInt(e.ID, 10) + "); a curator removes it before it becomes " + slug + "'s own")
		}
		if e.ReviewedBy != "" || e.Reason != "" { // a ruling, a reset's reason
			panic("zones: " + own.url + " is listed under " + string(own.kind) + " by " + e.Registrant.String() +
				" (endpoint #" + strconv.FormatInt(e.ID, 10) + "), with a curator's ruling; a curator removes it before it becomes " + slug + "'s own")
		}
		must(reg.RemoveEndpoint(e.ID, e.Revision))
	}
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
// pending, ReviewWindow blocks after it was proposed or last edited
// (so withdrawing and proposing again cannot dodge the edit wait), while every
// endpoint on it is theirs (the deposit is refunded to whoever signs the
// removal, so removing somebody else's endpoints would collect what they paid)
// and each one is one they could withdraw on its own (RemoveEndpoint):
// removing the zone must not wipe a curator's flag or unverify, or skip an endpoint's
// own wait. A rejected zone is the curators' record: only a curator removes
// it, or newer rejections push it out, and the rejection's deposit, paid by the
// curator, is not the proposer's to collect. A zone that was ever official is
// never removed this way: an approved one is retired, and a retired one is kept
// until newer retirements push it out.
func RemoveZone(cur realm, slug string, revision int64) {
	who := caller(cur)
	slug = zones.TrimSpaces(slug)
	z := mustZone(slug)
	if !curators.Has(who) {
		if z.Proposer != who || z.Status != zones.Pending {
			panic("zones: only a curator, or the proposer while it is pending, may remove " + slug)
		}
		assertReviewWindow(slug, z)
		// From the index counts first: nothing is read to answer it.
		if _, total := reg.Count(slug); reg.OwnerCount(slug, who) != total {
			panic("zones: " + slug + " carries endpoints somebody else registered; they must be removed first")
		}
		// Every endpoint is the proposer's: at most MaxEndpointsPerZone (a curator
		// who proposed it may have registered past the per-address cap).
		for _, e := range reg.Endpoints(zones.EndpointFilter{Zone: slug}) {
			assertWithdrawable(e)
		}
	}
	must(reg.RemoveZone(slug, revision))
}

// ---- registering and curating endpoints

// RegisterEndpoint lists an endpoint on a zone and returns its id. On an
// approved zone anybody may, except the zone's own main RPC under rpc and
// gnoweb under gnoweb, which only a curator lists (or the proposer while the
// zone is pending: every proposer right ends at approval); on a
// pending one only the proposer or a curator, so a stranger cannot pin a
// proposal the proposer then cannot withdraw. It shows as unverified until a
// curator checks it. A curator also registers past the review queue's caps
// and into the zones.ReservedForReviewers places a gated registration may
// not take, never past zones.MaxEndpointsPerZone.
//
// kind is rpc, gnoweb, seed, peer, indexer, faucet or explorer. addr is a
// URL, or <node id>@<host>:<port> for a seed or a peer. label is optional:
// who runs it, in your words.
func RegisterEndpoint(cur realm, slug, kind, addr, label string) int64 {
	who := caller(cur)
	slug = zones.TrimSpaces(slug)
	z := mustZone(slug)
	if z.Status == zones.Pending && z.Proposer != who && !curators.Has(who) {
		panic("zones: " + slug + " is pending; only its proposer or a curator may register on it")
	}
	k, err := zones.ParseEndpointKind(kind)
	must(err)
	addr = zones.TrimSpaces(addr) // compared as the registry will store it
	// The zone's own main RPC and gnoweb, listed under their own kind, carry
	// the verdict its page shows on them, so only a curator lists them, or the
	// proposer while the zone is pending (every proposer right ends at
	// approval): a stranger's listing, once flagged for its label, would mark
	// the zone's own URL.
	if !curators.Has(who) && !(z.Status == zones.Pending && z.Proposer == who) &&
		((k == zones.RPC && zones.Canonical(k, addr) == zones.Canonical(k, z.RPCURL)) ||
			(k == zones.Gnoweb && z.GnowebURL != "" && zones.Canonical(k, addr) == zones.Canonical(k, z.GnowebURL))) {
		panic("zones: that is " + slug + "'s own " + string(k) + "; only a curator, or its proposer while it is pending, lists it")
	}
	register := reg.Register
	if curators.Has(who) {
		register = reg.RegisterExempt // past the review queue, as ProposeZone
	}
	id, err := register(who, runtime.ChainHeight(), slug, k, addr, label)
	must(err)
	return id
}

// VerifyEndpoint marks an endpoint as checked against its zone. revision is
// the endpoint's revision as read (the endpoint table's revision column), and
// zoneRevision the zone's (the zone page shows it): the verdict fails if
// either changed since, another curator's verdict on the endpoint, or any
// edit or status change of the zone (what is verified is that it answers for
// this zone's chain id). The reason is optional. Each verdict may be given
// again with a new reason, to restate it.
func VerifyEndpoint(cur realm, id, zoneRevision, revision int64, reason string) {
	reviewEndpoint(cur, id, zones.Verified, zoneRevision, revision, reason)
}

// FlagEndpoint tells readers not to use an endpoint. The reason is required.
// revision is the endpoint's, as for VerifyEndpoint; a flag is not bound to
// the zone, so editing the zone cannot hold off a warning.
func FlagEndpoint(cur realm, id, revision int64, reason string) {
	reviewEndpoint(cur, id, zones.Flagged, 0, revision, reason)
}

// UnverifyEndpoint puts an endpoint back to unverified, for one that changed
// hands or needs checking again. revision is as for FlagEndpoint.
func UnverifyEndpoint(cur realm, id, revision int64, reason string) {
	reviewEndpoint(cur, id, zones.Unverified, 0, revision, reason)
}

// RemoveEndpoint deletes an endpoint. revision is its revision as read: the
// removal fails if a verdict landed since, rather than delete one nobody saw. A
// curator may remove any. Its registrant may remove it unless a curator flagged
// or unverified it (a flag is a warning, an unverify carries why, and removing
// and registering it again would wipe either; a verified one the registrant may
// take down, since listing it again starts it unverified, and so one a reset
// sent back to unverified, since the reset says the zone changed, not it), only while its zone is pending or approved (a rejected
// or retired zone is a record, endpoints and all), and only ReviewWindow blocks
// after registering it (removing and registering again every block would give
// it a new id faster than a curator could flag the old one).
func RemoveEndpoint(cur realm, id, revision int64) {
	who := caller(cur)
	e, ok := reg.Endpoint(id)
	if !ok {
		panic("zones: no endpoint #" + strconv.FormatInt(id, 10))
	}
	if !curators.Has(who) {
		if e.Registrant != who {
			panic("zones: only a curator or its registrant may remove endpoint #" + strconv.FormatInt(id, 10))
		}
		if z := mustZone(e.Zone); z.Status != zones.Pending && z.Status != zones.Approved {
			panic("zones: " + z.Slug + " is " + string(z.Status) + ", a record; only a curator may remove its endpoints")
		}
		assertWithdrawable(e)
	}
	must(reg.RemoveEndpoint(id, revision))
}

// ClearUnreviewed removes, in one call, every endpoint on a zone that is
// zones.Endpoint.Clearable (nobody ruled on it, and no reviewer registered it
// past the caps), and returns how many. There are never more than
// zones.MaxUnverifiedPerZone: clearable endpoints are a part of the review
// queue its gate holds there, and no reset makes one. It is the answer to a
// flood that cycles: registrants who withdraw and register again each review
// window keep the queue full, and one removal per transaction lets them refill
// it before a curator is done. throughRevision bounds it to what the curator
// read: an endpoint registered after it (a later Revision) is kept. The
// deposits go to the curator who signs. At most zones.MaxEndpointsPerZone are
// read.
func ClearUnreviewed(cur realm, slug string, throughRevision int64) int {
	who := caller(cur)
	assertCurator(who)
	slug = zones.TrimSpaces(slug)
	mustZone(slug)
	n := 0
	for _, e := range reg.Endpoints(zones.EndpointFilter{Zone: slug, Status: zones.Unverified}) {
		if e.Clearable() && e.Revision <= throughRevision {
			must(reg.RemoveEndpoint(e.ID, e.Revision))
			n++
		}
	}
	return n
}

// assertWithdrawable refuses a non-curator's withdrawal of an endpoint a
// curator flagged or unverified, or one registered less than ReviewWindow
// blocks ago. Shared by RemoveEndpoint, the proposer's RemoveZone and the
// proposer's edit off local, so none can do what another refuses.
func assertWithdrawable(e zones.Endpoint) {
	id := strconv.FormatInt(e.ID, 10)
	// A verification guards nothing a withdrawal could erase: the registrant
	// takes down a node that is going away, and listing it again starts it
	// unverified. A flag, or an unverify a curator wrote (a reviewer or a
	// reason), is a warning, and removing and registering it again would wipe
	// it. A reset is not: it reaches only a verified endpoint and says the zone
	// changed, not the endpoint, so it leaves the withdrawal a verified one had.
	if e.Status == zones.Flagged || (e.Status == zones.Unverified && (e.ReviewedBy != "" || e.Reason != "") && !zones.IsReset(e)) {
		panic("zones: a curator ruled on endpoint #" + id + "; only a curator may remove it now")
	}
	if wait := e.RegisteredAt + ReviewWindow - runtime.ChainHeight(); wait > 0 {
		panic("zones: endpoint #" + id + " was registered at block " +
			strconv.FormatInt(e.RegisteredAt, 10) + "; it may be withdrawn in " +
			strconv.FormatInt(wait, 10) + " blocks, so curators can review it")
	}
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
	return reg.Zone(zones.TrimSpaces(slug))
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
	must(reg.ReviewZone(zones.TrimSpaces(slug), to, revision, who, runtime.ChainHeight(), reason))
}

func reviewEndpoint(cur realm, id int64, to zones.Verification, zoneRevision, revision int64, reason string) {
	who := caller(cur)
	assertCurator(who)
	must(reg.ReviewEndpoint(id, to, zoneRevision, revision, who, runtime.ChainHeight(), reason))
}

func endpointFilter(slug, kind, status string) zones.EndpointFilter {
	slug = zones.TrimSpaces(slug)
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
		ChainID:     zones.TrimSpaces(chainID),
		Title:       zones.TrimSpaces(title),
		Description: zones.TrimSpaces(description),
		Kind:        k,
		GnowebURL:   zones.TrimSpaces(gnowebURL),
		RPCURL:      zones.TrimSpaces(rpcURL),
		GenesisURL:  zones.TrimSpaces(genesisURL),
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

// assertReviewWindow refuses a proposer's edit or withdrawal of a pending zone
// sooner than ReviewWindow blocks after it was proposed or last edited,
// by anybody.
func assertReviewWindow(slug string, z zones.Zone) {
	last := z.ProposedAt
	if z.EditedAt > last {
		last = z.EditedAt
	}
	if wait := last + ReviewWindow - runtime.ChainHeight(); wait > 0 {
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
