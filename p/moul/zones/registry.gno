package zones

import (
	"errors"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/index/v0"
	"gno.land/p/moul/kit/store/v0"
)

// Bounds on what the registry holds, in three layers.
//
// The hard caps bound the storage. The per-address caps make one address
// cheap to ignore. Neither stops a flood from many addresses, because an
// address is not an identity, so the middle layer is what keeps a flood from
// mattering: unreviewed entries have a ceiling of their own, well under the
// hard cap, and the room above it can only be reached through a curator's
// review. A flood can fill the review queue; it can never crowd out an
// official zone or a verified endpoint. Clearing the queue is RemoveZone and
// RemoveEndpoint, and every entry a flood writes costs its sender a storage
// deposit, which is the only admission price a permissionless list has.
const (
	MaxZones               = 256 // every zone, whatever its status
	MaxPending             = 64  // zones awaiting review, all proposers together
	MaxPendingPerProposer  = 4   // open proposals one address may have at once
	MaxEndpointsPerZone    = 512
	MaxUnverifiedPerZone   = 128 // endpoints on one zone no curator has verified
	MaxEndpointsPerAddress = 32  // endpoints one address may register on one zone
)

// Registry holds the zones and their endpoints. The zero value is not usable:
// call [NewRegistry], because the slug and address indexes are unique ones.
//
// Every write that touches more than one container touches all of them in one
// method, so an error anywhere returns before any of them changed, and the
// realm's abort covers the rest. That is the whole correctness argument for
// keeping the records and the indexes in separate containers.
type Registry struct {
	zones      *store.Store
	bySlug     *index.Index // slug -> zone id, unique
	byProposer *index.Index // proposer -> ids of their PENDING zones
	byStatus   *index.Index // status -> zone ids, so a page reads only its rows
	byChain    *index.Index // chain id -> zone ids; not unique, chain ids collide

	endpoints *store.Store
	byZone    *index.Index // slug -> endpoint ids
	byAddress *index.Index // slug|kind|address -> endpoint id, unique
	byOwner   *index.Index // slug|registrant -> endpoint ids
	byKind    *index.Index // slug|kind -> endpoint ids, so a page reads only its rows
	unchecked *index.Index // slug -> ids of endpoints that are not Verified
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{
		zones:      store.Named("zone"),
		bySlug:     index.Unique(),
		byProposer: index.New(),
		byStatus:   index.New(),
		byChain:    index.New(),
		endpoints:  store.Named("endpoint"),
		byZone:     index.New(),
		byAddress:  index.Unique(),
		byOwner:    index.New(),
		byKind:     index.New(),
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
	if !by.IsValid() {
		return errors.New("zones: the proposer is not a valid address")
	}
	if r.bySlug.Has(slug) {
		return errors.New("zones: the slug " + strconv.Quote(slug) + " is taken")
	}
	if r.zones.Len() >= MaxZones {
		return errors.New("zones: the registry is full at " + strconv.Itoa(MaxZones) + " zones")
	}
	if r.byProposer.Len() >= MaxPending {
		return errors.New("zones: " + strconv.Itoa(MaxPending) + " proposals are already waiting for review; try again once a curator has cleared some")
	}
	if n := r.byProposer.Count(by.String()); n >= MaxPendingPerProposer {
		return errors.New("zones: " + by.String() + " already has " + strconv.Itoa(n) +
			" pending proposals, the limit is " + strconv.Itoa(MaxPendingPerProposer))
	}
	z := &Zone{Slug: slug, Status: Pending, Proposer: by, ProposedAt: at}
	z.setInfo(in)
	id := r.zones.Add(z)
	if err := r.bySlug.Add(slug, id); err != nil {
		return err
	}
	if err := r.byStatus.Add(string(Pending), id); err != nil {
		return err
	}
	if err := r.byChain.Add(in.ChainID, id); err != nil {
		return err
	}
	return r.byProposer.Add(by.String(), id)
}

// Edit replaces a zone's description. Its slug and status stay.
//
// Only a pending or an approved zone can be edited. A rejected one is removed
// and proposed again, or approved first; a retired one is a record, and its
// retirement reason is the thing it is kept for.
//
// Editing a pending zone is just an edit. Editing an approved one is a curator
// decision of its own: the reviewed values changed, so the review on record is
// replaced by this one, with a reason required. Otherwise the page would show
// a new chain id or RPC under the name, height and reason of whoever approved
// the old ones. And when the chain id itself changes, whatever the status,
// every endpoint verified against the old one goes back to unverified, because
// what was verified was that it answered for a chain this zone no longer names.
// A pending zone is no exception: a proposer could otherwise collect verdicts
// for one chain id and then switch it.
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
	reason = strings.TrimSpace(reason)
	if err := ValidateReason(reason); err != nil {
		return err
	}
	if !by.IsValid() {
		return errors.New("zones: the editor is not a valid address")
	}
	if z.Status == Approved && reason == "" {
		return errors.New("zones: " + slug + " is approved, so an edit needs a reason")
	}
	if in.ChainID != z.ChainID {
		for _, id := range r.byZone.Lookup(slug) {
			v, _ := r.endpoints.Get(id)
			e := v.(*Endpoint)
			if e.Status != Verified {
				continue
			}
			if err := r.unchecked.Add(slug, id); err != nil {
				return err
			}
			e.Status = Unverified
			e.ReviewedBy, e.ReviewedAt, e.Reason = by, at, ChainIDChanged
		}
	}
	if z.Status == Approved {
		z.ReviewedBy, z.ReviewedAt, z.Reason = by, at, reason
	}
	if in.ChainID != z.ChainID {
		r.byChain.Remove(z.ChainID, zid)
		if err := r.byChain.Add(in.ChainID, zid); err != nil {
			return err
		}
	}
	z.setInfo(in)
	return nil
}

// ChainIDChanged is the reason an endpoint carries when an edit to its zone's
// chain id sent it back to unverified.
const ChainIDChanged = "the zone's chain id changed; verify again"

// ReviewZone records a curator's decision on a zone.
//
// The transitions are the curation policy, and they are deliberately few:
//
//	approve  from pending, rejected or retired   reason optional
//	reject   from pending                        reason REQUIRED
//	retire   from approved                       reason REQUIRED
//
// Nothing goes back to pending: a proposer who disagrees with a rejection
// removes the zone and proposes it again. An official zone is never rejected
// after the fact, it is retired, so the record of it having been official
// survives.
func (r *Registry) ReviewZone(slug string, to Status, by address, at int64, reason string) error {
	z, id, err := r.zone(slug)
	if err != nil {
		return err
	}
	if !by.IsValid() {
		return errors.New("zones: the reviewer is not a valid address")
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
		// any state but approved itself, which the check above refused
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
	if (to == Rejected || to == Retired) && reason == "" {
		return errors.New("zones: " + string(to) + " needs a reason")
	}
	if z.Status == Pending {
		r.byProposer.Remove(z.Proposer.String(), id)
	}
	r.byStatus.Remove(string(z.Status), id)
	if err := r.byStatus.Add(string(to), id); err != nil {
		return err
	}
	z.Status = to
	z.ReviewedBy, z.ReviewedAt, z.Reason = by, at, reason
	return nil
}

// RemoveZone deletes a pending or rejected zone and every endpoint registered
// on it, which gives the storage deposit back. A zone that has ever been
// official cannot be removed: an approved one is retired, and a retired one is
// kept, so whoever still holds its chain id can find out what happened to it.
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
	for _, eid := range r.byZone.Lookup(slug) {
		r.removeEndpoint(eid)
	}
	if z.Status == Pending {
		r.byProposer.Remove(z.Proposer.String(), id)
	}
	r.bySlug.Remove(slug, id)
	r.byStatus.Remove(string(z.Status), id)
	r.byChain.Remove(z.ChainID, id)
	r.zones.Remove(id)
	return nil
}

// Register adds an endpoint to a zone, Unverified, and returns its id.
//
// A zone takes endpoints while it is pending or approved: a proposer may fill
// in the peers before the review, and a rejected or retired zone takes none.
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
	if kind != Seed && kind != Peer {
		addr = lowerScheme(addr)
	}
	if err := ValidateLabel(label); err != nil {
		return 0, err
	}
	if !by.IsValid() {
		return 0, errors.New("zones: the registrant is not a valid address")
	}
	akey := addressKey(slug, kind, addr)
	if r.byAddress.Has(akey) {
		return 0, errors.New("zones: " + slug + " already lists that " + string(kind) + ": " + addr)
	}
	if n := r.byZone.Count(slug); n >= MaxEndpointsPerZone {
		return 0, errors.New("zones: " + slug + " is full at " + strconv.Itoa(MaxEndpointsPerZone) + " endpoints")
	}
	if n := r.unchecked.Count(slug); n >= MaxUnverifiedPerZone {
		return 0, errors.New("zones: " + slug + " already has " + strconv.Itoa(n) +
			" endpoints waiting for review; try again once a curator has cleared some")
	}
	okey := slug + "|" + by.String()
	if n := r.byOwner.Count(okey); n >= MaxEndpointsPerAddress {
		return 0, errors.New("zones: " + by.String() + " already registered " + strconv.Itoa(n) +
			" endpoints on " + slug + ", the limit is " + strconv.Itoa(MaxEndpointsPerAddress))
	}
	e := &Endpoint{Zone: slug, Kind: kind, Address: addr, Label: label, Registrant: by, RegisteredAt: at, Status: Unverified}
	id := r.endpoints.Add(e)
	e.ID = int64(id)
	if err := r.byZone.Add(slug, id); err != nil {
		return 0, err
	}
	if err := r.byAddress.Add(akey, id); err != nil {
		return 0, err
	}
	if err := r.byOwner.Add(okey, id); err != nil {
		return 0, err
	}
	if err := r.byKind.Add(slug+"|"+string(kind), id); err != nil {
		return 0, err
	}
	if err := r.unchecked.Add(slug, id); err != nil {
		return 0, err
	}
	return e.ID, nil
}

// ReviewEndpoint records a curator's verdict on an endpoint. Any verdict may
// follow any other; flagging needs a reason, because "do not use this" with no
// why is not something an operator can act on.
func (r *Registry) ReviewEndpoint(id int64, to Verification, by address, at int64, reason string) error {
	e, err := r.endpoint(id)
	if err != nil {
		return err
	}
	if !by.IsValid() {
		return errors.New("zones: the reviewer is not a valid address")
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
	if to == Flagged && reason == "" {
		return errors.New("zones: flagging an endpoint needs a reason")
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

// RemoveEndpoint deletes an endpoint and gives its deposit back.
func (r *Registry) RemoveEndpoint(id int64) error {
	if _, err := r.endpoint(id); err != nil {
		return err
	}
	r.removeEndpoint(store.ID(id))
	return nil
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
// proposed, which is the order a curator seeded them in. With a status set it
// reads that status's zones only.
func (r *Registry) Zones(f ZoneFilter) []Zone {
	out := []Zone{}
	if f.Status != "" {
		for _, id := range r.byStatus.Lookup(string(f.Status)) {
			if z := r.zones.MustGet(id).(*Zone); f.Match(*z) {
				out = append(out, *z)
			}
		}
		return out
	}
	r.zones.Each(func(_ store.ID, v any) {
		if z := v.(*Zone); f.Match(*z) {
			out = append(out, *z)
		}
	})
	return out
}

// ZoneCount returns how many zones have that status, without reading any.
func (r *Registry) ZoneCount(status Status) int {
	if status == "" {
		return r.zones.Len()
	}
	return r.byStatus.Count(string(status))
}

// ZonePage returns page (1-based) of the zones with that status, size per
// page, in proposal order. A page past the end is empty.
//
// It reads only the zones ON the page. The status's id list is read whole (one
// object, at most MaxZones ids) and sliced, which is the bound that matters:
// measured at the full caps, 256 approved zones and 512 endpoints on one zone,
// one ZonePage plus one EndpointPage of 25 costs about 7.5M gas, against
// vm/qrender's 3,000,000,000 ceiling.
func (r *Registry) ZonePage(status Status, page, size int) []Zone {
	out := []Zone{}
	if status == "" {
		// Every status, as ZoneCount("") counts and ZoneFilter{} matches.
		// store.Page multiplies before it checks, so the same overflow guard as
		// pageOf goes first, and size is capped at what exists.
		n := r.zones.Len()
		if page < 1 || size < 1 || page-1 > n/size {
			return out
		}
		if size > n {
			size = n
		}
		for _, e := range r.zones.Page(page, size) {
			out = append(out, *e.Value.(*Zone))
		}
		return out
	}
	for _, id := range pageOf(r.byStatus.Lookup(string(status)), page, size) {
		out = append(out, *r.zones.MustGet(id).(*Zone))
	}
	return out
}

// ZonesByChainID returns the zones naming that chain id, in proposal order.
// Usually one, but chain ids are not unique across networks (every gnodev is
// "dev"), so it is a list.
func (r *Registry) ZonesByChainID(chainID string) []Zone {
	out := []Zone{}
	for _, id := range r.byChain.Lookup(chainID) {
		out = append(out, *r.zones.MustGet(id).(*Zone))
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
// zone set it reads that zone's index only, so it costs what the zone holds,
// not what the registry holds.
func (r *Registry) Endpoints(f EndpointFilter) []Endpoint {
	out := []Endpoint{}
	keep := func(v any) {
		if e := v.(*Endpoint); f.Match(*e) {
			out = append(out, *e)
		}
	}
	if f.Zone != "" {
		ids := r.byZone.Lookup(f.Zone)
		if f.Kind != "" {
			ids = r.byKind.Lookup(f.Zone + "|" + string(f.Kind))
		}
		for _, id := range ids {
			v, _ := r.endpoints.Get(id)
			keep(v)
		}
		return out
	}
	r.endpoints.Each(func(_ store.ID, v any) { keep(v) })
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
	return r.byKind.Count(slug + "|" + string(kind))
}

// EndpointPage returns page (1-based) of a zone's endpoints of that kind, ""
// for every kind, size per page, oldest first. Like [Registry.ZonePage] it reads
// the records on the page only, and the bucket's id list (at most
// MaxEndpointsPerZone ids) whole.
func (r *Registry) EndpointPage(slug string, kind EndpointKind, page, size int) []Endpoint {
	ids := r.byZone.Lookup(slug)
	if kind != "" {
		ids = r.byKind.Lookup(slug + "|" + string(kind))
	}
	out := []Endpoint{}
	for _, id := range pageOf(ids, page, size) {
		v, _ := r.endpoints.Get(id)
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
func (r *Registry) Len() int { return r.zones.Len() }

func (r *Registry) zone(slug string) (*Zone, store.ID, error) {
	id, ok := r.bySlug.First(slug)
	if !ok {
		return nil, 0, errors.New("zones: no zone " + strconv.Quote(slug))
	}
	return r.zones.MustGet(id).(*Zone), id, nil
}

func (r *Registry) endpoint(id int64) (*Endpoint, error) {
	if id <= 0 {
		return nil, errors.New("zones: no endpoint #" + strconv.FormatInt(id, 10))
	}
	v, ok := r.endpoints.Get(store.ID(id))
	if !ok {
		return nil, errors.New("zones: no endpoint #" + strconv.FormatInt(id, 10))
	}
	return v.(*Endpoint), nil
}

// removeEndpoint unwinds the store and all five of its indexes together.
func (r *Registry) removeEndpoint(id store.ID) {
	v, ok := r.endpoints.Remove(id)
	if !ok {
		return
	}
	e := v.(*Endpoint)
	r.byZone.Remove(e.Zone, id)
	r.byAddress.Remove(addressKey(e.Zone, e.Kind, e.Address), id)
	r.byOwner.Remove(e.Zone+"|"+e.Registrant.String(), id)
	r.byKind.Remove(e.Zone+"|"+string(e.Kind), id)
	r.unchecked.Remove(e.Zone, id)
}

// addressKey is the dedup key, on the [Canonical] form: the same RPC under two
// spellings of its host is one RPC, and two paths on one host are two.
func addressKey(slug string, kind EndpointKind, addr string) string {
	return slug + "|" + string(kind) + "|" + Canonical(kind, addr)
}

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
