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
	uassert.NoError(t, r.Edit("onyx", in))
	z, _ := r.Zone("onyx")
	uassert.Equal(t, in.GenesisURL, z.GenesisURL)

	in.RPCURL = ""
	uassert.ErrorContains(t, r.Edit("onyx", in), "rpc url is empty")
	uassert.ErrorContains(t, r.Edit("nope", in), "no zone")
	z, _ = r.Zone("onyx")
	uassert.Equal(t, "https://rpc.onyx.testnets.gno.land", z.RPCURL) // unchanged by the refused edit
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
