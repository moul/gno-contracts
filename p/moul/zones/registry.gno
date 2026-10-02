package zones

import (
	"crypto/sha256"
	"errors"
	"strconv"

	"gno.land/p/moul/kit/index/v0"
	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/bptree/v0"
)

// Bounds on what the registry holds.
//
// The LIVE registry, pending and approved zones, has a hard cap. Rejected and
// retired zones are kept for the record but do not count against it: each has
// a cap of its own, and when it is reached the zone that has been in that state
// longest is dropped to make room (by when it entered the state, not when it
// was proposed, so a long-lived network retired today is not the next to go).
// So nothing a proposer or a curator does, and no amount of time, can fill the
// registry for good: a cap that only ever fills is a lifetime cap, and on an
// immutable path that is a brick.
//
// The per-address caps make one address cheap to ignore. Neither stops a flood
// from many addresses, because an address is not an identity, so admission to
// the review queue has a gate of its own (MaxPending zones, MaxUnverifiedPerZone
// endpoints awaiting a verdict), well under the hard caps: a flood fills the
// queue and never crowds out an approved zone or a verified endpoint. A
// flagged endpoint has its verdict and leaves the queue, so curators keep a
// warning instead of having to delete it to make room. The gate is checked
// where something enters (Propose, Register); a review or a reset can push a
// count past it, and never fails for it. ProposeExempt and RegisterExempt skip
// it, and the per-address caps, for the reviewers a holder trusts: a full
// queue must not lock out the people who clear it. The queue clears through
// approval, verification, a flag, rejection, RemoveZone, RemoveEndpoint, an
// edit leaving the local kind, and eviction. Flagged endpoints still count
// toward MaxEndpointsPerZone: a flood a curator flags rather than removes can
// fill the places a gated registration may use (all but the last
// ReservedForReviewers), and removing it is the answer. Each entry costs its sender a
// storage deposit, refunded to whoever signs the transaction that
// frees it (on a chain where ugnot is not transfer-locked; on one that is, the
// refund goes to the storage fee collector), so a flooder who withdraws first
// gets it back: a bond, not a fee.
const (
	MaxZones               = 256 // pending and approved zones together
	MaxPending             = 64  // zones awaiting review, all proposers together
	MaxPendingPerProposer  = 4   // open proposals one address may have at once
	MaxRejected            = 64  // rejected zones kept for the record
	MaxRetired             = 128 // retired zones kept for the record
	MaxEndpointsPerZone    = 128
	MaxUnverifiedPerZone   = 64 // endpoints on one zone still waiting for a verdict (flagged ones have theirs)
	MaxEndpointsPerAddress = 16 // endpoints one address may register on one zone
	// MaxDropPerEdit bounds how many endpoints one edit off the local kind
	// drops, and so its gas: a removal rewrites up to about 45 later values in
	// two B+ tree leaves, and a caller can lay ids out so every removal does,
	// which at 128 measured 2.6B, close to a 3B block, and at 64 measures
	// 1.94B even with a chain-id reset and both own URLs moved in the same
	// edit. More waits for removals.
	MaxDropPerEdit = 64
	// ReservedForReviewers is how much of each hard cap (MaxZones live,
	// MaxEndpointsPerZone) only the exempt calls may use: strangers who keep
	// a cap full refill it the block after a curator clears it, and a cap a
	// curator cannot reach is one they cannot act under.
	ReservedForReviewers = 16
)

// The reasons an endpoint carries when its zone changed under it and sent it
// back to unverified. A reset caused by an edit to a pending zone by its own
// proposer records nobody, because that is not a review: ReviewedBy is empty
// and Reason says why. Every other reset (a rejection, a retirement, anybody
// else's edit, any edit to an approved zone) records whoever caused it.
const (
	ChainIDChanged = "the zone's chain id changed; verify again"
	ZoneRetired    = "the zone was retired; verify again if it returns"
	ZoneRejected   = "the zone was rejected; verify again if it is approved"
)

// sequences are the registry-wide counters: the last Revision handed out (so
// none is reused) and the last status-entry sequence (the eviction order).
type sequences struct{ rev, seq uint64 }

// fanout is the B+ tree fanout for every container this package builds itself:
// 32, not the 128 EFFECTIVE_GNO.md measured cheapest in memory. Every value in
// a B+ tree leaf is a boxed object of its own, and removing (or inserting) a
// key shifts every later value in the leaf, each shift a store write. Measured
// on a node, one transaction per step (gno master 3cc494ec4): removing the
// first key of a fanout-128 leaf filled with 120 cost 15.8M gas, the last 5.1M,
// about 90k gas per entry shifted (kit/index, whose values are pointers, measured
// 230k per shift); at fanout 32 it is the same 90k on a leaf a
// quarter the size. Endpoints are removed and their dedup keys inserted at
// arbitrary positions, so the smaller leaf is worth its larger node overhead
// (671 B per entry against 592).
const fanout = 32

// Registry holds the zones and their endpoints. The zero value is not usable:
// call [NewRegistry]. All its state is behind pointers, so a copy of the value
// is the same registry, not a second one sharing half of it.
//
// Every write touches its record and all of that record's indexes in one
// method. The index writes cannot fail as written: every key is validated
// non-empty and every unique key is checked free before the first write. If a
// later change made one fail, the method returns the error and the holding
// realm's abort undoes the half-applied write; that abort, not this method, is
// the atomicity guarantee.
type Registry struct {
	// The two sequences live behind a pointer like every container here, so a
	// copied Registry value shares them: with them inline, r2 := *r1 would
	// share every zone but count revisions on its own, and hand out a revision
	// r1 had already used, which a stale decision would then pass.
	ids *sequences

	zones      *table
	bySlug     *unique      // slug -> zone id
	byStatus   *index.Index // status -> zone ids, so a page reads only its rows
	entered    *unique      // status|entry sequence -> zone id: who has been in a state longest
	byProposer *counter     // proposer -> how many PENDING zones they have
	approved   *index.Index // chain id -> ids of APPROVED zones naming it

	endpoints *table
	byAddress *unique      // slug|kind|hash(canonical address) -> endpoint id
	byZone    *index.Index // slug -> endpoint ids
	byKind    *index.Index // slug|kind -> endpoint ids, so a page reads only its rows
	byOwner   *counter     // slug|registrant -> how many endpoints they registered
	unchecked *index.Index // slug -> ids of endpoints that are not Verified
	flagged   *counter     // slug -> how many of those are Flagged
	fresh     *counter     // slug -> how many endpoints are Clearable
	private   *index.Index // slug -> ids of endpoints on a private host (a local zone's only)
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{
		ids:        &sequences{},
		zones:      newTable(),
		bySlug:     newUnique(),
		byStatus:   index.New(),
		entered:    newUnique(),
		byProposer: newCounter(),
		approved:   index.New(),
		endpoints:  newTable(),
		byAddress:  newUnique(),
		byZone:     index.New(),
		byKind:     index.New(),
		byOwner:    newCounter(),
		flagged:    newCounter(),
		fresh:      newCounter(),
		unchecked:  index.New(),
		private:    index.New(),
	}
}

// Propose files a new zone, Pending, under a slug nobody holds.
func (r *Registry) Propose(by address, at int64, slug string, in Info) error {
	return r.propose(by, at, slug, in, true)
}

// ProposeExempt is Propose without the admission gates (MaxPending and
// MaxPendingPerProposer), for the reviewers a holding realm trusts: a flood
// that fills the queue would otherwise lock out the people who clear it. It
// also takes the last ReservedForReviewers places of the live registry, which
// Propose may not; MaxZones itself still holds.
func (r *Registry) ProposeExempt(by address, at int64, slug string, in Info) error {
	return r.propose(by, at, slug, in, false)
}

func (r *Registry) propose(by address, at int64, slug string, in Info, gated bool) error {
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
	if gated && r.Live() >= MaxZones-ReservedForReviewers {
		return errors.New("zones: the registry's last " + strconv.Itoa(ReservedForReviewers) + " places are kept for curators")
	}
	if gated && r.byStatus.Count(string(Pending)) >= MaxPending {
		return errors.New("zones: " + strconv.Itoa(MaxPending) + " proposals are already waiting for review; try again once a curator has cleared some")
	}
	if n := r.byProposer.count(by.String()); gated && n >= MaxPendingPerProposer {
		return errors.New("zones: " + by.String() + " already has " + strconv.Itoa(n) +
			" pending proposals, the limit is " + strconv.Itoa(MaxPendingPerProposer))
	}
	z := &Zone{Slug: slug, Proposer: by, ProposedAt: at}
	z.setInfo(in)
	id := r.zones.add(z)
	r.bySlug.set(slug, id)
	r.byProposer.inc(by.String())
	return r.enter(z, id, Pending)
}

// enter files a zone under a status, and bumps its Revision: a decision
// prepared against the old status must fail too, or an approval opened before
// a colleague's rejection would quietly reverse it. Only the two states that
// evict read the entry order, so only they write it. The caller has already
// taken the zone out of its old status.
func (r *Registry) enter(z *Zone, id store.ID, to Status) error {
	r.ids.seq++
	r.ids.rev++
	z.Status, z.Entered, z.Revision = to, int64(r.ids.seq), int64(r.ids.rev)
	if evicts(to) {
		r.entered.set(enteredKey(to, z.Entered), id)
	}
	return r.byStatus.Add(string(to), id)
}

func evicts(st Status) bool { return st == Rejected || st == Retired }

// leave takes a zone out of its current status.
func (r *Registry) leave(z *Zone, id store.ID) {
	r.byStatus.Remove(string(z.Status), id)
	if evicts(z.Status) {
		r.entered.remove(enteredKey(z.Status, z.Entered))
	}
	if z.Status == Pending {
		r.byProposer.dec(z.Proposer.String())
	}
	if z.Status == Approved {
		r.approved.Remove(z.ChainID, id)
	}
}

func enteredKey(st Status, seq int64) string { return string(st) + "|" + store.ID(seq).Key() }

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
// answered for a chain this zone no longer names. A reset caused by the
// proposer's own edit to a pending zone records no reviewer; any other records
// the editor. An edit that changes nothing is refused, and leaving the local
// kind removes every endpoint on a private or special-use host (IsPrivateHost),
// at most MaxDropPerEdit in one edit, and is refused while one of them carries
// a curator's ruling.
//
// An edit names the revision it was written against, like an approval does, so
// two editors working from the same reading cannot silently undo each other.
func (r *Registry) Edit(slug string, revision int64, in Info, by address, at int64, reason string) error {
	z, zid, err := r.zone(slug)
	if err != nil {
		return err
	}
	if err := stale(z, revision); err != nil {
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
	reason = TrimSpaces(reason)
	if err := ValidateReason(reason); err != nil {
		return err
	}
	switch {
	case z.Status == Pending && reason != "":
		return errors.New("zones: " + slug + " is pending, and an edit before review takes no reason")
	case z.Status == Approved && !HasVisible(reason):
		return errors.New("zones: " + slug + " is approved, so an edit needs a reason")
	}
	// An edit that changes nothing would still bump the revision, so refusing
	// it is what stops a revision being bumped for its own sake.
	if in == z.Info() {
		return errors.New("zones: that edit changes nothing on " + slug)
	}
	// Leaving the local kind drops the private hosts only a local zone may
	// list, whatever their verdict: they name nothing on the zone it becomes.
	// Dropped in the edit itself, not refused until somebody removes them,
	// because anybody may register one again between that removal and this
	// edit. Only those endpoints are read, from their own index. One a
	// curator ruled on (a verdict, or a reset that left a reason) is a
	// record, maybe one the editor never saw: the edit fails while one is
	// listed, and a curator removes it first, naming its revision. Only a
	// curator can rule, so nobody else can block the edit this way.
	if z.Kind == Local && in.Kind != Local {
		drop := r.private.Lookup(slug)
		if len(drop) > MaxDropPerEdit {
			return errors.New("zones: leaving local would drop " + strconv.Itoa(len(drop)) + " endpoints, more than " +
				strconv.Itoa(MaxDropPerEdit) + " in one edit; remove some first")
		}
		for _, eid := range drop {
			v, _ := r.endpoints.get(eid)
			// Every verdict names its reviewer and a reset leaves a reason, so
			// these two say "ruled on".
			if e := v.(*Endpoint); e.ReviewedBy != "" || e.Reason != "" {
				who := "a curator ruled on; a curator must remove it first"
				if e.Status == Verified {
					who = "is verified; its registrant or a curator must remove it first"
				}
				return errors.New("zones: leaving local would drop endpoint #" + strconv.FormatInt(e.ID, 10) + ", which " + who)
			}
		}
		for _, eid := range drop {
			r.removeEndpoint(eid)
		}
	}
	if in.ChainID != z.ChainID {
		// The proposer is not a reviewer; anybody else editing (a curator, on a
		// pending zone or an approved one) is, and is named on the reset.
		resetBy := address("")
		if z.Status == Approved || by != z.Proposer {
			resetBy = by
		}
		if z.Status == Approved {
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
	r.ids.rev++
	z.Revision = int64(r.ids.rev)
	z.EditedBy, z.EditedAt = by, at
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
// and a decision restated: the zone's present status again, with a new
// visible reason, which records the new reviewer and bumps the revision and
// does nothing else (no new entry in the state, no eviction, no reset). It is
// the only way to correct a reason.
//
// Every decision names the zone's Revision the curator read, and fails if the
// zone changed since: otherwise a proposer's edit landing just before an
// approval would become official under the curator's name, and a rejection's
// public reason would describe text the curator never saw.
//
// Rejecting or retiring sends every verified endpoint back to unverified: a
// rejected zone was never vouched for, and a retired network's peers may be
// somebody else's hosts by the time anyone reads them. Each state keeps at most
// MaxRejected or MaxRetired zones; the next one in drops the zone that entered
// that state first, with its endpoints. Every transition bumps the zone's
// Revision, so a decision prepared against the old status fails.
//
// Nothing goes back to pending: a rejected zone is approved after all, removed,
// or pushed out by newer rejections. An official zone is never rejected
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
	reason = TrimSpaces(reason)
	if err := ValidateReason(reason); err != nil {
		return err
	}
	if err := stale(z, revision); err != nil {
		return err
	}
	if z.Status == to {
		// A decision is restated with a new reason, the only way to correct
		// one: a rejected or retired zone is not editable, and an edit to an
		// approved zone must change something besides its reason.
		if (to == Approved || to == Rejected || to == Retired) && HasVisible(reason) && reason != z.Reason {
			r.ids.rev++
			z.Revision = int64(r.ids.rev)
			z.ReviewedBy, z.ReviewedAt, z.Reason = by, at, reason
			return nil
		}
		return errors.New("zones: " + slug + " is already " + string(to))
	}
	switch to {
	case Approved:
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
	r.leave(z, id)
	if to == Approved {
		if err := r.approved.Add(z.ChainID, id); err != nil {
			return err
		}
	}
	if err := r.enter(z, id, to); err != nil {
		return err
	}
	z.ReviewedBy, z.ReviewedAt, z.Reason = by, at, reason
	return nil
}

// stale refuses a decision written against a revision the zone has moved past.
func stale(z *Zone, revision int64) error {
	if revision != z.Revision {
		return errors.New("zones: " + z.Slug + " changed since you read it: it is at revision " +
			strconv.FormatInt(z.Revision, 10) + ", you acted on revision " + strconv.FormatInt(revision, 10) +
			"; read it again")
	}
	return nil
}

// makeRoom drops the zone that has been in that state longest, when the state
// is at its cap, so the one about to enter fits.
func (r *Registry) makeRoom(status Status, max int) {
	for r.byStatus.Count(string(status)) >= max {
		var oldest store.ID
		r.entered.tree.Iterate(string(status)+"|", string(status)+"}", func(_ string, v any) bool {
			oldest = v.(store.ID)
			return true
		})
		v, _ := r.zones.get(oldest)
		r.removeZone(v.(*Zone), oldest)
	}
}

// RemoveZone deletes a pending or rejected zone and every endpoint registered
// on it, freeing their storage deposit to whoever signs the removal. It names
// the revision it was decided on, so a removal meant for one proposal cannot
// land on another proposed again under the same slug. A zone that has ever
// been official cannot be removed this way: an approved one is retired, and a
// retired one is kept until MaxRetired newer retirements push it out, so
// whoever still holds its chain id can find out what happened to it.
func (r *Registry) RemoveZone(slug string, revision int64) error {
	z, id, err := r.zone(slug)
	if err != nil {
		return err
	}
	if err := stale(z, revision); err != nil {
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
		r.byOwner.dec(ownerKey(slug, v.(*Endpoint).Registrant))
	}
	// The zone's dedup keys are one contiguous range (a slug is [a-z0-9-], all
	// below "|"), so they are dropped without hashing each address again.
	keys := []string{}
	r.byAddress.tree.Iterate(slug+"|", slug+"}", func(k string, _ any) bool {
		keys = append(keys, k)
		return false
	})
	for _, k := range keys {
		r.byAddress.remove(k)
	}
	r.flagged.drop(slug)
	r.fresh.drop(slug)
	r.byZone.RemoveKey(slug)
	r.unchecked.RemoveKey(slug)
	r.private.RemoveKey(slug)
	for _, k := range EndpointKinds() {
		r.byKind.RemoveKey(kindKey(slug, k))
	}
	r.leave(z, id)
	r.bySlug.remove(slug)
	r.zones.remove(id)
}

// Register adds an endpoint to a zone, Unverified, and returns its id.
//
// A zone takes endpoints while it is pending or approved, and a rejected or
// retired zone takes none. Who may register on a pending zone is the holding
// realm's call; a URL is stored with its scheme and host lowercased and
// without an empty tail (trimEmptyTail), a peer lowercased whole without its
// host's terminal dot, so what is listed is what dials (Canonical, which also drops default ports and reads tcp as http, is
// what they are compared in, not what is stored).
func (r *Registry) Register(by address, at int64, slug string, kind EndpointKind, addr, label string) (int64, error) {
	return r.register(by, at, slug, kind, addr, label, true)
}

// RegisterExempt is Register without the admission gates
// (MaxUnverifiedPerZone and MaxEndpointsPerAddress), for the reviewers a
// holding realm trusts, as ProposeExempt is, and also takes a zone's last
// ReservedForReviewers places; the hard cap, MaxEndpointsPerZone, still holds.
func (r *Registry) RegisterExempt(by address, at int64, slug string, kind EndpointKind, addr, label string) (int64, error) {
	return r.register(by, at, slug, kind, addr, label, false)
}

func (r *Registry) register(by address, at int64, slug string, kind EndpointKind, addr, label string, gated bool) (int64, error) {
	z, _, err := r.zone(slug)
	if err != nil {
		return 0, err
	}
	if z.Status != Pending && z.Status != Approved {
		return 0, errors.New("zones: " + slug + " is " + string(z.Status) + " and takes no endpoints")
	}
	addr = TrimSpaces(addr)
	label = TrimSpaces(label)
	if err := ValidateEndpoint(kind, addr); err != nil {
		return 0, err
	}
	if kind == Seed || kind == Peer {
		addr = Canonical(kind, addr) // lowercase, no terminal dot: what tm2 dials
	} else {
		addr = trimEmptyTail(lowerAuthority(addr))
	}
	private := IsPrivateHost(HostOf(kind, addr))
	if z.Kind != Local && private {
		return 0, errors.New("zones: " + slug + " is a " + string(z.Kind) + " zone, and " + addr +
			" names a private or special-use host; only a local zone lists those")
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
	} else if gated && n >= MaxEndpointsPerZone-ReservedForReviewers {
		return 0, errors.New("zones: " + slug + "'s last " + strconv.Itoa(ReservedForReviewers) + " endpoint places are kept for curators")
	}
	if n := r.Awaiting(slug); gated && n >= MaxUnverifiedPerZone {
		return 0, errors.New("zones: " + slug + " already has " + strconv.Itoa(n) +
			" endpoints waiting for review; try again once a curator has cleared some")
	}
	okey := ownerKey(slug, by)
	if n := r.byOwner.count(okey); gated && n >= MaxEndpointsPerAddress {
		return 0, errors.New("zones: " + by.String() + " already registered " + strconv.Itoa(n) +
			" endpoints on " + slug + ", the limit is " + strconv.Itoa(MaxEndpointsPerAddress))
	}
	e := &Endpoint{Zone: slug, Kind: kind, Address: addr, Label: label, Registrant: by, RegisteredAt: at, Status: Unverified, Exempt: !gated}
	id := r.endpoints.add(e)
	e.ID = int64(id)
	r.ids.rev++
	e.Revision = int64(r.ids.rev)
	r.byAddress.set(akey, id)
	if err := r.byZone.Add(slug, id); err != nil {
		return 0, err
	}
	if err := r.byKind.Add(kindKey(slug, kind), id); err != nil {
		return 0, err
	}
	r.byOwner.inc(okey)
	if gated {
		r.fresh.inc(slug)
	}
	if err := r.unchecked.Add(slug, id); err != nil {
		return 0, err
	}
	if private {
		if err := r.private.Add(slug, id); err != nil {
			return 0, err
		}
	}
	return e.ID, nil
}

// ReviewEndpoint records a curator's verdict on an endpoint. Any verdict may
// follow any other, and the same one again with a new reason (so a typo is
// corrected without passing through a state its registrant may remove it
// from), with these rules:
//
//   - every verdict names the endpoint's Revision as read, and fails if the
//     endpoint changed since: a verdict landing after another curator's,
//     unseen, would silently reverse it;
//   - flagging needs a reason, because "do not use this" with no why is not
//     something an operator can act on;
//   - a verification also names the zone's Revision it was checked against,
//     and fails if the zone changed since: what is verified is that the
//     endpoint answers for THIS zone's chain id, and a proposer could otherwise
//     switch it while the verdict is in flight. A flag or an unverify does
//     not, so an edit to the zone cannot hold off a warning;
//   - only an endpoint of a pending or approved zone can be verified.
func (r *Registry) ReviewEndpoint(id int64, to Verification, zoneRevision, revision int64, by address, at int64, reason string) error {
	e, err := r.endpoint(id)
	if err != nil {
		return err
	}
	if !ValidAddress(by) {
		return errors.New("zones: the reviewer is not a valid lowercase address")
	}
	reason = TrimSpaces(reason)
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
	if e.Status == to && (reason == e.Reason || !HasVisible(reason)) {
		return errors.New("zones: endpoint #" + strconv.FormatInt(id, 10) + " is already " + string(to) +
			"; restating it needs a new reason")
	}
	if to == Flagged && !HasVisible(reason) {
		return errors.New("zones: flagging an endpoint needs a reason")
	}
	z, _, err := r.zone(e.Zone)
	if err != nil {
		return err
	}
	if revision != e.Revision {
		return errors.New("zones: endpoint #" + strconv.FormatInt(id, 10) + " changed since you checked it: it is at revision " +
			strconv.FormatInt(e.Revision, 10) + ", you acted on revision " + strconv.FormatInt(revision, 10))
	}
	if to == Verified {
		if z.Status != Pending && z.Status != Approved {
			return errors.New("zones: " + z.Slug + " is " + string(z.Status) + "; nothing on it can be verified")
		}
		if zoneRevision != z.Revision {
			return errors.New("zones: " + z.Slug + " changed since you checked it against it: it is at revision " +
				strconv.FormatInt(z.Revision, 10) + ", you verified against revision " + strconv.FormatInt(zoneRevision, 10))
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
	if e.Status == Flagged {
		r.flagged.dec(e.Zone)
	}
	if to == Flagged {
		r.flagged.inc(e.Zone)
	}
	if e.Clearable() {
		r.fresh.dec(e.Zone) // its first verdict: somebody has ruled on it now
	}
	e.Status = to
	e.ReviewedBy, e.ReviewedAt, e.Reason = by, at, reason
	r.ids.rev++
	e.Revision = int64(r.ids.rev)
	return nil
}

// unverifyAll sends every verified endpoint of a zone back to unverified with
// that reason, and by as the reviewer ("" when the proposer's own edit caused
// it). Flagged ones keep their flag. Only the verified ones are read: their
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
		r.ids.rev++
		e.Revision = int64(r.ids.rev)
	}
	return nil
}

// RemoveEndpoint deletes an endpoint, freeing its storage deposit to whoever
// signs the removal. revision is the endpoint's Revision as read: a removal
// fails if a verdict landed since, rather than delete one nobody saw. Who may
// is the holding realm's call.
func (r *Registry) RemoveEndpoint(id, revision int64) error {
	e, err := r.endpoint(id)
	if err != nil {
		return err
	}
	if revision != e.Revision {
		return errors.New("zones: endpoint #" + strconv.FormatInt(id, 10) + " changed since you read it: it is at revision " +
			strconv.FormatInt(e.Revision, 10) + ", you acted on revision " + strconv.FormatInt(revision, 10))
	}
	r.removeEndpoint(store.ID(id))
	return nil
}

// removeEndpoint unwinds the record and all eight of its indexes and counters
// together.
func (r *Registry) removeEndpoint(id store.ID) {
	v, ok := r.endpoints.remove(id)
	if !ok {
		return
	}
	e := v.(*Endpoint)
	r.byAddress.remove(addressKey(e.Zone, e.Kind, e.Address))
	r.byZone.Remove(e.Zone, id)
	r.byKind.Remove(kindKey(e.Zone, e.Kind), id)
	r.byOwner.dec(ownerKey(e.Zone, e.Registrant))
	r.unchecked.Remove(e.Zone, id)
	r.private.Remove(e.Zone, id)
	if e.Status == Flagged {
		r.flagged.dec(e.Zone)
	}
	if e.Clearable() {
		r.fresh.dec(e.Zone)
	}
}

// Revision is the last revision handed out, to a zone or an endpoint. Anything
// that changes after a read gets a later one.
func (r *Registry) Revision() int64 { return int64(r.ids.rev) }

// PrivateEndpoints returns a zone's endpoints on a private host, the ones
// leaving the local kind drops. Only those are read.
func (r *Registry) PrivateEndpoints(slug string) []Endpoint {
	out := []Endpoint{}
	for _, id := range r.private.Lookup(slug) {
		if v, ok := r.endpoints.get(id); ok {
			out = append(out, *v.(*Endpoint))
		}
	}
	return out
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
		//gnovet:ignore page-offset-overflow bounded by page-1 > n/size at the top
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

// SoleApproved returns the approved zone naming that chain id when there is
// exactly one, which is the only case a reader can be pointed at it without a
// guess. It counts first and reads one record at most.
func (r *Registry) SoleApproved(chainID string) (Zone, bool) {
	if r.approved.Count(chainID) != 1 {
		return Zone{}, false
	}
	id, _ := r.approved.First(chainID)
	v, _ := r.zones.get(id)
	return *v.(*Zone), true
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
		var ids []store.ID
		if f.Kind != "" {
			ids = r.byKind.Lookup(kindKey(f.Zone, f.Kind))
		} else {
			ids = r.byZone.Lookup(f.Zone)
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

// Awaiting returns how many of a zone's endpoints are waiting for a verdict,
// what MaxUnverifiedPerZone gates. No endpoint is read.
func (r *Registry) Awaiting(slug string) int {
	return r.unchecked.Count(slug) - r.flagged.count(slug)
}

// Clearable returns how many of a zone's endpoints are Clearable, what a bulk
// clear could remove. No endpoint is read.
func (r *Registry) Clearable(slug string) int { return r.fresh.count(slug) }

// OwnerCount returns how many endpoints that address registered on a zone. No
// endpoint is read.
func (r *Registry) OwnerCount(slug string, who address) int {
	return r.byOwner.count(ownerKey(slug, who))
}

// EndpointPage returns page (1-based) of a zone's endpoints of that kind, ""
// for every kind, size per page, oldest first. Like [Registry.ZonePage] it reads
// the records on the page only, and the bucket's id list (at most
// MaxEndpointsPerZone ids) whole.
func (r *Registry) EndpointPage(slug string, kind EndpointKind, page, size int) []Endpoint {
	var ids []store.ID
	if kind != "" {
		ids = r.byKind.Lookup(kindKey(slug, kind))
	} else {
		ids = r.byZone.Lookup(slug)
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
	//gnovet:ignore page-offset-overflow bounded by page-1 > len(ids)/size above
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
// in [Canonical] form. Hashed so the address part of the key is 16 bytes
// whatever the URL's length,
// instead of a second copy of up to MaxURLLen bytes the record already holds,
// and kept raw rather than hex: it is a key, never shown. Truncated to 128
// bits, which no accidental collision reaches and which only lets a deliberate
// one refuse its own registration. It is the last field, so a byte that happens
// to be "|" cannot be mistaken for a separator.
func addressKey(slug string, kind EndpointKind, addr string) string {
	sum := sha256.Sum256([]byte(Canonical(kind, addr)))
	return slug + "|" + string(kind) + "|" + string(sum[:16])
}

func kindKey(slug string, kind EndpointKind) string { return slug + "|" + string(kind) }

func ownerKey(slug string, who address) string { return slug + "|" + who.String() }

// trimInfo normalizes what a caller typed before it is validated: spaces
// around every field, and each URL's scheme and host lowercased in ASCII
// (both are case-insensitive, gno's link sanitizer is not, so HTTPS:// would
// render as a dead link). Nothing else is rewritten: what fails validation is
// refused, not repaired.
func trimInfo(in Info) Info {
	in.ChainID = TrimSpaces(in.ChainID)
	in.Title = TrimSpaces(in.Title)
	in.Description = TrimSpaces(in.Description)
	in.Kind = Kind(TrimSpaces(string(in.Kind)))
	in.GnowebURL = trimEmptyTail(lowerAuthority(TrimSpaces(in.GnowebURL)))
	in.RPCURL = lowerAuthority(TrimSpaces(in.RPCURL))
	in.GenesisURL = trimEmptyTail(lowerAuthority(TrimSpaces(in.GenesisURL)))
	return in
}

// table is numbered records in a B+ tree: kit/store's shape (an
// id that is never reused, keyed by its seqid encoding so the tree iterates in
// id order) on a B+ tree, the keyed, ordered container EFFECTIVE_GNO.md
// recommends for iteration and pagination. kit/store/v0 sits on an avl, which
// it measured at 2,029 B per entry against a B+ tree's 592 to 671, and about
// six times the gas per entry iterated, and on an immutable path that choice
// is permanent.
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
// stores every key as three objects (a box, an entry struct, an ids array), and
// for a key that only ever has one id two of them say nothing.
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

// counter is a key -> count map in a B+ tree, one object per key. What it
// answers (pending proposals per proposer and endpoints per registrant per
// zone for the caps, flagged endpoints per zone for the admission gate,
// clearable endpoints per zone for the bulk clear) only
// ever asks how many, so keeping the ids would be two more objects per key,
// written and deleted for nothing.
type counter struct{ tree *bptree.BPTree }

func newCounter() *counter { return &counter{tree: bptree.NewBPTreeN(fanout)} }

func (c *counter) count(key string) int {
	v := c.tree.Get(key)
	if v == nil {
		return 0
	}
	return v.(int)
}

func (c *counter) inc(key string) { c.tree.Set(key, c.count(key)+1) }

func (c *counter) dec(key string) {
	if n := c.count(key) - 1; n > 0 {
		c.tree.Set(key, n)
	} else {
		c.tree.Remove(key)
	}
}

func (c *counter) drop(key string) { c.tree.Remove(key) }
