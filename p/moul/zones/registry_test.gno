package zones

import (
	"strconv"
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
	uassert.ErrorContains(t, r.Propose("", 11, "other", onyx()), "proposer is not a valid address")
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
	uassert.NoError(t, r.ReviewZone("z0", Approved, curator, 2, ""))
	uassert.NoError(t, r.Propose(alice, 3, "one-more", onyx()))
	// So does a removed one.
	uassert.NoError(t, r.RemoveZone("z1"))
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
			uassert.NoError(t, r.ReviewZone("onyx", Approved, curator, 2, ""))
		case Rejected:
			uassert.NoError(t, r.ReviewZone("onyx", Rejected, curator, 2, "setup"))
		case Retired:
			uassert.NoError(t, r.ReviewZone("onyx", Approved, curator, 2, ""))
			uassert.NoError(t, r.ReviewZone("onyx", Retired, curator, 3, "setup"))
		}
		label := string(c.from) + " -> " + string(c.to)
		err := r.ReviewZone("onyx", c.to, curator, 9, c.reason)
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
	uassert.ErrorContains(t, r.Edit("onyx", in, "", 2, ""), "editor is not a valid address")
	uassert.NoError(t, r.Edit("onyx", in, alice, 2, ""))
	z, _ := r.Zone("onyx")
	uassert.Equal(t, in.GenesisURL, z.GenesisURL)
	uassert.False(t, z.Reviewed()) // pending: just an edit

	bad := in
	bad.RPCURL = ""
	uassert.ErrorContains(t, r.Edit("onyx", bad, alice, 2, ""), "rpc url is empty")
	uassert.ErrorContains(t, r.Edit("nope", in, alice, 2, ""), "no zone")
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "https://rpc.onyx.testnets.gno.land", z.RPCURL) // unchanged by the refused edit

	// Once reviewed, an edit is a decision: it needs a reason and an editor, and
	// it replaces the review on record.
	uassert.NoError(t, r.ReviewZone("onyx", Approved, curator, 3, "probed"))
	in.RPCURL = "https://rpc2.onyx.example"
	uassert.ErrorContains(t, r.Edit("onyx", in, curator, 4, ""), "an edit needs a reason")
	uassert.ErrorContains(t, r.Edit("onyx", in, "", 4, "moved"), "editor is not a valid address")
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "https://rpc.onyx.testnets.gno.land", z.RPCURL)
	uassert.Equal(t, "probed", z.Reason)
	uassert.NoError(t, r.Edit("onyx", in, bob, 5, "rpc moved"))
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "https://rpc2.onyx.example", z.RPCURL)
	uassert.Equal(t, bob.String(), z.ReviewedBy.String())
	uassert.Equal(t, int64(5), z.ReviewedAt)
	uassert.Equal(t, "rpc moved", z.Reason)
	uassert.Equal(t, string(Approved), string(z.Status))

	// A retired zone is a record: its retirement reason is not editable away.
	uassert.NoError(t, r.ReviewZone("onyx", Retired, curator, 6, "testnet ended"))
	uassert.ErrorContains(t, r.Edit("onyx", in, curator, 7, "typo"), "only a pending or approved zone can be edited")
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "testnet ended", z.Reason)
	// Nor is a rejected one.
	uassert.NoError(t, r.Propose(alice, 8, "nope", onyx()))
	uassert.NoError(t, r.ReviewZone("nope", Rejected, curator, 9, "dup"))
	uassert.ErrorContains(t, r.Edit("nope", onyx(), alice, 10, ""), "only a pending or approved zone can be edited")
}

// What was verified is that an endpoint answered for the zone's chain id, so
// changing the chain id un-verifies them; changing only the RPC does not.
func TestChainIDEditUnverifiesEndpoints(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(curator, 1, "onyx", onyx()))
	uassert.NoError(t, r.ReviewZone("onyx", Approved, curator, 1, ""))
	a, _ := r.Register(alice, 2, "onyx", RPC, "https://a.example", "")
	b, _ := r.Register(alice, 2, "onyx", Peer, nodeID+"@b.example:26656", "")
	f, _ := r.Register(alice, 2, "onyx", RPC, "https://f.example", "")
	uassert.NoError(t, r.ReviewEndpoint(a, Verified, curator, 3, ""))
	uassert.NoError(t, r.ReviewEndpoint(b, Verified, curator, 3, ""))
	uassert.NoError(t, r.ReviewEndpoint(f, Flagged, curator, 3, "down"))

	in := onyx()
	in.RPCURL = "https://rpc2.onyx.example"
	uassert.NoError(t, r.Edit("onyx", in, curator, 4, "rpc moved"))
	uassert.Equal(t, 2, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))

	in.ChainID = "onyx-2"
	uassert.NoError(t, r.Edit("onyx", in, curator, 5, "relaunched as onyx-2"))
	uassert.Equal(t, 0, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))
	e, _ := r.Endpoint(a)
	uassert.Equal(t, string(Unverified), string(e.Status))
	uassert.Equal(t, ChainIDChanged, e.Reason)
	uassert.Equal(t, int64(5), e.ReviewedAt)
	e, _ = r.Endpoint(f)
	uassert.Equal(t, string(Flagged), string(e.Status)) // a flag is not undone by an edit
	uassert.Equal(t, "down", e.Reason)
	// And they count against the review queue again: verifying one frees it.
	uassert.NoError(t, r.ReviewEndpoint(a, Verified, curator, 6, "answers onyx-2"))
	uassert.Equal(t, 1, len(r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})))

	// A pending zone is no exception: a proposer collecting verdicts for one
	// chain id and then switching it gets them all reset.
	uassert.NoError(t, r.Propose(alice, 7, "pend", onyx()))
	pid, _ := r.Register(alice, 7, "pend", RPC, "https://p.example", "")
	uassert.NoError(t, r.ReviewEndpoint(pid, Verified, curator, 8, ""))
	other := onyx()
	other.ChainID = "elsewhere-1"
	uassert.NoError(t, r.Edit("pend", other, alice, 9, ""))
	e, _ = r.Endpoint(pid)
	uassert.Equal(t, string(Unverified), string(e.Status))
	uassert.Equal(t, alice.String(), e.ReviewedBy.String())
	z, _ := r.Zone("pend")
	uassert.False(t, z.Reviewed()) // still a pending edit: the zone's own review is untouched
}

func TestRegisterAndFilter(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(curator, 1, "onyx", onyx()))
	uassert.NoError(t, r.ReviewZone("onyx", Approved, curator, 1, ""))

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
	_, err = r.Register(bob, 7, "onyx", Indexer, "https://indexer.example/API", "")
	uassert.NoError(t, err)
	_, err = r.Register(bob, 7, "onyx", Indexer, "https://INDEXER.example/API", "")
	uassert.ErrorContains(t, err, "already lists that indexer")
	_, err = r.Register(bob, 7, "onyx", Indexer, "https://indexer.example/api", "")
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

	uassert.NoError(t, r.ReviewEndpoint(rpc, Verified, curator, 8, "answers onyx-1"))
	vs := r.Endpoints(EndpointFilter{Zone: "onyx", Status: Verified})
	uassert.Equal(t, 1, len(vs))
	uassert.Equal(t, "answers onyx-1", vs[0].Reason)
	v, total := r.Count("onyx")
	uassert.Equal(t, 1, v)
	uassert.Equal(t, 5, total)

	uassert.ErrorContains(t, r.ReviewEndpoint(rpc, Verified, curator, 8, ""), "already verified")
	uassert.ErrorContains(t, r.ReviewEndpoint(peer, Flagged, curator, 8, ""), "needs a reason")
	uassert.ErrorContains(t, r.ReviewEndpoint(peer, "trusted", curator, 8, ""), "unknown verification")
	uassert.ErrorContains(t, r.ReviewEndpoint(peer, "", curator, 8, ""), "needs a verdict")
	uassert.ErrorContains(t, r.ReviewEndpoint(peer, " verified ", curator, 8, ""), "unknown verification")
	_, err = r.Register(bob, 7, "onyx", " rpc ", "not a url", "")
	uassert.ErrorContains(t, err, "unknown endpoint kind")
	// A scheme's case is not a different endpoint.
	_, err = r.Register(bob, 7, "onyx", Explorer, "HTTPS://Explorer.example/x", "")
	uassert.NoError(t, err)
	_, err = r.Register(bob, 7, "onyx", Explorer, "https://explorer.example/x", "")
	uassert.ErrorContains(t, err, "already lists that explorer")
	uassert.ErrorContains(t, r.ReviewEndpoint(999, Verified, curator, 8, ""), "no endpoint #999")
	uassert.ErrorContains(t, r.ReviewEndpoint(0, Verified, curator, 8, ""), "no endpoint #0")
	uassert.NoError(t, r.ReviewEndpoint(peer, Flagged, curator, 9, "wrong chain id"))
	uassert.NoError(t, r.ReviewEndpoint(peer, Unverified, curator, 10, "fixed, re-checking"))

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
	_, err := r.Register(alice, 2, "onyx", RPC, "https://a.example", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewZone("onyx", Rejected, curator, 3, "not a gno chain"))
	_, err = r.Register(alice, 4, "onyx", RPC, "https://b.example", "")
	uassert.ErrorContains(t, err, "is rejected and takes no endpoints")
}

func TestEndpointCapPerAddress(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	for i := 0; i < MaxEndpointsPerAddress; i++ {
		_, err := r.Register(alice, 2, "onyx", RPC, "https://n"+strconv.Itoa(i)+".example", "")
		uassert.NoError(t, err)
	}
	_, err := r.Register(alice, 2, "onyx", RPC, "https://over.example", "")
	uassert.ErrorContains(t, err, "the limit is")
	// Bob still can.
	_, err = r.Register(bob, 2, "onyx", RPC, "https://over.example", "")
	uassert.NoError(t, err)
}

func TestRemoveZone(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	_, err := r.Register(bob, 2, "onyx", RPC, "https://a.example", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewZone("onyx", Approved, curator, 3, ""))
	uassert.ErrorContains(t, r.RemoveZone("onyx"), "retire it instead")
	uassert.NoError(t, r.ReviewZone("onyx", Retired, curator, 4, "testnet ended"))
	uassert.ErrorContains(t, r.RemoveZone("onyx"), "kept on record")
	_, ok := r.Zone("onyx")
	uassert.True(t, ok)

	// A rejected zone is removable, endpoints and all.
	uassert.NoError(t, r.Propose(alice, 5, "spam", onyx()))
	_, err = r.Register(bob, 5, "spam", RPC, "https://a.example", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewZone("spam", Rejected, curator, 6, "not a network"))
	uassert.NoError(t, r.RemoveZone("spam"))
	_, ok = r.Zone("spam")
	uassert.False(t, ok)
	uassert.Equal(t, 0, len(r.Endpoints(EndpointFilter{Zone: "spam"})))
	uassert.Equal(t, 1, r.Len())
	uassert.ErrorContains(t, r.RemoveZone("spam"), "no zone")
	// The slug and the address are free again.
	uassert.NoError(t, r.Propose(bob, 7, "spam", onyx()))
	_, err = r.Register(bob, 8, "spam", RPC, "https://a.example", "")
	uassert.NoError(t, err)
}

func TestReviewNeedsAReviewer(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(alice, 1, "onyx", onyx()))
	uassert.ErrorContains(t, r.ReviewZone("onyx", Approved, "", 2, ""), "reviewer is not a valid address")
	z, _ := r.Zone("onyx")
	uassert.Equal(t, string(Pending), string(z.Status))
	id, err := r.Register(alice, 2, "onyx", RPC, "https://a.example", "")
	uassert.NoError(t, err)
	uassert.ErrorContains(t, r.ReviewEndpoint(id, Verified, "", 3, ""), "reviewer is not a valid address")
}

// A flood from many addresses fills the review queue and nothing above it.
func TestFloodCannotCrowdOutReviewedEntries(t *testing.T) {
	r := NewRegistry()
	uassert.NoError(t, r.Propose(curator, 1, "onyx", onyx()))
	uassert.NoError(t, r.ReviewZone("onyx", Approved, curator, 1, ""))
	for i := 0; i < MaxPending; i++ {
		uassert.NoError(t, r.Propose(testAddr(i), 2, "flood-"+strconv.Itoa(i), onyx()))
	}
	uassert.ErrorContains(t, r.Propose(bob, 3, "honest", onyx()), "waiting for review")
	uassert.Equal(t, MaxPending+1, r.Len())
	// Clearing one makes room.
	uassert.NoError(t, r.ReviewZone("flood-0", Rejected, curator, 4, "spam"))
	uassert.NoError(t, r.Propose(bob, 5, "honest", onyx()))

	// Endpoints: unverified ones have their own ceiling, and verifying frees it.
	ids := []int64{}
	for i := 0; i < MaxUnverifiedPerZone; i++ {
		id, err := r.Register(testAddr(i/MaxEndpointsPerAddress), 6, "onyx", RPC, "https://n"+strconv.Itoa(i)+".example", "")
		uassert.NoError(t, err)
		ids = append(ids, id)
	}
	_, err := r.Register(bob, 7, "onyx", RPC, "https://honest.example", "")
	uassert.ErrorContains(t, err, "waiting for review")
	uassert.NoError(t, r.ReviewEndpoint(ids[0], Verified, curator, 8, ""))
	_, err = r.Register(bob, 9, "onyx", RPC, "https://honest.example", "")
	uassert.NoError(t, err)
	// Flagging puts it back under the ceiling's count, which is now one over:
	// a review is never refused for the queue being full, a registration is.
	uassert.NoError(t, r.ReviewEndpoint(ids[0], Flagged, curator, 10, "spam"))
	_, err = r.Register(bob, 11, "onyx", RPC, "https://honest2.example", "")
	uassert.ErrorContains(t, err, "waiting for review")
	uassert.NoError(t, r.RemoveEndpoint(ids[1]))
	_, err = r.Register(bob, 12, "onyx", RPC, "https://honest2.example", "")
	uassert.ErrorContains(t, err, "waiting for review")
	uassert.NoError(t, r.RemoveEndpoint(ids[2]))
	_, err = r.Register(bob, 13, "onyx", RPC, "https://honest2.example", "")
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
	uassert.NoError(t, r.ReviewZone("mainnet", Approved, curator, 3, ""))
	uassert.NoError(t, r.ReviewZone("onyx", Approved, curator, 3, ""))

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
	uassert.NoError(t, r.ReviewZone("z1", Approved, curator, 2, ""))
	uassert.NoError(t, r.ReviewZone("z3", Approved, curator, 2, ""))
	uassert.NoError(t, r.ReviewZone("z5", Approved, curator, 2, ""))
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
	uassert.NoError(t, r.ReviewZone("z0", Rejected, curator, 3, "dup"))
	uassert.NoError(t, r.RemoveZone("z2"))
	uassert.Equal(t, "z4 z6 ", page(r.ZonePage(Pending, 1, 10)))
	uassert.Equal(t, "z0 ", page(r.ZonePage(Rejected, 1, 10)))
	uassert.Equal(t, "z1 z3 z5 ", page(r.Zones(ZoneFilter{Status: Approved})))

	// Chain ids are not unique, and the chain index follows an edit.
	uassert.Equal(t, 6, len(r.ZonesByChainID("onyx-1")))
	in := onyx()
	in.ChainID = "onyx-2"
	uassert.NoError(t, r.Edit("z1", in, curator, 4, "relaunched"))
	uassert.Equal(t, "z1 ", page(r.ZonesByChainID("onyx-2")))
	uassert.Equal(t, 5, len(r.ZonesByChainID("onyx-1")))
	uassert.NoError(t, r.RemoveZone("z0"))
	uassert.Equal(t, 4, len(r.ZonesByChainID("onyx-1")))

	// Endpoints: counts from the indexes, pages by kind.
	for i := 0; i < 5; i++ {
		_, err := r.Register(alice, 5, "z3", RPC, "https://e"+strconv.Itoa(i)+".example", "")
		uassert.NoError(t, err)
	}
	pid, err := r.Register(alice, 5, "z3", Peer, nodeID+"@p.example:26656", "")
	uassert.NoError(t, err)
	uassert.NoError(t, r.ReviewEndpoint(pid, Verified, curator, 6, ""))
	v, total := r.Count("z3")
	uassert.Equal(t, 1, v)
	uassert.Equal(t, 6, total)
	uassert.Equal(t, 5, r.EndpointCount("z3", RPC))
	uassert.Equal(t, 1, r.EndpointCount("z3", Peer))
	uassert.Equal(t, 0, r.EndpointCount("z3", Faucet))
	uassert.Equal(t, 6, r.EndpointCount("z3", ""))
	uassert.Equal(t, 1, len(r.EndpointPage("z3", RPC, 3, 2))) // page 3 of 5 rpcs at 2 a page holds one
	uassert.Equal(t, "https://e4.example", r.EndpointPage("z3", RPC, 3, 2)[0].Address)
	uassert.Equal(t, nodeID+"@p.example:26656", r.EndpointPage("z3", Peer, 1, 10)[0].Address)
	uassert.Equal(t, 6, len(r.EndpointPage("z3", "", 1, 10)))
	uassert.Equal(t, 1, len(r.Endpoints(EndpointFilter{Zone: "z3", Kind: Peer})))
	uassert.NoError(t, r.RemoveEndpoint(pid))
	uassert.Equal(t, 0, r.EndpointCount("z3", Peer))
	v, total = r.Count("z3")
	uassert.Equal(t, 0, v)
	uassert.Equal(t, 5, total)
}
