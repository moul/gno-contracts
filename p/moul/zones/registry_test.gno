package zones

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice   = testutils.TestAddress("alice")
	bob     = testutils.TestAddress("bob")
	curator = testutils.TestAddress("curator")
)

func onyx() Info {
	return Info{
		ChainID:     "onyx-1",
		Title:       "Onyx",
		Description: "The gno.land testnet.",
		Kind:        Testnet,
		GnowebURL:   "https://onyx.testnets.gno.land",
		RPCURL:      "https://rpc.onyx.testnets.gno.land",
	}
}

func TestProposeAndRead(t *testing.T) {
	r := NewRegistry()
	in := onyx()
	in.Title = "  Onyx  "
	uassert.NoError(t, r.Propose(alice, 10, "onyx", in))

	z, ok := r.Zone("onyx")
	uassert.True(t, ok)
	uassert.Equal(t, "Onyx", z.Title) // trimmed
	uassert.Equal(t, string(Pending), string(z.Status))
	uassert.Equal(t, alice.String(), z.Proposer.String())
	uassert.Equal(t, int64(10), z.ProposedAt)
	uassert.True(t, !z.Reviewed())

	_, ok = r.Zone("nope")
	uassert.False(t, ok)

	uassert.ErrorContains(t, r.Propose(bob, 11, "onyx", onyx()), "is taken")
	uassert.ErrorContains(t, r.Propose(bob, 11, "On yx", onyx()), "slug")
	uassert.ErrorContains(t, r.Propose("", 11, "other", onyx()), "proposer is not a valid lowercase address")
	uassert.Equal(t, 1, r.Len())
}

func TestZoneCopiesAreCopies(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	z, _ := r.Zone("onyx")
	z.Title = "mutated"
	z.Status = Approved
	again, _ := r.Zone("onyx")
	uassert.Equal(t, "Onyx", again.Title)
	uassert.Equal(t, string(Pending), string(again.Status))
}

func TestPendingCapPerProposer(t *testing.T) {
	r := NewRegistry()
	for i := 0; i < MaxPendingPerProposer; i++ {
		uassert.NoError(t, r.Propose(alice, 1, "z"+strconv.Itoa(i), onyx()))
	}
	uassert.ErrorContains(t, r.Propose(alice, 1, "one-more", onyx()), "pending proposals, the limit is")
	// Somebody else is not blocked by alice's spam.
	uassert.NoError(t, r.Propose(bob, 1, "bobs", onyx()))
	// A reviewed proposal frees the slot.
	uassert.NoError(t, r.ReviewZone("z0", Approved, rev(r, "z0"), curator, 2, ""))
	uassert.NoError(t, r.Propose(alice, 3, "one-more", onyx()))
	// So does a removed one.
	uassert.NoError(t, r.RemoveZone("z1", rev(r, "z1")))
	uassert.NoError(t, r.Propose(alice, 3, "and-another", onyx()))
}

func TestReviewTransitions(t *testing.T) {
	cases := []struct {
		from   Status
		to     Status
		reason string
		err    string
	}{
		{Pending, Approved, "", ""},
		{Pending, Rejected, "duplicate of onyx", ""},
		{Pending, Rejected, "", "needs a reason"},
		{Pending, Rejected, "\u200b", "invisible or bidi"},
		{Approved, Retired, "\u2066\u2069", "invisible or bidi"},
		{Pending, Retired, "gone", "only an approved zone can be retired"},
		{Pending, Pending, "", "already pending"},
		{Approved, Retired, "the RPC stopped resolving", ""},
		{Approved, Retired, "  ", "needs a reason"},
		{Approved, Rejected, "x", "retire it instead"},
		{Approved, Approved, "", "already approved"},
		{Rejected, Approved, "reconsidered", ""},
		{Rejected, Retired, "x", "only an approved zone"},
		{Retired, Approved, "it came back", ""},
		{Retired, Rejected, "x", "only a pending zone can be rejected"},
		{Pending, "official", "", "cannot set a zone"},
	}
	for _, c := range cases {
		r := NewRegistry()
		uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
		// Walk the zone to the starting state.
		switch c.from {
		case Approved:
			uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 2, ""))
		case Rejected:
			uassert.NoError(t, r.ReviewZone("onyx", Rejected, rev(r, "onyx"), curator, 2, "setup"))
		case Retired:
			uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 2, ""))
			uassert.NoError(t, r.ReviewZone("onyx", Retired, rev(r, "onyx"), curator, 3, "setup"))
		}
		label := string(c.from) + " -> " + string(c.to)
		err := r.ReviewZone("onyx", c.to, rev(r, "onyx"), curator, 9, c.reason)
		z, _ := r.Zone("onyx")
		if c.err != "" {
			uassert.ErrorContains(t, err, c.err, label)
			uassert.Equal(t, string(c.from), string(z.Status), label)
			continue
		}
		uassert.NoError(t, err, label)
		uassert.Equal(t, string(c.to), string(z.Status), label)
		uassert.Equal(t, curator.String(), z.ReviewedBy.String(), label)
		uassert.Equal(t, int64(9), z.ReviewedAt, label)
		uassert.Equal(t, c.reason, z.Reason, label)
	}
}

func TestEdit(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	in := onyx()
	in.GenesisURL = "https://github.com/gnolang/gno/releases/download/chain/onyx/genesis.json"
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), in, "", 2, ""), "editor is not a valid lowercase address")
	uassert.NoError(t, r.Edit("onyx", rev(r, "onyx"), in, alice, 2, ""))
	z, _ := r.Zone("onyx")
	uassert.Equal(t, in.GenesisURL, z.GenesisURL)
	uassert.False(t, z.Reviewed()) // pending: just an edit

	bad := in
	bad.RPCURL = ""
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), bad, alice, 2, ""), "rpc url is empty")
	uassert.ErrorContains(t, r.Edit("nope", rev(r, "nope"), in, alice, 2, ""), "no zone")
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "https://rpc.onyx.testnets.gno.land", z.RPCURL) // unchanged by the refused edit

	// Once reviewed, an edit is a decision: it needs a reason and an editor, and
	// it replaces the review on record.
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 3, "probed"))
	in.RPCURL = "https://rpc2.onyx.example.com"
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), in, curator, 4, ""), "an edit needs a reason")
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), in, "", 4, "moved"), "editor is not a valid lowercase address")
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "https://rpc.onyx.testnets.gno.land", z.RPCURL)
	uassert.Equal(t, "probed", z.Reason)
	uassert.NoError(t, r.Edit("onyx", rev(r, "onyx"), in, bob, 5, "rpc moved"))
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "https://rpc2.onyx.example.com", z.RPCURL)
	uassert.Equal(t, bob.String(), z.ReviewedBy.String())
	uassert.Equal(t, int64(5), z.ReviewedAt)
	uassert.Equal(t, "rpc moved", z.Reason)
	uassert.Equal(t, string(Approved), string(z.Status))

	// A retired zone is a record: its retirement reason is not editable away.
	uassert.NoError(t, r.ReviewZone("onyx", Retired, rev(r, "onyx"), curator, 6, "testnet ended"))
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), in, curator, 7, "typo"), "only a pending or approved zone can be edited")
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "testnet ended", z.Reason)
	// Nor is a rejected one.
	uassert.NoError(t, r.Propose(alice, 8, "nope", onyx()))
	uassert.NoError(t, r.ReviewZone("nope", Rejected, rev(r, "nope"), curator, 9, "dup"))
	uassert.ErrorContains(t, r.Edit("nope", rev(r, "nope"), onyx(), alice, 10, ""), "only a pending or approved zone can be edited")
}

// What was verified is that an endpoint answered for the zone's chain id, so
// changing the chain id un-verifies them; changing only the RPC does not.
func TestChainIDEditUnverifiesEndpoints(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(curator, 1, "onyx", onyx()))
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 1, ""))
	a, _ := r.Register(alice, 2, "onyx", RPC, "https://a.example.com", "")
	b, _ := r.Register(alice, 2, "onyx", Peer, nodeID+"@b.example.com:26656", "")
	f, _ := r.Register(alice, 2, "onyx", RPC, "https://f.example.com", "")
	uassert.NoError(t, r.ReviewEndpoint(a, Verified, erev(r, a), curator, 3, ""))
	uassert.NoError(t, r.ReviewEndpoint(b, Verified, erev(r, b), curator, 3, ""))
	uassert.NoError(t, r.ReviewEndpoint(f, Flagged, erev(r, f), curator, 3, "down"))

	in := onyx()
	in.RPCURL = "https://rpc2.onyx.example.com"
	uassert.NoError(t, r.Edit("onyx", rev(r, "onyx"), in, curator, 4, "rpc moved"))
	uassert.Equal(t, 2, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))

	in.ChainID = "onyx-2"
	uassert.NoError(t, r.Edit("onyx", rev(r, "onyx"), in, curator, 5, "relaunched as onyx-2"))
	uassert.Equal(t, 0, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))
	e, _ := r.Endpoint(a)
	uassert.Equal(t, string(Unverified), string(e.Status))
	uassert.Equal(t, ChainIDChanged, e.Reason)
	uassert.Equal(t, int64(5), e.ReviewedAt)
	e, _ = r.Endpoint(f)
	uassert.Equal(t, string(Flagged), string(e.Status)) // a flag is not undone by an edit
	uassert.Equal(t, "down", e.Reason)
	// And the reset ones count against the review queue again (the flagged
	// one has its verdict and stays out): verifying one frees it.
	v, _ := r.Count("onyx")
	uassert.Equal(t, 0, v)
	uassert.Equal(t, 2, r.Awaiting("onyx"), "both reset endpoints are back in the queue")
	uassert.NoError(t, r.ReviewEndpoint(a, Verified, erev(r, a), curator, 6, "answers onyx-2"))
	uassert.Equal(t, 1, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))
	v, _ = r.Count("onyx")
	uassert.Equal(t, 1, v)

	// Retiring resets what was verified, at the moment the network stops: a
	// retired network's hosts may be somebody else's by the time anyone reads
	// them. Approving it again does not restore anything.
	uassert.NoError(t, r.ReviewEndpoint(b, Verified, erev(r, b), curator, 6, ""))
	uassert.NoError(t, r.ReviewZone("onyx", Retired, rev(r, "onyx"), curator, 6, "stopped"))
	uassert.Equal(t, 0, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))
	e, _ = r.Endpoint(b)
	uassert.Equal(t, ZoneRetired, e.Reason)
	uassert.Equal(t, curator.String(), e.ReviewedBy.String())
	uassert.ErrorContains(t, r.ReviewEndpoint(b, Verified, erev(r, b), curator, 6, ""), "nothing on it can be verified")
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 7, "back up"))
	uassert.Equal(t, 0, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))
	e, _ = r.Endpoint(f)
	uassert.Equal(t, string(Flagged), string(e.Status))
	// A pending zone is no exception: a proposer collecting verdicts for one
	// chain id and then switching it gets them all reset.
	uassert.NoError(t, r.Propose(alice, 7, "pend", onyx()))
	pid, _ := r.Register(alice, 7, "pend", RPC, "https://p.example.com", "")
	uassert.NoError(t, r.ReviewEndpoint(pid, Verified, erev(r, pid), curator, 8, ""))
	other := onyx()
	other.ChainID = "elsewhere-1"
	uassert.NoError(t, r.Edit("pend", rev(r, "pend"), other, alice, 9, ""))
	e, _ = r.Endpoint(pid)
	uassert.Equal(t, string(Unverified), string(e.Status))
	// The proposer's own edit caused the reset, and the proposer is not a
	// reviewer, so none is recorded, and the reason says why.
	uassert.Equal(t, "", e.ReviewedBy.String())
	uassert.Equal(t, ChainIDChanged, e.Reason)
	z, _ := r.Zone("pend")
	uassert.False(t, z.Reviewed()) // still a pending edit: the zone's own review is untouched
}

func TestRegisterAndFilter(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(curator, 1, "onyx", onyx()))
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 1, ""))

	rpc, err := r.Register(alice, 5, "onyx", RPC, " https://rpc.onyx.testnets.gno.land ", "gno core")
	uassert.NoError(t, err)
	peer, err := r.Register(bob, 6, "onyx", Peer, nodeID+"@seed-1.onyx.testnets.gno.land:26656", "")
	uassert.NoError(t, err)
	uassert.True(t, rpc > 0 && peer > rpc)

	e, ok := r.Endpoint(rpc)
	uassert.True(t, ok)
	uassert.Equal(t, rpc, e.ID)
	uassert.Equal(t, "https://rpc.onyx.testnets.gno.land", e.Address) // trimmed
	uassert.Equal(t, string(Unverified), string(e.Status))
	uassert.Equal(t, alice.String(), e.Registrant.String())

	// Dedup is case-insensitive: the same host under another spelling.
	_, err = r.Register(bob, 7, "onyx", RPC, "https://RPC.onyx.testnets.gno.land", "")
	uassert.ErrorContains(t, err, "already lists that rpc")
	// ...but a path is case-sensitive, so another path is another endpoint.
	_, err = r.Register(bob, 7, "onyx", Indexer, "https://indexer.example.com/API", "")
	uassert.NoError(t, err)
	_, err = r.Register(bob, 7, "onyx", Indexer, "https://INDEXER.example.com/API", "")
	uassert.ErrorContains(t, err, "already lists that indexer")
	_, err = r.Register(bob, 7, "onyx", Indexer, "https://indexer.example.com/api", "")
	uassert.NoError(t, err)
	// The same address under another kind is a different endpoint.
	_, err = r.Register(bob, 7, "onyx", Gnoweb, "https://rpc.onyx.testnets.gno.land", "")
	uassert.NoError(t, err)

	_, err = r.Register(bob, 7, "nope", RPC, "https://x.y", "")
	uassert.ErrorContains(t, err, "no zone")
	_, err = r.Register(bob, 7, "onyx", Peer, "https://x.y", "")
	uassert.ErrorContains(t, err, "<node id>@")
	_, err = r.Register(bob, 7, "onyx", RPC, "https://x.y", "two\nlines")
	uassert.ErrorContains(t, err, "control character")

	uassert.Equal(t, 5, len(r.Endpoints(EndpointFilter{Zone: "onyx"})))
	uassert.Equal(t, 1, len(r.Endpoints(EndpointFilter{Zone: "onyx", Kind: Peer})))
	uassert.Equal(t, 4, len(r.Endpoints(EndpointFilter{Registrant: bob})))
	uassert.Equal(t, 0, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))

	uassert.NoError(t, r.ReviewEndpoint(rpc, Verified, erev(r, rpc), curator, 8, "answers onyx-1"))
	vs := r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})
	uassert.Equal(t, 1, len(vs))
	uassert.Equal(t, "answers onyx-1", vs[0].Reason)
	v, total := r.Count("onyx")
	uassert.Equal(t, 1, v)
	uassert.Equal(t, 5, total)

	uassert.ErrorContains(t, r.ReviewEndpoint(rpc, Verified, erev(r, rpc), curator, 8, ""), "already verified")
	uassert.ErrorContains(t, r.ReviewEndpoint(peer, Flagged, erev(r, peer), curator, 8, ""), "needs a reason")
	uassert.ErrorContains(t, r.ReviewEndpoint(peer, "trusted", erev(r, peer), curator, 8, ""), "unknown verification")
	uassert.ErrorContains(t, r.ReviewEndpoint(peer, "", erev(r, peer), curator, 8, ""), "needs a verdict")
	uassert.ErrorContains(t, r.ReviewEndpoint(peer, " verified ", erev(r, peer), curator, 8, ""), "unknown verification")
	_, err = r.Register(bob, 7, "onyx", " rpc ", "not a url", "")
	uassert.ErrorContains(t, err, "unknown endpoint kind")
	// A scheme's case is not a different endpoint.
	_, err = r.Register(bob, 7, "onyx", Explorer, "HTTPS://Explorer.example.com/x", "")
	uassert.NoError(t, err)
	_, err = r.Register(bob, 7, "onyx", Explorer, "https://explorer.example.com/x", "")
	uassert.ErrorContains(t, err, "already lists that explorer")
	uassert.ErrorContains(t, r.ReviewEndpoint(999, Verified, erev(r, 999), curator, 8, ""), "no endpoint #999")
	uassert.ErrorContains(t, r.ReviewEndpoint(0, Verified, erev(r, 0), curator, 8, ""), "no endpoint #0")
	uassert.NoError(t, r.ReviewEndpoint(peer, Flagged, erev(r, peer), curator, 9, "wrong chain id"))
	uassert.NoError(t, r.ReviewEndpoint(peer, Unverified, erev(r, peer), curator, 10, "fixed, re-checking"))

	// Removing frees the dedup key, so the same address can come back.
	uassert.NoError(t, r.RemoveEndpoint(rpc))
	_, ok = r.Endpoint(rpc)
	uassert.False(t, ok)
	uassert.ErrorContains(t, r.RemoveEndpoint(rpc), "no endpoint")
	_, err = r.Register(bob, 11, "onyx", RPC, "https://rpc.onyx.testnets.gno.land", "")
	uassert.NoError(t, err)
}

func TestRegisterNeedsALiveZone(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	// Pending takes endpoints: a proposer fills in the peers before review.
	_, err := r.Register(alice, 2, "onyx", RPC, "https://a.example.com", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewZone("onyx", Rejected, rev(r, "onyx"), curator, 3, "not a gno chain"))
	_, err = r.Register(alice, 4, "onyx", RPC, "https://b.example.com", "")
	uassert.ErrorContains(t, err, "is rejected and takes no endpoints")
}

func TestEndpointCapPerAddress(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	for i := 0; i < MaxEndpointsPerAddress; i++ {
		_, err := r.Register(alice, 2, "onyx", RPC, "https://n"+strconv.Itoa(i)+".example.com", "")
		uassert.NoError(t, err)
	}
	_, err := r.Register(alice, 2, "onyx", RPC, "https://over.example.com", "")
	uassert.ErrorContains(t, err, "the limit is")
	// Bob still can.
	_, err = r.Register(bob, 2, "onyx", RPC, "https://over.example.com", "")
	uassert.NoError(t, err)
}

func TestRemoveZone(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	_, err := r.Register(bob, 2, "onyx", RPC, "https://a.example.com", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 3, ""))
	uassert.ErrorContains(t, r.RemoveZone("onyx", rev(r, "onyx")), "retire it instead")
	uassert.NoError(t, r.ReviewZone("onyx", Retired, rev(r, "onyx"), curator, 4, "testnet ended"))
	uassert.ErrorContains(t, r.RemoveZone("onyx", rev(r, "onyx")), "kept on record")
	_, ok := r.Zone("onyx")
	uassert.True(t, ok)

	// A rejected zone is removable, endpoints and all.
	uassert.NoError(t, r.Propose(alice, 5, "spam", onyx()))
	_, err = r.Register(bob, 5, "spam", RPC, "https://a.example.com", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewZone("spam", Rejected, rev(r, "spam"), curator, 6, "not a network"))
	uassert.NoError(t, r.RemoveZone("spam", rev(r, "spam")))
	_, ok = r.Zone("spam")
	uassert.False(t, ok)
	uassert.Equal(t, 0, len(r.Endpoints(EndpointFilter{Zone: "spam"})))
	uassert.Equal(t, 1, r.Len())
	uassert.ErrorContains(t, r.RemoveZone("spam", rev(r, "spam")), "no zone")
	// The slug and the address are free again.
	uassert.NoError(t, r.Propose(bob, 7, "spam", onyx()))
	_, err = r.Register(bob, 8, "spam", RPC, "https://a.example.com", "")
	uassert.NoError(t, err)
}

func TestReviewNeedsAReviewer(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	uassert.ErrorContains(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), "", 2, ""), "reviewer is not a valid lowercase address")
	z, _ := r.Zone("onyx")
	uassert.Equal(t, string(Pending), string(z.Status))
	id, err := r.Register(alice, 2, "onyx", RPC, "https://a.example.com", "")
	uassert.NoError(t, err)
	uassert.ErrorContains(t, r.ReviewEndpoint(id, Verified, erev(r, id), "", 3, ""), "reviewer is not a valid lowercase address")
}

// A flood from many addresses fills the review queue and nothing above it.
func TestFloodCannotCrowdOutReviewedEntries(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(curator, 1, "onyx", onyx()))
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 1, ""))
	for i := 0; i < MaxPending; i++ {
		uassert.NoError(t, r.Propose(testAddr(i), 2, "flood-"+strconv.Itoa(i), onyx()))
	}
	uassert.ErrorContains(t, r.Propose(bob, 3, "honest", onyx()), "waiting for review")
	uassert.Equal(t, MaxPending+1, r.Len())
	// Clearing one makes room.
	uassert.NoError(t, r.ReviewZone("flood-0", Rejected, rev(r, "flood-0"), curator, 4, "spam"))
	uassert.NoError(t, r.Propose(bob, 5, "honest", onyx()))

	// Endpoints: those waiting for a verdict have their own gate, and verifying frees it.
	ids := []int64{}
	for i := 0; i < MaxUnverifiedPerZone; i++ {
		id, err := r.Register(testAddr(i/MaxEndpointsPerAddress), 6, "onyx", RPC, "https://n"+strconv.Itoa(i)+".example.com", "")
		uassert.NoError(t, err)
		ids = append(ids, id)
	}
	_, err := r.Register(bob, 7, "onyx", RPC, "https://honest.example.com", "")
	uassert.ErrorContains(t, err, "waiting for review")
	uassert.NoError(t, r.ReviewEndpoint(ids[0], Verified, erev(r, ids[0]), curator, 8, ""))
	_, err = r.Register(bob, 9, "onyx", RPC, "https://honest.example.com", "")
	uassert.NoError(t, err)
	// The gate is full again (the honest one is waiting). A flag is a verdict,
	// so a flagged endpoint leaves the queue: curators keep the warning and
	// still make room, instead of deleting the warning to make room.
	_, err = r.Register(bob, 11, "onyx", RPC, "https://honest2.example.com", "")
	uassert.ErrorContains(t, err, "waiting for review")
	uassert.NoError(t, r.ReviewEndpoint(ids[1], Flagged, 0, curator, 12, "spam"))
	_, err = r.Register(bob, 13, "onyx", RPC, "https://honest2.example.com", "")
	uassert.NoError(t, err)
	// Unflagging puts it back in the queue, and a review is never refused for
	// the queue being full, only a registration is.
	uassert.NoError(t, r.ReviewEndpoint(ids[1], Unverified, 0, curator, 14, "re-checking"))
	_, err = r.Register(bob, 15, "onyx", RPC, "https://honest3.example.com", "")
	uassert.ErrorContains(t, err, "waiting for review")
	uassert.NoError(t, r.RemoveEndpoint(ids[2]))
	uassert.NoError(t, r.RemoveEndpoint(ids[3]))
	_, err = r.Register(bob, 16, "onyx", RPC, "https://honest3.example.com", "")
	uassert.NoError(t, err)
}

func testAddr(i int) address { return testutils.TestAddress("flood" + strconv.Itoa(i)) }

func TestZonesFilterAndOrder(t *testing.T) {
	r := NewRegistry()
	mainnet := onyx()
	mainnet.ChainID, mainnet.Kind = "gnoland-1", Mainnet
	uassert.NoError(t, r.Propose(curator, 1, "mainnet", mainnet))
	uassert.NoError(t, r.Propose(curator, 1, "onyx", onyx()))
	uassert.NoError(t, r.Propose(alice, 2, "alices", onyx()))
	uassert.NoError(t, r.ReviewZone("mainnet", Approved, rev(r, "mainnet"), curator, 3, ""))
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 3, ""))

	slugs := func(zs []Zone) string {
		s := ""
		for _, z := range zs {
			s += z.Slug + " "
		}
		return s
	}
	uassert.Equal(t, "mainnet onyx alices ", slugs(r.Zones(ZoneFilter{})))
	uassert.Equal(t, "mainnet onyx ", slugs(r.Zones(ZoneFilter{Status: Approved})))
	uassert.Equal(t, "alices ", slugs(r.Zones(ZoneFilter{Status: Pending})))
	uassert.Equal(t, "onyx alices ", slugs(r.Zones(ZoneFilter{Kind: Testnet})))
	uassert.Equal(t, "onyx ", slugs(r.Zones(ZoneFilter{Status: Approved, Kind: Testnet})))
	uassert.Equal(t, "", slugs(r.Zones(ZoneFilter{Kind: Local})))
}

func TestPagesAndCounts(t *testing.T) {
	r := NewRegistry()
	for i := 0; i < 7; i++ {
		uassert.NoError(t, r.Propose(testAddr(i), 1, "z"+strconv.Itoa(i), onyx()))
	}
	uassert.NoError(t, r.ReviewZone("z1", Approved, rev(r, "z1"), curator, 2, ""))
	uassert.NoError(t, r.ReviewZone("z3", Approved, rev(r, "z3"), curator, 2, ""))
	uassert.NoError(t, r.ReviewZone("z5", Approved, rev(r, "z5"), curator, 2, ""))
	uassert.Equal(t, 3, r.ZoneCount(Approved))
	uassert.Equal(t, 4, r.ZoneCount(Pending))
	uassert.Equal(t, 7, r.ZoneCount(""))

	page := func(zs []Zone) string {
		out := ""
		for _, z := range zs {
			out += z.Slug + " "
		}
		return out
	}
	uassert.Equal(t, "z1 z3 ", page(r.ZonePage(Approved, 1, 2)))
	uassert.Equal(t, "z5 ", page(r.ZonePage(Approved, 2, 2)))
	uassert.Equal(t, "", page(r.ZonePage(Approved, 3, 2)))
	uassert.Equal(t, "", page(r.ZonePage(Approved, 0, 2)))
	uassert.Equal(t, "", page(r.ZonePage(Approved, 1, 0)))
	uassert.Equal(t, "", page(r.ZonePage(Approved, 1<<62, 1<<10)), "no overflow into a small offset")
	uassert.Equal(t, "z0 z2 z4 z6 ", page(r.ZonePage(Pending, 1, 10)))
	// "" is every status, consistent with ZoneCount("") and ZoneFilter{}.
	uassert.Equal(t, "z0 z1 z2 ", page(r.ZonePage("", 1, 3)))
	uassert.Equal(t, "z6 ", page(r.ZonePage("", 3, 3)))
	uassert.Equal(t, "", page(r.ZonePage("", 4, 3)))
	uassert.Equal(t, "", page(r.ZonePage("", 0, 3)))
	uassert.Equal(t, "", page(r.ZonePage("", 1<<62, 1<<10)), "no overflow into a small offset")
	uassert.Equal(t, "z0 z1 z2 z3 z4 z5 z6 ", page(r.ZonePage("", 1, 1<<40)))
	// The status index follows a review and a removal.
	uassert.NoError(t, r.ReviewZone("z0", Rejected, rev(r, "z0"), curator, 3, "dup"))
	uassert.NoError(t, r.RemoveZone("z2", rev(r, "z2")))
	uassert.Equal(t, "z4 z6 ", page(r.ZonePage(Pending, 1, 10)))
	uassert.Equal(t, "z0 ", page(r.ZonePage(Rejected, 1, 10)))
	uassert.Equal(t, "z1 z3 z5 ", page(r.Zones(ZoneFilter{Status: Approved})))

	// Chain ids are not unique, only approved zones are indexed by one (so a
	// proposal naming a real chain id costs a reader nothing), and the index
	// follows an edit and a retirement.
	uassert.Equal(t, "z1 z3 z5 ", page(r.ApprovedByChainID("onyx-1")))
	in := onyx()
	in.ChainID = "onyx-2"
	uassert.NoError(t, r.Edit("z1", rev(r, "z1"), in, curator, 4, "relaunched"))
	uassert.Equal(t, "z1 ", page(r.ApprovedByChainID("onyx-2")))
	uassert.Equal(t, "z3 z5 ", page(r.ApprovedByChainID("onyx-1")))
	uassert.NoError(t, r.Edit("z4", rev(r, "z4"), in, alice, 4, "")) // pending: not indexed
	uassert.Equal(t, "z1 ", page(r.ApprovedByChainID("onyx-2")))
	uassert.NoError(t, r.ReviewZone("z5", Retired, rev(r, "z5"), curator, 4, "gone"))
	uassert.Equal(t, "z3 ", page(r.ApprovedByChainID("onyx-1")))

	// Endpoints: counts from the indexes, pages by kind.
	for i := 0; i < 5; i++ {
		_, err := r.Register(alice, 5, "z3", RPC, "https://e"+strconv.Itoa(i)+".example.com", "")
		uassert.NoError(t, err)
	}
	pid, err := r.Register(alice, 5, "z3", Peer, nodeID+"@p.example.com:26656", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewEndpoint(pid, Verified, erev(r, pid), curator, 6, ""))
	v, total := r.Count("z3")
	uassert.Equal(t, 1, v)
	uassert.Equal(t, 6, total)
	uassert.Equal(t, 5, r.EndpointCount("z3", RPC))
	uassert.Equal(t, 1, r.EndpointCount("z3", Peer))
	uassert.Equal(t, 0, r.EndpointCount("z3", Faucet))
	uassert.Equal(t, 6, r.EndpointCount("z3", ""))
	uassert.Equal(t, 1, len(r.EndpointPage("z3", RPC, 3, 2))) // page 3 of 5 rpcs at 2 a page holds one
	uassert.Equal(t, "https://e4.example.com", r.EndpointPage("z3", RPC, 3, 2)[0].Address)
	uassert.Equal(t, nodeID+"@p.example.com:26656", r.EndpointPage("z3", Peer, 1, 10)[0].Address)
	uassert.Equal(t, 6, len(r.EndpointPage("z3", "", 1, 10)))
	uassert.Equal(t, 1, len(r.Endpoints(EndpointFilter{Zone: "z3", Kind: Peer})))
	uassert.NoError(t, r.RemoveEndpoint(pid))
	uassert.Equal(t, 0, r.EndpointCount("z3", Peer))
	v, total = r.Count("z3")
	uassert.Equal(t, 0, v)
	uassert.Equal(t, 5, total)
}

// rev is a zone's current revision, what a curator who just read it approves.
func rev(r *Registry, slug string) int64 {
	z, _ := r.Zone(slug)
	return z.Revision
}

// erev is the revision of an endpoint's zone, what a curator verifies against.
func erev(r *Registry, id int64) int64 {
	e, ok := r.Endpoint(id)
	if !ok {
		return 0
	}
	return rev(r, e.Zone)
}

// An approval names the revision the curator read. An edit landing between the
// reading and the approval makes the approval fail, rather than making text the
// curator never saw official under their name. Remove-and-propose-again cannot
// reuse a revision either.
func TestApprovalBindsToRevision(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	read := rev(r, "onyx")

	swapped := onyx()
	swapped.RPCURL = "https://attacker.example.com"
	uassert.NoError(t, r.Edit("onyx", rev(r, "onyx"), swapped, alice, 2, ""))
	uassert.ErrorContains(t, r.ReviewZone("onyx", Approved, read, curator, 3, ""), "changed since you read it")
	z, _ := r.Zone("onyx")
	uassert.Equal(t, string(Pending), string(z.Status))
	uassert.Equal(t, alice.String(), z.EditedBy.String())
	uassert.Equal(t, int64(2), z.EditedAt)

	// Removed and proposed again under the same slug: a new revision, never the old one.
	uassert.NoError(t, r.RemoveZone("onyx", rev(r, "onyx")))
	uassert.NoError(t, r.Propose(alice, 4, "onyx", onyx()))
	uassert.ErrorContains(t, r.ReviewZone("onyx", Approved, read, curator, 5, ""), "changed since you read it")
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 5, ""))

	// Verifying an endpoint binds the same way: to the chain id it was checked against.
	id, err := r.Register(alice, 6, "onyx", RPC, "https://a.example.com", "")
	uassert.NoError(t, err)
	checked := rev(r, "onyx")
	moved := onyx()
	moved.ChainID = "onyx-2"
	uassert.NoError(t, r.Edit("onyx", rev(r, "onyx"), moved, curator, 7, "relaunch"))
	uassert.ErrorContains(t, r.ReviewEndpoint(id, Verified, checked, curator, 8, ""), "changed since you checked it")
	uassert.NoError(t, r.ReviewEndpoint(id, Verified, rev(r, "onyx"), curator, 8, ""))
	// Flagging and unverifying need no revision: they withdraw trust, never grant it.
	uassert.NoError(t, r.ReviewEndpoint(id, Flagged, 0, curator, 9, "down"))
}

func TestPendingEditTakesNoReason(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), onyx(), alice, 2, "fixed a typo"), "takes no reason")
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 3, ""))
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), onyx(), curator, 4, "\u200b"), "invisible")
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), onyx(), curator, 4, ""), "needs a reason")
	uassert.ErrorContains(t, r.Edit("onyx", rev(r, "onyx"), onyx(), curator, 4, "no change"), "changes nothing")
	in := onyx()
	in.Title = "Onyx testnet"
	uassert.NoError(t, r.Edit("onyx", rev(r, "onyx"), in, curator, 4, "retitled"))
}

// Rejected and retired zones are kept for the record, each up to a cap of its
// own, and neither counts against the live registry: nothing a proposer or a
// curator does, and no amount of time, fills it for good.
func TestRecordsNeverFillTheRegistry(t *testing.T) {
	r := NewRegistry()
	for i := 0; i < MaxRejected+3; i++ {
		slug := "rej" + strconv.Itoa(i)
		uassert.NoError(t, r.Propose(testAddr(i), 1, slug, onyx()))
		uassert.NoError(t, r.ReviewZone(slug, Rejected, rev(r, slug), curator, 2, "spam"))
	}
	uassert.Equal(t, MaxRejected, r.ZoneCount(Rejected))
	// The three that entered the rejected state first made room.
	_, ok := r.Zone("rej0")
	uassert.False(t, ok)
	_, ok = r.Zone("rej3")
	uassert.True(t, ok)
	uassert.Equal(t, 0, r.Live())

	for i := 0; i < MaxRetired+2; i++ {
		slug := "ret" + strconv.Itoa(i)
		uassert.NoError(t, r.Propose(curator, 3, slug, onyx()))
		uassert.NoError(t, r.ReviewZone(slug, Approved, rev(r, slug), curator, 3, ""))
		uassert.NoError(t, r.ReviewZone(slug, Retired, rev(r, slug), curator, 4, "stopped"))
	}
	uassert.Equal(t, MaxRetired, r.ZoneCount(Retired))
	_, ok = r.Zone("ret0")
	uassert.False(t, ok)
	uassert.Equal(t, 0, r.Live())
	uassert.Equal(t, MaxRejected+MaxRetired, r.Len())

	// The live registry is untouched by all of it.
	uassert.NoError(t, r.Propose(bob, 5, "honest", onyx()))
	uassert.Equal(t, 1, r.Live())
}

// An evicted zone takes its endpoints and every index entry with it, so its
// slug and its addresses can be used again.
func TestEvictionUnwindsEverything(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "first", onyx()))
	_, err := r.Register(alice, 1, "first", RPC, "https://f.example.com", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewZone("first", Rejected, rev(r, "first"), curator, 2, "dup"))
	for i := 0; i < MaxRejected; i++ {
		slug := "rej" + strconv.Itoa(i)
		uassert.NoError(t, r.Propose(testAddr(i), 3, slug, onyx()))
		uassert.NoError(t, r.ReviewZone(slug, Rejected, rev(r, slug), curator, 4, "spam"))
	}
	_, ok := r.Zone("first")
	uassert.False(t, ok)
	_, total := r.Count("first")
	uassert.Equal(t, 0, total)
	uassert.Equal(t, 0, r.OwnerCount("first", alice))
	uassert.Equal(t, 0, r.EndpointCount("first", RPC))
	uassert.NoError(t, r.Propose(alice, 5, "first", onyx()))
	_, err = r.Register(alice, 5, "first", RPC, "https://f.example.com", "")
	uassert.NoError(t, err)
}

// Approving a rejected or retired zone back into the live registry respects
// its cap.
func TestReviveRespectsTheLiveCap(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "back", onyx()))
	uassert.NoError(t, r.ReviewZone("back", Rejected, rev(r, "back"), curator, 1, "not yet"))
	for i := 0; i < MaxZones; i++ {
		slug := "z" + strconv.Itoa(i)
		uassert.NoError(t, r.Propose(curator, 2, slug, onyx()))
		uassert.NoError(t, r.ReviewZone(slug, Approved, rev(r, slug), curator, 2, ""))
	}
	uassert.Equal(t, MaxZones, r.Live())
	uassert.ErrorContains(t, r.ReviewZone("back", Approved, rev(r, "back"), curator, 3, ""), "full at")
	uassert.ErrorContains(t, r.Propose(bob, 3, "more", onyx()), "full at")
	uassert.NoError(t, r.ReviewZone("z0", Retired, rev(r, "z0"), curator, 3, "stopped"))
	uassert.NoError(t, r.ReviewZone("back", Approved, rev(r, "back"), curator, 4, ""))
}

func TestUppercaseAddressesAreRefused(t *testing.T) {
	r := NewRegistry()
	upper := address(strings.ToUpper(alice.String()))
	uassert.True(t, upper.IsValid(), "bech32 itself decodes the uppercase form")
	uassert.False(t, ValidAddress(upper))
	uassert.ErrorContains(t, r.Propose(upper, 1, "onyx", onyx()), "lowercase")
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	_, err := r.Register(upper, 1, "onyx", RPC, "https://a.example.com", "")
	uassert.ErrorContains(t, err, "lowercase")
	uassert.ErrorContains(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), upper, 2, ""), "lowercase")
}

// A peer is stored lowercased whole, so the listed form is the one tm2 dials,
// and two spellings of one host are one peer.
func TestPeerStoredLowercase(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	id, err := r.Register(alice, 1, "onyx", Peer, nodeID+"@SEED-1.Onyx.example.com:26656", "")
	uassert.NoError(t, err)
	e, _ := r.Endpoint(id)
	uassert.Equal(t, nodeID+"@seed-1.onyx.example.com:26656", e.Address)
	_, err = r.Register(alice, 1, "onyx", Peer, nodeID+"@seed-1.onyx.example.com:26656", "")
	uassert.ErrorContains(t, err, "already lists that peer")
	got, ok := r.EndpointByAddress("onyx", Peer, nodeID+"@Seed-1.onyx.example.com:26656")
	uassert.True(t, ok)
	uassert.Equal(t, id, got.ID)
}

// Rejecting sends what was verified on the proposal back to unverified: a
// rejected zone was never vouched for, so nothing on it reads as checked.
func TestRejectUnverifies(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	id, err := r.Register(alice, 1, "onyx", RPC, "https://a.example.com", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewEndpoint(id, Verified, rev(r, "onyx"), curator, 2, ""))
	uassert.NoError(t, r.ReviewZone("onyx", Rejected, rev(r, "onyx"), curator, 3, "not a gno chain"))
	e, _ := r.Endpoint(id)
	uassert.Equal(t, string(Unverified), string(e.Status))
	uassert.Equal(t, ZoneRejected, e.Reason)
	uassert.Equal(t, curator.String(), e.ReviewedBy.String())
	v, _ := r.Count("onyx")
	uassert.Equal(t, 0, v)
}

// Eviction goes by when a zone entered its state, not when it was proposed: a
// long-lived network retired today is not the next record to go.
func TestEvictionIsByEntryOrder(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(curator, 1, "mainnet", onyx())) // proposed first
	uassert.NoError(t, r.ReviewZone("mainnet", Approved, rev(r, "mainnet"), curator, 1, ""))
	for i := 0; i < MaxRetired; i++ {
		slug := "ret" + strconv.Itoa(i)
		uassert.NoError(t, r.Propose(curator, 2, slug, onyx()))
		uassert.NoError(t, r.ReviewZone(slug, Approved, rev(r, slug), curator, 2, ""))
		uassert.NoError(t, r.ReviewZone(slug, Retired, rev(r, slug), curator, 3, "stopped"))
	}
	// Retiring mainnet now drops ret0, the zone retired longest ago.
	uassert.NoError(t, r.ReviewZone("mainnet", Retired, rev(r, "mainnet"), curator, 4, "end of an era"))
	_, ok := r.Zone("ret0")
	uassert.False(t, ok)
	// And the next retirement drops ret1, not mainnet.
	uassert.NoError(t, r.Propose(curator, 5, "next", onyx()))
	uassert.NoError(t, r.ReviewZone("next", Approved, rev(r, "next"), curator, 5, ""))
	uassert.NoError(t, r.ReviewZone("next", Retired, rev(r, "next"), curator, 6, "stopped"))
	_, ok = r.Zone("mainnet")
	uassert.True(t, ok)
	_, ok = r.Zone("ret1")
	uassert.False(t, ok)
}

// Every decision on a zone names the revision it was made on.
func TestEveryZoneDecisionIsRevisionBound(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	old := rev(r, "onyx")
	edited := onyx()
	edited.Title = "Onyx, edited"
	uassert.NoError(t, r.Edit("onyx", old, edited, alice, 2, ""))
	uassert.ErrorContains(t, r.Edit("onyx", old, onyx(), curator, 3, ""), "changed since you read it")
	uassert.ErrorContains(t, r.ReviewZone("onyx", Rejected, old, curator, 3, "spam"), "changed since you read it")
	uassert.ErrorContains(t, r.RemoveZone("onyx", old), "changed since you read it")
	uassert.NoError(t, r.ReviewZone("onyx", Approved, rev(r, "onyx"), curator, 3, ""))
	uassert.ErrorContains(t, r.ReviewZone("onyx", Retired, old, curator, 4, "gone"), "changed since you read it")
	uassert.NoError(t, r.ReviewZone("onyx", Retired, rev(r, "onyx"), curator, 4, "gone"))
}

func TestCanonicalHostAndTextEdgeCases(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	// A peer's host loses its terminal dot, so the two spellings are one peer.
	_, err := r.Register(alice, 1, "onyx", Peer, nodeID+"@seed-1.onyx.example.com:26656", "")
	uassert.NoError(t, err)
	_, err = r.Register(alice, 1, "onyx", Peer, nodeID+"@seed-1.onyx.example.com.:26656", "")
	uassert.ErrorContains(t, err, "already lists that peer")
	// An IPv4 host with a terminal dot is refused: Go's dialer cannot use it.
	uassert.ErrorContains(t, ValidateEndpoint(RPC, "http://1.2.3.4.:26657"), "DNS name or an IPv4")
	uassert.ErrorContains(t, ValidateEndpoint(Peer, nodeID+"@1.2.3.4.:26656"), "DNS name or an IPv4")
	// A loopback or private host is a local zone's only.
	_, err = r.Register(alice, 1, "onyx", RPC, "http://127.0.0.1:26657", "")
	uassert.ErrorContains(t, err, "loopback or private")
	_, err = r.Register(alice, 1, "onyx", Peer, nodeID+"@10.1.2.3:26656", "")
	uassert.ErrorContains(t, err, "loopback or private")
	local := onyx()
	local.Kind, local.RPCURL = Local, "http://127.0.0.1:26657"
	uassert.NoError(t, r.Propose(alice, 1, "mine", local))
	_, err = r.Register(alice, 1, "mine", Peer, nodeID+"@127.0.0.1:26656", "")
	uassert.NoError(t, err)
	// Equivalent URL spellings are one endpoint.
	for _, pair := range [][2]string{
		{"https://h.example.com/path", "https://h.example.com/path?"},
		{"https://h.example.com?a=1", "https://h.example.com/?a=1"},
		{"https://h.example.com/%2F", "https://h.example.com/%2f"},
	} {
		uassert.Equal(t, Canonical(Indexer, pair[0]), Canonical(Indexer, pair[1]), pair[0])
	}
	uassert.ErrorContains(t, ValidateEndpoint(Indexer, "https://h.example.com/%7e"), "needs no escaping")
	uassert.ErrorContains(t, ValidateEndpoint(Indexer, "https://h.example.com/%41"), "needs no escaping")
	// Look-alike badges and characters that draw nothing.
	in := onyx()
	for _, title := range []string{"✔ official", "☑ mainnet", "\U0001D159", "main\U000E0100net", "x\ue000", "\u180b", "\u0378"} {
		in.Title = title
		uassert.Error(t, ValidateInfo(in), title)
	}
}

// The per-proposer and per-registrant caps are counts, and they follow every
// way a zone or an endpoint leaves.
func TestCountersFollowRemovals(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	a, _ := r.Register(alice, 1, "onyx", RPC, "https://a.example.com", "")
	_, _ = r.Register(alice, 1, "onyx", RPC, "https://b.example.com", "")
	uassert.Equal(t, 2, r.OwnerCount("onyx", alice))
	uassert.NoError(t, r.RemoveEndpoint(a))
	uassert.Equal(t, 1, r.OwnerCount("onyx", alice))
	uassert.NoError(t, r.RemoveZone("onyx", rev(r, "onyx")))
	uassert.Equal(t, 0, r.OwnerCount("onyx", alice))
	for i := 0; i < MaxPendingPerProposer; i++ {
		uassert.NoError(t, r.Propose(alice, 2, "p"+strconv.Itoa(i), onyx()))
	}
	uassert.ErrorContains(t, r.Propose(alice, 2, "over", onyx()), "pending proposals")
	uassert.NoError(t, r.ReviewZone("p0", Approved, rev(r, "p0"), curator, 3, ""))
	uassert.NoError(t, r.Propose(alice, 3, "over", onyx()))
}

func TestSoleApproved(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(curator, 1, "za", onyx()))
	_, ok := r.SoleApproved("onyx-1")
	uassert.False(t, ok, "pending is not approved")
	uassert.NoError(t, r.ReviewZone("za", Approved, rev(r, "za"), curator, 1, ""))
	z, ok := r.SoleApproved("onyx-1")
	uassert.True(t, ok)
	uassert.Equal(t, "za", z.Slug)
	uassert.NoError(t, r.Propose(curator, 1, "zb", onyx()))
	uassert.NoError(t, r.ReviewZone("zb", Approved, rev(r, "zb"), curator, 1, ""))
	_, ok = r.SoleApproved("onyx-1")
	uassert.False(t, ok, "two approved zones share it: no guess")
}

// A status change bumps the revision too: an approval prepared before a
// colleague's rejection fails instead of quietly reversing it.
func TestStatusChangeBumpsTheRevision(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	read := rev(r, "onyx")
	uassert.NoError(t, r.ReviewZone("onyx", Rejected, read, bob, 2, "phishing RPC"))
	uassert.ErrorContains(t, r.ReviewZone("onyx", Approved, read, curator, 3, ""), "changed since you read it")
	z, _ := r.Zone("onyx")
	uassert.Equal(t, "phishing RPC", z.Reason)
}

// Leaving the local kind is refused while the zone lists a private host.
// Leaving the local kind drops the private endpoints in the same edit, so
// nobody can block the edit by registering one again after each removal.
func TestLeavingLocalDropsPrivateEndpoints(t *testing.T) {
	r := NewRegistry()
	local := onyx()
	local.Kind, local.RPCURL = Local, "http://127.0.0.1:26657"
	uassert.NoError(t, r.Propose(alice, 1, "mine", local))
	priv, err := r.Register(alice, 1, "mine", Peer, nodeID+"@10.0.0.5:26656", "")
	uassert.NoError(t, err)
	flagged, err := r.Register(bob, 1, "mine", RPC, "http://localhost:1", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewEndpoint(flagged, Flagged, 0, curator, 1, "squatting"))
	pub, err := r.Register(alice, 1, "mine", RPC, "https://rpc.mine.example.com", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.Edit("mine", rev(r, "mine"), onyx(), alice, 2, ""))
	for _, id := range []int64{priv, flagged} {
		_, ok := r.Endpoint(id)
		uassert.False(t, ok, "a private endpoint is dropped")
	}
	_, ok := r.Endpoint(pub)
	uassert.True(t, ok, "a public one stays")
	uassert.Equal(t, 1, r.EndpointCount("mine", ""))
	uassert.Equal(t, 0, r.OwnerCount("mine", bob))
	uassert.Equal(t, 1, r.Awaiting("mine"))
}

// A curator's chain-id edit of a pending zone names the curator on the resets;
// only the proposer's own edit records nobody.
func TestResetNamesACuratorEditor(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	id, _ := r.Register(alice, 1, "onyx", RPC, "https://a.example.com", "")
	uassert.NoError(t, r.ReviewEndpoint(id, Verified, rev(r, "onyx"), curator, 2, ""))
	moved := onyx()
	moved.ChainID = "onyx-2"
	uassert.NoError(t, r.Edit("onyx", rev(r, "onyx"), moved, curator, 3, ""))
	e, _ := r.Endpoint(id)
	uassert.Equal(t, curator.String(), e.ReviewedBy.String())
}

func TestPrivateHostsAndURLForms(t *testing.T) {
	for _, h := range []string{"validator", "node", "printer.local", "metadata.google.internal", "router.home.arpa",
		"foo.localdomain", "a.localhost", "192.0.0.1", "198.18.0.1", "198.19.255.255", "224.0.0.1", "255.255.255.255",
		"127.1", "0x7f.1", "2130706433",
		"rpc.test", "node.lan", "nas.home", "dc.corp", "wiki.intranet", "box.private", "x.onion", "y.alt",
		"192.0.2.1", "198.51.100.7", "203.0.113.255",
		"gno.example", "x.invalid", "rpc.mail", "ipv4only.arpa"} {
		uassert.True(t, IsPrivateHost(h), h)
	}
	for _, h := range []string{"rpc.gno.land", "1.1.1.1", "198.20.0.1", "172.32.0.1", "gno.land.",
		"a.latest", "my.salt", "192.0.3.1", "198.51.101.1", "203.0.114.1",
		"example.com", "gmail.com", "x.arpa"} {
		uassert.False(t, IsPrivateHost(h), h)
	}
	// tcp:// and http:// are one rpc endpoint, the way gnokey dials them.
	uassert.Equal(t, Canonical(RPC, "tcp://h.example.com:26657"), Canonical(RPC, "http://h.example.com:26657"))
	uassert.Equal(t, Canonical(RPC, "tcp://h.example.com:80"), Canonical(RPC, "http://h.example.com"))
	// An empty query's ? goes; a query ending in ? keeps it.
	uassert.Equal(t, "https://h.example.com/p?a?", Canonical(Indexer, "https://h.example.com/p?a?"))
	// . and .. path segments are another spelling: refused.
	for _, u := range []string{"https://h.example.com/.", "https://h.example.com/./x", "https://h.example.com/a/..", "https://h.example.com/../a"} {
		uassert.ErrorContains(t, ValidateEndpoint(Indexer, u), "path segment", u)
	}
	uassert.NoError(t, ValidateEndpoint(Indexer, "https://h.example.com/a.b/..c/x."))
	in := onyx()
	for _, title := range []string{"⌛ pending", "❎ rejected", "√ ok", "\U0001F6D1 stop", "☒ no"} {
		in.Title = title
		uassert.ErrorContains(t, ValidateInfo(in), "status glyph", title)
	}
}

// A copied Registry value is the same registry: it shares the revision
// counter with the zones it shares, so no revision is handed out twice. With
// the counter inline, an edit through the copy and then one through the
// original would both produce the same revision number, and a decision made on
// the first content would pass against the second.
func TestCopiedRegistryIsTheSameRegistry(t *testing.T) {
	r1 := NewRegistry()
	uassert.NoError(t, r1.Propose(alice, 1, "onyx", onyx()))
	r2 := *r1
	in := onyx()
	in.Title = "via the copy"
	uassert.NoError(t, r2.Edit("onyx", rev(r1, "onyx"), in, alice, 2, ""))
	seen := rev(r1, "onyx") // what a curator read: the copy's content
	in.Title = "via the original"
	uassert.NoError(t, r1.Edit("onyx", seen, in, alice, 3, ""))
	uassert.True(t, rev(r1, "onyx") != seen, "a new content, a new revision")
	uassert.ErrorContains(t, r1.ReviewZone("onyx", Approved, seen, curator, 4, ""), "changed since you read it")
}
