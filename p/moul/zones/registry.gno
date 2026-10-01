package zones

import (
	"errors"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/index/v0"
	"gno.land/p/moul/kit/store/v0"
)

// Bounds on what the registry holds. Two kinds of cap, because a single global
// one is filled by whoever gets there first: the per-address caps are what keep
// the registry open to the next proposer once a stranger has spammed it.
const (
	MaxZones               = 256 // every zone, whatever its status
	MaxPendingPerProposer  = 4   // open proposals one address may have at once
	MaxEndpointsPerZone    = 512
	MaxEndpointsPerAddress = 32 // endpoints one address may register on one zone
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

	endpoints *store.Store
	byZone    *index.Index // slug -> endpoint ids
	byAddress *index.Index // slug|kind|address -> endpoint id, unique
	byOwner   *index.Index // slug|registrant -> endpoint ids
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{
		zones:      store.Named("zone"),
		bySlug:     index.Unique(),
		byProposer: index.New(),
		endpoints:  store.Named("endpoint"),
		byZone:     index.New(),
		byAddress:  index.Unique(),
		byOwner:    index.New(),
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
	return r.byProposer.Add(by.String(), id)
}

// Edit replaces a zone's description. Its slug, status and history stay.
func (r *Registry) Edit(slug string, in Info) error {
	z, _, err := r.zone(slug)
	if err != nil {
		return err
	}
	in = trimInfo(in)
	if err := ValidateInfo(in); err != nil {
		return err
	}
	z.setInfo(in)
	return nil
}

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
	z.Status = to
	z.ReviewedBy, z.ReviewedAt, z.Reason = by, at, reason
	return nil
}

// RemoveZone deletes a zone and every endpoint registered on it, which gives
// the storage deposit back. An approved zone cannot be removed: retire it, so
// the record of it having been official survives.
func (r *Registry) RemoveZone(slug string) error {
	z, id, err := r.zone(slug)
	if err != nil {
		return err
	}
	if z.Status == Approved {
		return errors.New("zones: " + slug + " is approved; retire it instead of removing it")
	}
	for _, eid := range r.byZone.Lookup(slug) {
		r.removeEndpoint(eid)
	}
	if z.Status == Pending {
		r.byProposer.Remove(z.Proposer.String(), id)
	}
	r.bySlug.Remove(slug, id)
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
	reason = strings.TrimSpace(reason)
	if err := ValidateReason(reason); err != nil {
		return err
	}
	if to == "" {
		return errors.New("zones: a review needs a verdict")
	}
	if _, err := ParseVerification(string(to)); err != nil {
		return err
	}
	if e.Status == to {
		return errors.New("zones: endpoint #" + strconv.FormatInt(id, 10) + " is already " + string(to))
	}
	if to == Flagged && reason == "" {
		return errors.New("zones: flagging an endpoint needs a reason")
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
// proposed, which is the order a curator seeded them in.
func (r *Registry) Zones(f ZoneFilter) []Zone {
	out := []Zone{}
	r.zones.Each(func(_ store.ID, v any) {
		if z := v.(*Zone); f.Match(*z) {
			out = append(out, *z)
		}
	})
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
		for _, id := range r.byZone.Lookup(f.Zone) {
			v, _ := r.endpoints.Get(id)
			keep(v)
		}
		return out
	}
	r.endpoints.Each(func(_ store.ID, v any) { keep(v) })
	return out
}

// Count returns how many endpoints a zone has, and how many of them are
// verified, without copying any of them.
func (r *Registry) Count(slug string) (verified, total int) {
	for _, id := range r.byZone.Lookup(slug) {
		v, _ := r.endpoints.Get(id)
		total++
		if v.(*Endpoint).Status == Verified {
			verified++
		}
	}
	return verified, total
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

// removeEndpoint unwinds the store and all three indexes together.
func (r *Registry) removeEndpoint(id store.ID) {
	v, ok := r.endpoints.Remove(id)
	if !ok {
		return
	}
	e := v.(*Endpoint)
	r.byZone.Remove(e.Zone, id)
	r.byAddress.Remove(addressKey(e.Zone, e.Kind, e.Address), id)
	r.byOwner.Remove(e.Zone+"|"+e.Registrant.String(), id)
}

// addressKey is the dedup key. Lowercased, because a DNS name is
// case-insensitive and the same RPC registered twice under two spellings is
// still one RPC.
func addressKey(slug string, kind EndpointKind, addr string) string {
	return slug + "|" + string(kind) + "|" + strings.ToLower(addr)
}

func trimInfo(in Info) Info {
	in.ChainID = strings.TrimSpace(in.ChainID)
	in.Title = strings.TrimSpace(in.Title)
	in.Description = strings.TrimSpace(in.Description)
	in.Kind = Kind(strings.TrimSpace(string(in.Kind)))
	in.GnowebURL = strings.TrimSpace(in.GnowebURL)
	in.RPCURL = strings.TrimSpace(in.RPCURL)
	in.GenesisURL = strings.TrimSpace(in.GenesisURL)
	return in
}
