package zones

import (
	"strings"
	"testing"

	"gno.land/p/moul/addrset/v1"
	"gno.land/p/moul/zones/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

const nodeID = "g15rcv5yqef3kvnmueqvkyw8y05sd40jz9p3n5su"

// reset puts the realm back to its init() state.
//
// Realm globals persist for the whole test binary and examples run after every
// Test, so without this an ExampleRender's pinned output depends silently on
// which tests ran before it.
func reset() {
	reg = zones.NewRegistry()
	curators = addrset.Set{}
	curators.Add(Admin)
	seed()
}

func slugs(zs []zones.Zone) string {
	out := []string{}
	for _, z := range zs {
		out = append(out, z.Slug)
	}
	return strings.Join(out, " ")
}

func TestRealmURLMatchesTheModule(cur realm, t *testing.T) {
	uassert.Equal(t, "gno.land"+realmURL, cur.PkgPath())
}

func TestSeeded(t *testing.T) {
	reset()
	uassert.Equal(t, "mainnet onyx staging moul-staging", slugs(ListZones("approved", "")))
	uassert.Equal(t, "", slugs(ListZones("pending", "")))
	uassert.Equal(t, "onyx", slugs(ListZones("", "testnet")))
	uassert.Equal(t, "staging moul-staging", slugs(ListZones("approved", "devnet")))

	z, ok := GetZone("onyx")
	urequire.True(t, ok)
	uassert.Equal(t, "onyx-1", z.ChainID)
	uassert.Equal(t, Admin.String(), z.ReviewedBy.String())
	uassert.Equal(t, seedReason, z.Reason)

	peers := ListAddresses("onyx", "peer", "verified")
	uassert.Equal(t, 2, len(peers))
	uassert.Equal(t, "g1x5mlj5ava0dw9vkf4j6admjlzswm6f06p44krn@seed-1.onyx.testnets.gno.land:26656", peers[0])
	uassert.Equal(t, "https://rpc.gno.land", strings.Join(ListAddresses("mainnet", "rpc", ""), ","))

	// staging did not answer when the seed was written, so nothing on it is
	// verified, but it is all listed.
	uassert.Equal(t, 0, len(ListEndpoints("staging", "", "verified")))
	uassert.Equal(t, 2, len(ListEndpoints("staging", "", "unverified")))

	// Every seed endpoint is filed under its own zone, and only there.
	for _, s := range seeds {
		uassert.Equal(t, len(s.endpoints), len(ListEndpoints(s.slug, "", "")), s.slug)
	}
}

func TestReadsRefuseUnknownFilters(cur realm, t *testing.T) {
	reset()
	// The reads cross nothing, so a refusal is a plain panic, not an abort.
	uassert.PanicsContains(t, cur, "unknown status", func() { ListZones("official", "") })
	uassert.PanicsContains(t, cur, "unknown kind", func() { ListZones("", "betanet") })
	uassert.PanicsContains(t, cur, "unknown endpoint kind", func() { ListEndpoints("onyx", "grpc", "") })
	uassert.PanicsContains(t, cur, "unknown verification", func() { ListAddresses("onyx", "", "trusted") })
	_, ok := GetZone("nope")
	uassert.False(t, ok)
	_, ok = GetEndpoint(9999)
	uassert.False(t, ok)
}

func TestProposeThenCurate(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	ProposeZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "for trying things",
		"devnet", "", "https://rpc.alice.example", "")
	z, ok := GetZone("alice-dev")
	urequire.True(t, ok)
	uassert.Equal(t, string(zones.Pending), string(z.Status))
	uassert.Equal(t, alice.String(), z.Proposer.String())
	uassert.Equal(t, "alice-dev", slugs(ListZones("pending", "")))

	// The proposer fills in an endpoint and edits the description while pending.
	id := RegisterEndpoint(cross(cur), "alice-dev", "peer", nodeID+"@alice.example:26656", "alice")
	EditZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "for trying things",
		"devnet", "https://alice.example", "https://rpc.alice.example", "")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, "https://alice.example", z.GnowebURL)

	// Nobody but a curator approves, and bob cannot touch alice's proposal.
	uassert.AbortsContains(t, cur, "is not a curator", func() { ApproveZone(cross(cur), "alice-dev", "") })
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only a curator, or the proposer", func() {
		EditZone(cross(cur), "alice-dev", "x", "x", "", "devnet", "", "https://x.example", "")
	})
	uassert.AbortsContains(t, cur, "only a curator, or the proposer while it is pending or rejected", func() {
		RemoveZone(cross(cur), "alice-dev")
	})
	uassert.AbortsContains(t, cur, "only a curator or its registrant", func() {
		RemoveEndpoint(cross(cur), id)
	})
	uassert.AbortsContains(t, cur, "is not a curator", func() { VerifyEndpoint(cross(cur), id, "") })

	testing.SetRealm(testing.NewUserRealm(Admin))
	ApproveZone(cross(cur), "alice-dev", "checked the node answers")
	VerifyEndpoint(cross(cur), id, "")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, string(zones.Approved), string(z.Status))
	uassert.Equal(t, "checked the node answers", z.Reason)
	uassert.Equal(t, 1, len(ListAddresses("alice-dev", "peer", "verified")))

	// Approved, it is the curator's to edit now, not the proposer's.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "only a curator, or the proposer while it is pending", func() {
		EditZone(cross(cur), "alice-dev", "alicedev-1", "renamed", "", "devnet", "", "https://rpc.alice.example", "")
	})
	// Nor hers to remove; and not even a curator removes it: it is retired.
	uassert.AbortsContains(t, cur, "while it is pending or rejected", func() { RemoveZone(cross(cur), "alice-dev") })
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "retire it instead", func() { RemoveZone(cross(cur), "alice-dev") })
	uassert.AbortsContains(t, cur, "needs a reason", func() { RetireZone(cross(cur), "alice-dev", "") })
	RetireZone(cross(cur), "alice-dev", "alice turned it off")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, string(zones.Retired), string(z.Status))
	_, err := reg.Register(bob, 1, "alice-dev", zones.RPC, "https://late.example", "")
	uassert.ErrorContains(t, err, "takes no endpoints")

	// Retired, it is a record the curators keep: the proposer cannot erase it.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "while it is pending or rejected", func() { RemoveZone(cross(cur), "alice-dev") })
	testing.SetRealm(testing.NewUserRealm(Admin))
	RemoveZone(cross(cur), "alice-dev")
	_, ok = GetZone("alice-dev")
	uassert.False(t, ok)
}

func TestRejectAndWithdraw(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "fake-mainnet", "gnoland-1", "Mainnet (faster!)", "",
		"mainnet", "", "https://rpc.fake.example", "")

	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "needs a reason", func() { RejectZone(cross(cur), "fake-mainnet", "  ") })
	RejectZone(cross(cur), "fake-mainnet", "not the mainnet RPC")
	z, _ := GetZone("fake-mainnet")
	uassert.Equal(t, string(zones.Rejected), string(z.Status))
	uassert.Equal(t, "fake-mainnet", slugs(ListZones("rejected", "")))
	uassert.Equal(t, "mainnet onyx staging moul-staging", slugs(ListZones("approved", "")))

	// The proposer can take a rejected proposal down, which frees the slug.
	testing.SetRealm(testing.NewUserRealm(bob))
	RemoveZone(cross(cur), "fake-mainnet")
	_, ok := GetZone("fake-mainnet")
	uassert.False(t, ok)
}

func TestEndpointLifecycle(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://onyx-rpc.bob.example", "bob's node")
	e, ok := GetEndpoint(id)
	urequire.True(t, ok)
	uassert.Equal(t, string(zones.Unverified), string(e.Status))
	uassert.Equal(t, bob.String(), e.Registrant.String())

	// Unverified is listed, and a verified-only read leaves it out.
	uassert.Equal(t, 2, len(ListAddresses("onyx", "rpc", "")))
	uassert.Equal(t, 1, len(ListAddresses("onyx", "rpc", "verified")))

	uassert.AbortsContains(t, cur, "already lists that rpc", func() {
		RegisterEndpoint(cross(cur), "onyx", "rpc", "https://ONYX-rpc.bob.example", "")
	})
	uassert.AbortsContains(t, cur, "unknown endpoint kind", func() {
		RegisterEndpoint(cross(cur), "onyx", "grpc", "https://x.example", "")
	})
	uassert.AbortsContains(t, cur, "no zone", func() {
		RegisterEndpoint(cross(cur), "nope", "rpc", "https://x.example", "")
	})

	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "needs a reason", func() { FlagEndpoint(cross(cur), id, "") })
	FlagEndpoint(cross(cur), id, "answers for the wrong chain id")
	e, _ = GetEndpoint(id)
	uassert.Equal(t, string(zones.Flagged), string(e.Status))
	uassert.Equal(t, 1, len(ListEndpoints("onyx", "rpc", "flagged")))
	UnverifyEndpoint(cross(cur), id, "bob fixed it")
	VerifyEndpoint(cross(cur), id, "")
	uassert.Equal(t, 2, len(ListAddresses("onyx", "rpc", "verified")))

	// Its registrant can take it down.
	testing.SetRealm(testing.NewUserRealm(bob))
	RemoveEndpoint(cross(cur), id)
	_, ok = GetEndpoint(id)
	uassert.False(t, ok)
	uassert.AbortsContains(t, cur, "no endpoint", func() { RemoveEndpoint(cross(cur), id) })
}

func TestCurators(cur realm, t *testing.T) {
	reset()
	uassert.True(t, IsCurator(Admin))
	uassert.False(t, IsCurator(alice))

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "is not a curator", func() { AddCurator(cross(cur), alice) })

	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "is the last curator", func() { RemoveCurator(cross(cur), Admin) })
	AddCurator(cross(cur), alice)
	uassert.AbortsContains(t, cur, "already a curator", func() { AddCurator(cross(cur), alice) })
	uassert.Equal(t, 2, len(Curators()))

	// A curator added by the admin curates on equal terms, the admin included.
	testing.SetRealm(testing.NewUserRealm(alice))
	ProposeZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "", "devnet", "", "https://rpc.alice.example", "")
	ApproveZone(cross(cur), "alice-dev", "")
	RemoveCurator(cross(cur), Admin)
	uassert.False(t, IsCurator(Admin))
	uassert.AbortsContains(t, cur, "is not a curator", func() { RemoveCurator(cross(cur), bob) })
}

// Every caller string a Render interpolates is escaped: a title that is a link,
// a reason that would open a table column. The shapes that can carry markup at
// all (slug, chain id, URL) are refused at write time instead, so they never
// reach a Render.
func TestRenderEscapesCallerText(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	ProposeZone(cross(cur), "evil", "evil-1", "[click](https://evil.example)", "**bold** | col",
		"devnet", "", "https://rpc.evil.example", "")
	RegisterEndpoint(cross(cur), "evil", "rpc", "https://rpc2.evil.example", "a|b")

	page := Render("zone/evil")
	uassert.False(t, strings.Contains(page, "[click](https://evil.example)"), "a title renders as text, not a link")
	uassert.False(t, strings.Contains(page, "**bold**"), "a description renders as text, not markup")
	uassert.True(t, strings.Contains(page, `a\|b`), "a label cannot open a table column")

	uassert.AbortsContains(t, cur, "contains", func() {
		ProposeZone(cross(cur), "evil2", "evil-2", "x", "", "devnet", "", "https://rpc.evil.example/)[x](y", "")
	})
	uassert.AbortsContains(t, cur, "slug", func() {
		ProposeZone(cross(cur), "evil|3", "evil-3", "x", "", "devnet", "", "https://rpc.evil.example", "")
	})
}

func TestRenderPagesAnswer(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render("zone/nope"), "No such zone."))
	uassert.True(t, strings.Contains(Render("nope"), "No such page."))
	uassert.True(t, strings.Contains(Render("proposals"), "Nothing waiting for review."))
	uassert.True(t, strings.Contains(Render("zone/staging"), "unverified"))
}
