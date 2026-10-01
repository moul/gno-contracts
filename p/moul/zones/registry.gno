package zones

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/index/v0"
	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/bptree/v0"
)

// Bounds on what the registry holds.
//
// The LIVE registry, pending and approved zones, has a hard cap. Rejected and
// retired zones are kept for the record but do not count against it: each has
// a cap of its own, and when it is reached the zone proposed longest ago in
// that state is dropped to make room. So nothing a proposer or a curator does,
// and no amount of time, can fill the registry for good: a cap that only ever
// fills is a lifetime cap, and on an immutable path that is a brick.
//
// The per-address caps make one address cheap to ignore. Neither stops a flood
// from many addresses, because an address is not an identity, so the review
// queue has a ceiling of its own (MaxPending zones, MaxUnverifiedPerZone
// endpoints), well under the hard caps: a flood fills the queue and never
// crowds out an approved zone or a verified endpoint. Clearing the queue is
// RemoveZone, RemoveEndpoint and rejection. Each entry costs its sender a
// storage deposit, refunded to whoever signs the transaction that frees it, so
// a flooder who withdraws first gets it back: a bond, not a fee.
const (
	MaxZones               = 256 // pending and approved zones together
	MaxPending             = 64  // zones awaiting review, all proposers together
	MaxPendingPerProposer  = 4   // open proposals one address may have at once
	MaxRejected            = 64  // rejected zones kept for the record
	MaxRetired             = 128 // retired zones kept for the record
	MaxEndpointsPerZone    = 128
	MaxUnverifiedPerZone   = 64 // endpoints on one zone that are not verified: unverified or flagged
	MaxEndpointsPerAddress = 16 // endpoints one address may register on one zone
)

// The reasons an endpoint carries when its zone changed under it and sent it
// back to unverified. Such a reset is the registry's doing, not a curator's
// verdict, so it records no reviewer: ReviewedBy is empty and Reason says why.
const (
	ChainIDChanged = "the zone's chain id changed; verify again"
	ZoneRetired    = "the zone was retired; verify again if it returns"
	ZoneRejected   = "the zone was rejected"
)

// fanout is the B+ tree fanout for every container this package builds itself:
// 128, the cheapest point EFFECTIVE_GNO.md measured (592 B per entry).
const fanout = 128

// Registry holds the zones and their endpoints. The zero value is not usable:
// call [NewRegistry].
//
// Every write touches its record and all of that record's indexes in one
// method. The index writes cannot fail as written: every key is validated
// non-empty and every unique key is checked free before the first write. If a
// later change made one fail, the method returns the error and the holding
// realm's abort undoes the half-applied write; that abort, not this method, is
// the atomicity guarantee.
type Registry struct {
	rev uint64 // last Revision handed out, registry-wide, so never reused

	zones      *table
	bySlug     *unique      // slug -> zone id
	byStatus   *index.Index // status -> zone ids, so a page reads only its rows
	byProposer *index.Index // proposer -> ids of their PENDING zones
	approved   *index.Index // chain id -> ids of APPROVED zones naming it

	endpoints *table
	byAddress *unique      // slug|kind|hash(canonical address) -> endpoint id
	byZone    *index.Index // slug -> endpoint ids
	byKind    *index.Index // slug|kind -> endpoint ids, so a page reads only its rows
	byOwner   *index.Index // slug|registrant -> endpoint ids
	unchecked *index.Index // slug -> ids of endpoints that are not Verified
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{
		zones:      newTable(),
		bySlug:     newUnique(),
		byStatus:   index.New(),
		byProposer: index.New(),
		approved:   index.New(),
		endpoints:  newTable(),
		byAddress:  newUnique(),
		byZone:     index.New(),
		byKind:     index.New(),
		byOwner:    index.New(),
		unchecked:  index.New(),
	}
}

// Propose files a new zone, Pending, under a slug nobody holds.
func (r *Registry) Propose(by address, at int64, slug string, in Info) error {
	in = trimInfo(in)
	if err := ValidateSlug(slug); err != nil {
		return err
	}
	if err := ValidateInfo(in); err != nil {
		return err
	}
	if !ValidAddress(by) {
		return errors.New("zones: the proposer is not a valid lowercase address")
	}
	if r.bySlug.has(slug) {
		return errors.New("zones: the slug " + strconv.Quote(slug) + " is taken")
	}
	if r.Live() >= MaxZones {
		return errors.New("zones: the registry is full at " + strconv.Itoa(MaxZones) + " pending and approved zones")
	}
	if r.byProposer.Len() >= MaxPending {
		return errors.New("zones: " + strconv.Itoa(MaxPending) + " proposals are already waiting for review; try again once a curator has cleared some")
	}
	if n := r.byProposer.Count(by.String()); n >= MaxPendingPerProposer {
		return errors.New("zones: " + by.String() + " already has " + strconv.Itoa(n) +
			" pending proposals, the limit is " + strconv.Itoa(MaxPendingPerProposer))
	}
	r.rev++
	z := &Zone{Slug: slug, Status: Pending, Proposer: by, ProposedAt: at, Revision: int64(r.rev)}
	z.setInfo(in)
	id := r.zones.add(z)
	r.bySlug.set(slug, id)
	if err := r.byStatus.Add(string(Pending), id); err != nil {
		return err
	}
	return r.byProposer.Add(by.String(), id)
}

// Edit replaces a zone's Info: every field but the slug and the status.
//
// Only a pending or an approved zone can be edited. A rejected one is removed
// and proposed again, or approved first; a retired one is a record, and its
// retirement reason is the thing it is kept for.
//
// Every edit bumps the zone's Revision and records who made it and when. On a
// pending zone that is all, and a reason is refused rather than silently
// dropped: nobody has reviewed anything yet. On an approved zone an edit is a
// curator decision of its own: the reviewed values changed, so the review on
// record is replaced by this one, with a reason required.
//
// When the chain id changes, whatever the status, every endpoint verified
// against the old one goes back to unverified: what was verified was that it
// answered for a chain this zone no longer names. On a pending zone that reset
// records no reviewer, because the proposer is not one.
func (r *Registry) Edit(slug string, in Info, by address, at int64, reason string) error {
	z, zid, err := r.zone(slug)
	if err != nil {
		return err
	}
	if z.Status != Pending && z.Status != Approved {
		return errors.New("zones: " + slug + " is " + string(z.Status) + "; only a pending or approved zone can be edited")
	}
	in = trimInfo(in)
	if err := ValidateInfo(in); err != nil {
		return err
	}
	if !ValidAddress(by) {
		return errors.New("zones: the editor is not a valid lowercase address")
	}
	reason = strings.TrimSpace(reason)
	if err := ValidateReason(reason); err != nil {
		return err
	}
	switch {
	case z.Status == Pending && reason != "":
		return errors.New("zones: " + slug + " is pending, and an edit before review takes no reason")
	case z.Status == Approved && !HasVisible(reason):
		return errors.New("zones: " + slug + " is approved, so an edit needs a reason")
	}
	if in.ChainID != z.ChainID {
		resetBy := address("")
		if z.Status == Approved {
			resetBy = by
			r.approved.Remove(z.ChainID, zid)
			if err := r.approved.Add(in.ChainID, zid); err != nil {
				return err
			}
		}
		if err := r.unverifyAll(slug, resetBy, at, ChainIDChanged); err != nil {
			return err
		}
	}
	if z.Status == Approved {
		z.ReviewedBy, z.ReviewedAt, z.Reason = by, at, reason
	}
	r.rev++
	z.Revision = int64(r.rev)
	z.EditedBy, z.EditedAt = by, at
	z.setInfo(in)
	return nil
}

// ReviewZone records a curator's decision on a zone.
//
// The transitions are the curation policy, and they are deliberately few:
//
//	approve  from pending, rejected or retired   reason optional, revision REQUIRED
//	reject   from pending                        reason REQUIRED
//	retire   from approved                       reason REQUIRED
//
// An approval names the zone's Revision the curator read, and fails if the zone
// changed since: otherwise a proposer's edit landing just before the approval
// would become official under the curator's name.
//
// Rejecting or retiring sends every verified endpoint back to unverified: a
// rejected zone was never vouched for, and a retired network's peers may be
// somebody else's hosts by the time anyone reads them. Each state keeps at most
// MaxRejected or MaxRetired zones; the next one in drops the zone proposed
// longest ago in that state, with its endpoints.
//
// Nothing goes back to pending: a proposer who disagrees with a rejection
// removes the zone and proposes it again. An official zone is never rejected
// after the fact, it is retired, so the record of it having been official
// survives.
func (r *Registry) ReviewZone(slug string, to Status, revision int64, by address, at int64, reason string) error {
	z, id, err := r.zone(slug)
	if err != nil {
		return err
	}
	if !ValidAddress(by) {
		return errors.New("zones: the reviewer is not a valid lowercase address")
	}
	reason = strings.TrimSpace(reason)
	if err := ValidateReason(reason); err != nil {
		return err
	}
	if z.Status == to {
		return errors.New("zones: " + slug + " is already " + string(to))
	}
	switch to {
	case Approved:
		if revision != z.Revision {
			return errors.New("zones: " + slug + " changed since you read it: it is at revision " +
				strconv.FormatInt(z.Revision, 10) + ", you approved revision " + strconv.FormatInt(revision, 10) +
				"; read it again")
		}
		if z.Status != Pending && r.Live() >= MaxZones {
			return errors.New("zones: the registry is full at " + strconv.Itoa(MaxZones) + " pending and approved zones")
		}
	case Rejected:
		if z.Status == Approved {
			return errors.New("zones: " + slug + " is approved; retire it instead of rejecting it")
		}
		if z.Status != Pending {
			return errors.New("zones: only a pending zone can be rejected; " + slug + " is " + string(z.Status))
		}
	case Retired:
		if z.Status != Approved {
			return errors.New("zones: only an approved zone can be retired; " + slug + " is " + string(z.Status))
		}
	default:
		return errors.New("zones: a review cannot set a zone to " + strconv.Quote(string(to)))
	}
	if (to == Rejected || to == Retired) && !HasVisible(reason) {
		return errors.New("zones: " + string(to) + " needs a reason")
	}
	switch to {
	case Rejected:
		if err := r.unverifyAll(slug, by, at, ZoneRejected); err != nil {
			return err
		}
		r.makeRoom(Rejected, MaxRejected)
	case Retired:
		if err := r.unverifyAll(slug, by, at, ZoneRetired); err != nil {
			return err
		}
		r.makeRoom(Retired, MaxRetired)
	}
	if z.Status == Pending {
		r.byProposer.Remove(z.Proposer.String(), id)
	}
	if z.Status == Approved {
		r.approved.Remove(z.ChainID, id)
	}
	if to == Approved {
		if err := r.approved.Add(z.ChainID, id); err != nil {
			return err
		}
	}
	r.byStatus.Remove(string(z.Status), id)
	if err := r.byStatus.Add(string(to), id); err != nil {
		return err
	}
	z.Status = to
	z.ReviewedBy, z.ReviewedAt, z.Reason = by, at, reason
	return nil
}

// makeRoom drops the zone proposed longest ago in that state when the state is
// at its cap, so the one about to enter fits.
func (r *Registry) makeRoom(status Status, max int) {
	for r.byStatus.Count(string(status)) >= max {
		ids := r.byStatus.Lookup(string(status))
		v, _ := r.zones.get(ids[0])
		r.removeZone(v.(*Zone), ids[0])
	}
}

// RemoveZone deletes a pending or rejected zone and every endpoint registered
// on it, freeing their storage deposit to whoever signs the removal. A zone
// that has ever been official cannot be removed: an approved one is retired,
// and a retired one is kept, so whoever still holds its chain id can find out
// what happened to it.
func (r *Registry) RemoveZone(slug string) error {
	z, id, err := r.zone(slug)
	if err != nil {
		return err
	}
	if z.Status == Approved {
		return errors.New("zones: " + slug + " is approved; retire it instead of removing it")
	}
	if z.Status == Retired {
		return errors.New("zones: " + slug + " is retired, and a retired zone is kept on record")
	}
	r.removeZone(z, id)
	return nil
}

// removeZone unwinds a zone, its endpoints and every index. The per-zone index
// keys go in one RemoveKey each rather than an id at a time, which would copy
// the bucket once per endpoint.
func (r *Registry) removeZone(z *Zone, id store.ID) {
	slug := z.Slug
	for _, eid := range r.byZone.Lookup(slug) {
		v, ok := r.endpoints.remove(eid)
		if !ok {
			continue
		}
		e := v.(*Endpoint)
		r.byAddress.remove(addressKey(slug, e.Kind, e.Address))
		r.byOwner.Remove(ownerKey(slug, e.Registrant), eid)
	}
	r.byZone.RemoveKey(slug)
	r.unchecked.RemoveKey(slug)
	for _, k := range EndpointKinds() {
		r.byKind.RemoveKey(kindKey(slug, k))
	}
	if z.Status == Pending {
		r.byProposer.Remove(z.Proposer.String(), id)
	}
	if z.Status == Approved {
		r.approved.Remove(z.ChainID, id)
	}
	r.bySlug.remove(slug)
	r.byStatus.Remove(string(z.Status), id)
	r.zones.remove(id)
}

// Register adds an endpoint to a zone, Unverified, and returns its id.
//
// A zone takes endpoints while it is pending or approved, and a rejected or
// retired zone takes none. Who may register on a pending zone is the holding
// realm's call; the address is stored in its canonical spelling (scheme
// lowercased, a peer lowercased whole) so what is listed is what dials.
func (r *Registry) Register(by address, at int64, slug string, kind EndpointKind, addr, label string) (int64, error) {
	z, _, err := r.zone(slug)
	if err != nil {
		return 0, err
	}
	if z.Status != Pending && z.Status != Approved {
		return 0, errors.New("zones: " + slug + " is " + string(z.Status) + " and takes no endpoints")
	}
	addr = strings.TrimSpace(addr)
	label = strings.TrimSpace(label)
	if err := ValidateEndpoint(kind, addr); err != nil {
		return 0, err
	}
	if kind == Seed || kind == Peer {
		addr = strings.ToLower(addr)
	} else {
		addr = lowerScheme(addr)
	}
	if err := ValidateLabel(label); err != nil {
		return 0, err
	}
	if !ValidAddress(by) {
		return 0, errors.New("zones: the registrant is not a valid lowercase address")
	}
	akey := addressKey(slug, kind, addr)
	if r.byAddress.has(akey) {
		return 0, errors.New("zones: " + slug + " already lists that " + string(kind) + ": " + addr)
	}
	if n := r.byZone.Count(slug); n >= MaxEndpointsPerZone {
		return 0, errors.New("zones: " + slug + " is full at " + strconv.Itoa(MaxEndpointsPerZone) + " endpoints")
	}
	if n := r.unchecked.Count(slug); n >= MaxUnverifiedPerZone {
		return 0, errors.New("zones: " + slug + " already has " + strconv.Itoa(n) +
			" endpoints waiting for review; try again once a curator has cleared some")
	}
	okey := ownerKey(slug, by)
	if n := r.byOwner.Count(okey); n >= MaxEndpointsPerAddress {
		return 0, errors.New("zones: " + by.String() + " already registered " + strconv.Itoa(n) +
			" endpoints on " + slug + ", the limit is " + strconv.Itoa(MaxEndpointsPerAddress))
	}
	e := &Endpoint{Zone: slug, Kind: kind, Address: addr, Label: label, Registrant: by, RegisteredAt: at, Status: Unverified}
	id := r.endpoints.add(e)
	e.ID = int64(id)
	r.byAddress.set(akey, id)
	if err := r.byZone.Add(slug, id); err != nil {
		return 0, err
	}
	if err := r.byKind.Add(kindKey(slug, kind), id); err != nil {
		return 0, err
	}
	if err := r.byOwner.Add(okey, id); err != nil {
		return 0, err
	}
	if err := r.unchecked.Add(slug, id); err != nil {
		return 0, err
	}
	return e.ID, nil
}

// ReviewEndpoint records a curator's verdict on an endpoint. Any verdict may
// follow any other, with three rules:
//
//   - flagging needs a reason, because "do not use this" with no why is not
//     something an operator can act on;
//   - verifying names the zone's Revision the curator checked against, and
//     fails if the zone changed since: what is verified is that the endpoint
//     answers for THIS zone's chain id, and a proposer could otherwise switch
//     it while the verdict is in flight;
//   - only an endpoint of a pending or approved zone can be verified.
func (r *Registry) ReviewEndpoint(id int64, to Verification, revision int64, by address, at int64, reason string) error {
	e, err := r.endpoint(id)
	if err != nil {
		return err
	}
	if !ValidAddress(by) {
		return errors.New("zones: the reviewer is not a valid lowercase address")
	}
	reason = strings.TrimSpace(reason)
	if err := ValidateReason(reason); err != nil {
		return err
	}
	switch to {
	case Unverified, Verified, Flagged:
	case "":
		return errors.New("zones: a review needs a verdict")
	default:
		// Exact values only: ParseVerification trims, and a " verified " stored
		// as written would match no filter and count as unverified forever.
		return errors.New("zones: unknown verification " + strconv.Quote(string(to)) + ", want verified, unverified or flagged")
	}
	if e.Status == to {
		return errors.New("zones: endpoint #" + strconv.FormatInt(id, 10) + " is already " + string(to))
	}
	if to == Flagged && !HasVisible(reason) {
		return errors.New("zones: flagging an endpoint needs a reason")
	}
	if to == Verified {
		z, _, err := r.zone(e.Zone)
		if err != nil {
			return err
		}
		if z.Status != Pending && z.Status != Approved {
			return errors.New("zones: " + z.Slug + " is " + string(z.Status) + "; nothing on it can be verified")
		}
		if revision != z.Revision {
			return errors.New("zones: " + z.Slug + " changed since you checked it: it is at revision " +
				strconv.FormatInt(z.Revision, 10) + ", you verified against revision " + strconv.FormatInt(revision, 10))
		}
	}
	sid := store.ID(id)
	if to == Verified {
		r.unchecked.Remove(e.Zone, sid)
	} else if e.Status == Verified {
		if err := r.unchecked.Add(e.Zone, sid); err != nil {
			return err
		}
	}
	e.Status = to
	e.ReviewedBy, e.ReviewedAt, e.Reason = by, at, reason
	return nil
}

// unverifyAll sends every verified endpoint of a zone back to unverified with
// that reason, and by as the reviewer ("" when the reset is the registry's own
// doing). Flagged ones keep their flag. Only the verified ones are read: their
// ids are the zone's ids minus the unchecked ones, both kept ascending, so one
// merge pass finds them without loading the rest.
func (r *Registry) unverifyAll(slug string, by address, at int64, reason string) error {
	all := r.byZone.Lookup(slug)
	skip := r.unchecked.Lookup(slug)
	j := 0
	for _, id := range all {
		for j < len(skip) && skip[j] < id {
			j++
		}
		if j < len(skip) && skip[j] == id {
			continue
		}
		v, ok := r.endpoints.get(id)
		if !ok {
			continue
		}
		e := v.(*Endpoint)
		if err := r.unchecked.Add(slug, id); err != nil {
			return err
		}
		e.Status = Unverified
		e.ReviewedBy, e.ReviewedAt, e.Reason = by, at, reason
	}
	return nil
}

// RemoveEndpoint deletes an endpoint, freeing its storage deposit to whoever
// signs the removal. Who may is the holding realm's call.
func (r *Registry) RemoveEndpoint(id int64) error {
	if _, err := r.endpoint(id); err != nil {
		return err
	}
	r.removeEndpoint(store.ID(id))
	return nil
}

// removeEndpoint unwinds the record and all five of its indexes together.
func (r *Registry) removeEndpoint(id store.ID) {
	v, ok := r.endpoints.remove(id)
	if !ok {
		return
	}
	e := v.(*Endpoint)
	r.byAddress.remove(addressKey(e.Zone, e.Kind, e.Address))
	r.byZone.Remove(e.Zone, id)
	r.byKind.Remove(kindKey(e.Zone, e.Kind), id)
	r.byOwner.Remove(ownerKey(e.Zone, e.Registrant), id)
	r.unchecked.Remove(e.Zone, id)
}

// Zone returns a copy of the zone under slug.
func (r *Registry) Zone(slug string) (Zone, bool) {
	z, _, err := r.zone(slug)
	if err != nil {
		return Zone{}, false
	}
	return *z, true
}

// Endpoint returns a copy of the endpoint with that id.
func (r *Registry) Endpoint(id int64) (Endpoint, bool) {
	e, err := r.endpoint(id)
	if err != nil {
		return Endpoint{}, false
	}
	return *e, true
}

// EndpointByAddress returns a copy of the endpoint a zone lists under that kind
// and address, compared in [Canonical] form.
func (r *Registry) EndpointByAddress(slug string, kind EndpointKind, addr string) (Endpoint, bool) {
	id, ok := r.byAddress.get(addressKey(slug, kind, addr))
	if !ok {
		return Endpoint{}, false
	}
	v, ok := r.endpoints.get(id)
	if !ok {
		return Endpoint{}, false
	}
	return *v.(*Endpoint), true
}

// ZoneFilter selects zones. A zero field matches anything.
type ZoneFilter struct {
	Status Status
	Kind   Kind
}

// Match reports whether z passes the filter.
func (f ZoneFilter) Match(z Zone) bool {
	return (f.Status == "" || z.Status == f.Status) && (f.Kind == "" || z.Kind == f.Kind)
}

// Zones returns copies of the zones passing f, in the order they were
// proposed. With a status set it reads that status's zones only.
func (r *Registry) Zones(f ZoneFilter) []Zone {
	if f.Status != "" {
		ids := r.byStatus.Lookup(string(f.Status))
		out := make([]Zone, 0, len(ids))
		for _, id := range ids {
			v, _ := r.zones.get(id)
			if z := v.(*Zone); f.Match(*z) {
				out = append(out, *z)
			}
		}
		return out
	}
	out := make([]Zone, 0, r.zones.len())
	r.zones.each(func(v any) {
		if z := v.(*Zone); f.Match(*z) {
			out = append(out, *z)
		}
	})
	return out
}

// ZoneCount returns how many zones have that status ("" for all), without
// reading any.
func (r *Registry) ZoneCount(status Status) int {
	if status == "" {
		return r.zones.len()
	}
	return r.byStatus.Count(string(status))
}

// Live returns how many zones are pending or approved: what MaxZones bounds.
func (r *Registry) Live() int {
	return r.byStatus.Count(string(Pending)) + r.byStatus.Count(string(Approved))
}

// ZonePage returns page (1-based) of the zones with that status ("" for every
// status), size per page, in proposal order. A page past the end is empty.
//
// It reads the zones ON the page only; the status's id list (one object, at
// most MaxZones ids) is read whole and sliced.
func (r *Registry) ZonePage(status Status, page, size int) []Zone {
	if status == "" {
		n := r.zones.len()
		if page < 1 || size < 1 || page-1 > n/size {
			return []Zone{}
		}
		if size > n {
			size = n
		}
		out := make([]Zone, 0, size)
		r.zones.page((page-1)*size, size, func(v any) { out = append(out, *v.(*Zone)) })
		return out
	}
	ids := pageOf(r.byStatus.Lookup(string(status)), page, size)
	out := make([]Zone, 0, len(ids))
	for _, id := range ids {
		v, _ := r.zones.get(id)
		out = append(out, *v.(*Zone))
	}
	return out
}

// ApprovedByChainID returns the approved zones naming that chain id, in
// proposal order. Usually one, but chain ids are not unique across networks
// (every gnodev is "dev"), so it is a list. Only approved zones are indexed, so
// proposals naming a real chain id cost a reader of this nothing.
func (r *Registry) ApprovedByChainID(chainID string) []Zone {
	ids := r.approved.Lookup(chainID)
	out := make([]Zone, 0, len(ids))
	for _, id := range ids {
		v, _ := r.zones.get(id)
		out = append(out, *v.(*Zone))
	}
	return out
}

// EndpointFilter selects endpoints. A zero field matches anything.
type EndpointFilter struct {
	Zone       string
	Kind       EndpointKind
	Status     Verification
	Registrant address
}

// Match reports whether e passes the filter.
func (f EndpointFilter) Match(e Endpoint) bool {
	return (f.Zone == "" || e.Zone == f.Zone) &&
		(f.Kind == "" || e.Kind == f.Kind) &&
		(f.Status == "" || e.Status == f.Status) &&
		(f.Registrant == "" || e.Registrant == f.Registrant)
}

// Endpoints returns copies of the endpoints passing f, oldest first. With a
// zone set it reads that zone's ids only (that kind's, with a kind set), so it
// costs at most MaxEndpointsPerZone records. Without one it reads every
// endpoint in the registry: bound it yourself.
func (r *Registry) Endpoints(f EndpointFilter) []Endpoint {
	if f.Zone != "" {
		ids := r.byZone.Lookup(f.Zone)
		if f.Kind != "" {
			ids = r.byKind.Lookup(kindKey(f.Zone, f.Kind))
		}
		out := make([]Endpoint, 0, len(ids))
		for _, id := range ids {
			v, _ := r.endpoints.get(id)
			if e := v.(*Endpoint); f.Match(*e) {
				out = append(out, *e)
			}
		}
		return out
	}
	out := make([]Endpoint, 0, r.endpoints.len())
	r.endpoints.each(func(v any) {
		if e := v.(*Endpoint); f.Match(*e) {
			out = append(out, *e)
		}
	})
	return out
}

// Count returns how many endpoints a zone has, and how many of them are
// verified, from the index counts: no endpoint is read.
func (r *Registry) Count(slug string) (verified, total int) {
	total = r.byZone.Count(slug)
	return total - r.unchecked.Count(slug), total
}

// EndpointCount returns how many endpoints of that kind a zone has; "" is
// every kind. No endpoint is read.
func (r *Registry) EndpointCount(slug string, kind EndpointKind) int {
	if kind == "" {
		return r.byZone.Count(slug)
	}
	return r.byKind.Count(kindKey(slug, kind))
}

// OwnerCount returns how many endpoints that address registered on a zone. No
// endpoint is read.
func (r *Registry) OwnerCount(slug string, who address) int {
	return r.byOwner.Count(ownerKey(slug, who))
}

// EndpointPage returns page (1-based) of a zone's endpoints of that kind, ""
// for every kind, size per page, oldest first. Like [Registry.ZonePage] it reads
// the records on the page only, and the bucket's id list (at most
// MaxEndpointsPerZone ids) whole.
func (r *Registry) EndpointPage(slug string, kind EndpointKind, page, size int) []Endpoint {
	ids := r.byZone.Lookup(slug)
	if kind != "" {
		ids = r.byKind.Lookup(kindKey(slug, kind))
	}
	ids = pageOf(ids, page, size)
	out := make([]Endpoint, 0, len(ids))
	for _, id := range ids {
		v, _ := r.endpoints.get(id)
		out = append(out, *v.(*Endpoint))
	}
	return out
}

// pageOf slices ids to one page, 1-based. Out of range is empty, never a
// panic: page and size usually come from a reader's query string.
func pageOf(ids []store.ID, page, size int) []store.ID {
	// The division comes first so a page number near MaxInt cannot overflow
	// the multiplication into a small positive offset.
	if page < 1 || size < 1 || page-1 > len(ids)/size {
		return nil
	}
	start := (page - 1) * size
	if start >= len(ids) {
		return nil
	}
	end := len(ids)
	if len(ids)-start > size {
		end = start + size
	}
	return ids[start:end]
}

// Len returns how many zones the registry holds, whatever their status.
func (r *Registry) Len() int { return r.zones.len() }

func (r *Registry) zone(slug string) (*Zone, store.ID, error) {
	id, ok := r.bySlug.get(slug)
	if !ok {
		return nil, 0, errors.New("zones: no zone " + strconv.Quote(slug))
	}
	v, _ := r.zones.get(id)
	return v.(*Zone), id, nil
}

func (r *Registry) endpoint(id int64) (*Endpoint, error) {
	if id <= 0 {
		return nil, errors.New("zones: no endpoint #" + strconv.FormatInt(id, 10))
	}
	v, ok := r.endpoints.get(store.ID(id))
	if !ok {
		return nil, errors.New("zones: no endpoint #" + strconv.FormatInt(id, 10))
	}
	return v.(*Endpoint), nil
}

// addressKey is the dedup key: the zone, the kind, and a hash of the address
// in [Canonical] form. Hashed so the key is 32 bytes whatever the URL's length,
// instead of a second copy of up to MaxURLLen bytes the record already holds.
// Truncated to 128 bits, which no accidental collision reaches and which only
// lets a deliberate one refuse its own registration.
func addressKey(slug string, kind EndpointKind, addr string) string {
	sum := sha256.Sum256([]byte(Canonical(kind, addr)))
	return slug + "|" + string(kind) + "|" + hex.EncodeToString(sum[:16])
}

func kindKey(slug string, kind EndpointKind) string { return slug + "|" + string(kind) }

func ownerKey(slug string, who address) string { return slug + "|" + who.String() }

// trimInfo normalizes what a caller typed before it is validated: spaces
// around every field, and each URL's scheme lowercased (a scheme is
// case-insensitive, gno's link sanitizer is not, so HTTPS:// would render as a
// dead link). Nothing else is rewritten: what fails validation is refused, not
// repaired.
func trimInfo(in Info) Info {
	in.ChainID = strings.TrimSpace(in.ChainID)
	in.Title = strings.TrimSpace(in.Title)
	in.Description = strings.TrimSpace(in.Description)
	in.Kind = Kind(strings.TrimSpace(string(in.Kind)))
	in.GnowebURL = lowerScheme(strings.TrimSpace(in.GnowebURL))
	in.RPCURL = lowerScheme(strings.TrimSpace(in.RPCURL))
	in.GenesisURL = lowerScheme(strings.TrimSpace(in.GenesisURL))
	return in
}

// table is numbered records in a B+ tree at fanout 128: kit/store's shape (an
// id that is never reused, keyed by its seqid encoding so the tree iterates in
// id order) on the container EFFECTIVE_GNO.md measured cheapest. kit/store/v0
// sits on an avl, about 1.4 KB more per entry and about six times the object
// reads to walk a zone's endpoints, and on an immutable path that choice is
// permanent.
type table struct {
	tree *bptree.BPTree
	last uint64
}

func newTable() *table { return &table{tree: bptree.NewBPTreeN(fanout)} }

func (t *table) add(v any) store.ID {
	t.last++
	id := store.ID(t.last)
	t.tree.Set(id.Key(), v)
	return id
}

func (t *table) get(id store.ID) (any, bool) {
	v := t.tree.Get(id.Key())
	return v, v != nil
}

func (t *table) remove(id store.ID) (any, bool) { return t.tree.Remove(id.Key()) }

func (t *table) len() int { return t.tree.Size() }

func (t *table) each(fn func(v any)) {
	t.tree.IterateByOffset(0, t.tree.Size(), func(_ string, v any) bool {
		fn(v)
		return false
	})
}

func (t *table) page(offset, count int, fn func(v any)) {
	t.tree.IterateByOffset(offset, count, func(_ string, v any) bool {
		fn(v)
		return false
	})
}

// unique is a key -> id map in a B+ tree that holds the id itself. kit/index
// wraps every key's ids in a pointer to a struct holding a slice, which for a
// key that only ever has one id is about 1.2 KB of structure to say so.
type unique struct{ tree *bptree.BPTree }

func newUnique() *unique { return &unique{tree: bptree.NewBPTreeN(fanout)} }

func (u *unique) has(key string) bool { return u.tree.Has(key) }

func (u *unique) get(key string) (store.ID, bool) {
	v := u.tree.Get(key)
	if v == nil {
		return 0, false
	}
	return v.(store.ID), true
}

func (u *unique) set(key string, id store.ID) { u.tree.Set(key, id) }

func (u *unique) remove(key string) { u.tree.Remove(key) }
