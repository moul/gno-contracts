package zones

import (
	"chain/runtime"
	"strconv"
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
	invited = addrset.Set{}
	inviter = map[address]address{}
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
	flagged := ListEndpoints("staging", "", "flagged")
	uassert.Equal(t, 2, len(flagged))
	uassert.True(t, strings.Contains(flagged[0].Reason, "probed 2026-10-01"))
	uassert.Equal(t, Admin.String(), flagged[0].ReviewedBy.String())

	// Every seed endpoint is filed under its own zone, and only there.
	n := 0
	for _, s := range seeds() {
		uassert.Equal(t, len(s.endpoints), len(ListEndpoints(s.slug, "", "")), s.slug)
		for _, e := range ListEndpoints(s.slug, "", "") {
			uassert.Equal(t, s.slug, e.Zone)
		}
		n += len(s.endpoints)
	}
	uassert.Equal(t, n, len(reg.Endpoints(zones.EndpointFilter{})))
}

func TestReadsRefuseUnknownFilters(cur realm, t *testing.T) {
	reset()
	// The reads cross nothing, so a refusal is a plain panic, not an abort.
	uassert.PanicsContains(t, cur, "unknown status", func() { ListZones("official", "") })
	uassert.PanicsContains(t, cur, "unknown kind", func() { ListZones("", "betanet") })
	uassert.PanicsContains(t, cur, "unknown endpoint kind", func() { ListEndpoints("onyx", "grpc", "") })
	uassert.PanicsContains(t, cur, "unknown verification", func() { ListAddresses("onyx", "", "trusted") })
	// Every zone at once is not a read a node should be asked for.
	uassert.PanicsContains(t, cur, "name a zone", func() { ListEndpoints("", "", "") })
	uassert.PanicsContains(t, cur, "name a zone", func() { ListAddresses("  ", "rpc", "") })
	_, ok := GetZone("nope")
	uassert.False(t, ok)
	_, ok = GetEndpoint(9999)
	uassert.False(t, ok)
}

func TestProposeThenCurate(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	ProposeZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "for trying things",
		"devnet", "", "https://rpc.alice.example.com", "")
	z, ok := GetZone("alice-dev")
	urequire.True(t, ok)
	uassert.Equal(t, string(zones.Pending), string(z.Status))
	uassert.Equal(t, alice.String(), z.Proposer.String())
	uassert.Equal(t, "alice-dev", slugs(ListZones("pending", "")))

	// The proposer fills in an endpoint and edits the zone (its gnoweb URL)
	// while pending.
	id := RegisterEndpoint(cross(cur), "alice-dev", "peer", nodeID+"@alice.example.com:26656", "alice")
	// A proposer waits between their own edits: every edit bumps the revision a
	// curator's decision must name, and curators need a window to make one.
	uassert.AbortsContains(t, cur, "may act on it again in", func() {
		EditZone(cross(cur), "alice-dev", zrev("alice-dev"), "alicedev-1", "Alice's devnet", "for trying things",
			"devnet", "https://alice.example.com", "https://rpc.alice.example.com", "", "")
	})
	testing.SkipHeights(ReviewWindow)
	EditZone(cross(cur), "alice-dev", zrev("alice-dev"), "alicedev-1", "Alice's devnet", "for trying things",
		"devnet", "https://alice.example.com", "https://rpc.alice.example.com", "", "")
	uassert.AbortsContains(t, cur, "may act on it again in", func() {
		EditZone(cross(cur), "alice-dev", zrev("alice-dev"), "alicedev-1", "Alice's devnet", "for trying more",
			"devnet", "https://alice.example.com", "https://rpc.alice.example.com", "", "")
	})
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, "https://alice.example.com", z.GnowebURL)
	uassert.False(t, z.Reviewed()) // a pending edit is just an edit

	// Nobody but a curator approves, and bob cannot touch alice's proposal.
	uassert.AbortsContains(t, cur, "is not a curator", func() { ApproveZone(cross(cur), "alice-dev", zrev("alice-dev"), "") })
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only a curator, or the proposer", func() {
		EditZone(cross(cur), "alice-dev", zrev("alice-dev"), "x", "x", "", "devnet", "", "https://x.example.com", "", "")
	})
	uassert.AbortsContains(t, cur, "only a curator, or the proposer while it is pending", func() {
		RemoveZone(cross(cur), "alice-dev", zrev("alice-dev"))
	})
	uassert.AbortsContains(t, cur, "only a curator or its registrant", func() {
		RemoveEndpoint(cross(cur), id, erev(id))
	})
	uassert.AbortsContains(t, cur, "is not a curator", func() { VerifyEndpoint(cross(cur), id, zr(id), erev(id), "") })

	testing.SetRealm(testing.NewUserRealm(Admin))
	ApproveZone(cross(cur), "alice-dev", zrev("alice-dev"), "checked the node answers")
	VerifyEndpoint(cross(cur), id, zr(id), erev(id), "")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, string(zones.Approved), string(z.Status))
	uassert.Equal(t, "checked the node answers", z.Reason)
	uassert.Equal(t, 1, len(ListAddresses("alice-dev", "peer", "verified")))

	// Approved, it is the curator's to edit now, not the proposer's.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "only a curator, or the proposer while it is pending", func() {
		EditZone(cross(cur), "alice-dev", zrev("alice-dev"), "alicedev-1", "renamed", "", "devnet", "", "https://rpc.alice.example.com", "", "x")
	})

	// A curator's edit to a reviewed zone replaces the review on record, and
	// needs a reason, so the page never shows new values under the old review.
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "an edit needs a reason", func() {
		EditZone(cross(cur), "alice-dev", zrev("alice-dev"), "alicedev-1", "Alice's devnet", "", "devnet", "", "https://rpc2.alice.example.com", "", "")
	})
	EditZone(cross(cur), "alice-dev", zrev("alice-dev"), "alicedev-1", "Alice's devnet", "", "devnet", "", "https://rpc2.alice.example.com", "", "rpc moved")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, "https://rpc2.alice.example.com", z.RPCURL)
	uassert.Equal(t, "rpc moved", z.Reason)
	uassert.Equal(t, string(zones.Approved), string(z.Status))
	testing.SetRealm(testing.NewUserRealm(alice))
	// Nor hers to remove; and not even a curator removes an approved zone: it is
	// retired instead.
	uassert.AbortsContains(t, cur, "while it is pending, may remove", func() { RemoveZone(cross(cur), "alice-dev", zrev("alice-dev")) })
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "retire it instead", func() { RemoveZone(cross(cur), "alice-dev", zrev("alice-dev")) })
	uassert.AbortsContains(t, cur, "needs a reason", func() { RetireZone(cross(cur), "alice-dev", zrev("alice-dev"), "") })
	RetireZone(cross(cur), "alice-dev", zrev("alice-dev"), "alice turned it off")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, string(zones.Retired), string(z.Status))
	_, err := reg.Register(bob, 1, "alice-dev", zones.RPC, "https://late.example.com", "")
	uassert.ErrorContains(t, err, "takes no endpoints")

	// Retired, it is a record the curators keep: the proposer cannot erase it.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "while it is pending, may remove", func() { RemoveZone(cross(cur), "alice-dev", zrev("alice-dev")) })
	// Nor can a curator: a retired zone is kept on record.
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "kept on record", func() { RemoveZone(cross(cur), "alice-dev", zrev("alice-dev")) })
	_, ok = GetZone("alice-dev")
	uassert.True(t, ok)
}

// The printed command is pasted into a shell. The main RPC cannot carry shell
// syntax at all; the quote is defense in depth.
func TestQueryCommandQuotesTheRemote(t *testing.T) {
	reset()
	// Two layers. The main RPC cannot carry shell syntax at all: its host is
	// [A-Za-z0-9.-], its port digits, and a path, query or fragment is refused.
	// And the printed remote is single-quoted anyway, in case a later version
	// widens the validator.
	z, _ := GetZone("moul-staging")
	in := zones.Info{ChainID: runtime.ChainID(), Title: z.Title, Kind: z.Kind, RPCURL: "https://rpc.example.com/;id;"}
	uassert.ErrorContains(t, reg.Edit("moul-staging", zrev("moul-staging"), in, Admin, 1, "test"), "no path")
	in.RPCURL = "https://rpc.example.com:443"
	must(reg.Edit("moul-staging", zrev("moul-staging"), in, Admin, 1, "test"))
	got := queryCommand(`GetZone("onyx")`)
	uassert.Equal(t, `gnokey query vm/qeval -remote 'https://rpc.example.com:443' -data 'gno.land/r/moul/zones/v0.GetZone("onyx")'`, got)

	// Two approved zones on the same chain id: no -remote, rather than a guess.
	must(reg.Edit("staging", zrev("staging"), zones.Info{ChainID: runtime.ChainID(), Title: "S", Kind: zones.Devnet,
		RPCURL: "https://other.example.com"}, Admin, 1, "test"))
	uassert.Equal(t, `gnokey query vm/qeval -data 'gno.land/r/moul/zones/v0.GetZone("onyx")'`, queryCommand(`GetZone("onyx")`))
	uassert.ErrorContains(t, zones.ValidateEndpoint(zones.RPC, "https://rpc.example.com/'x"), "contains")
}

func TestRejectAndWithdraw(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "fake-mainnet", "gnoland-1", "Mainnet (faster!)", "",
		"mainnet", "", "https://rpc.fake.example.com", "")
	RegisterEndpoint(cross(cur), "fake-mainnet", "rpc", "https://bob.example.com", "")
	// A stranger cannot pin a pending proposal with an endpoint of their own.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "only its proposer or a curator may register", func() {
		RegisterEndpoint(cross(cur), "fake-mainnet", "rpc", "https://alice.example.com", "")
	})
	// A curator can.
	testing.SetRealm(testing.NewUserRealm(Admin))
	theirs := RegisterEndpoint(cross(cur), "fake-mainnet", "rpc", "https://curator.example.com", "")

	uassert.AbortsContains(t, cur, "needs a reason", func() { RejectZone(cross(cur), "fake-mainnet", zrev("fake-mainnet"), "  ") })
	RejectZone(cross(cur), "fake-mainnet", zrev("fake-mainnet"), "not the mainnet RPC")
	z, _ := GetZone("fake-mainnet")
	uassert.Equal(t, string(zones.Rejected), string(z.Status))
	uassert.Equal(t, "fake-mainnet", slugs(ListZones("rejected", "")))
	uassert.Equal(t, "mainnet onyx staging moul-staging", slugs(ListZones("approved", "")))

	// A rejected zone is the curators' record: its proposer cannot take it down
	// (and so cannot collect the deposit the curator paid to record the
	// rejection). A curator can.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "while it is pending, may remove", func() {
		RemoveZone(cross(cur), "fake-mainnet", zrev("fake-mainnet"))
	})
	testing.SetRealm(testing.NewUserRealm(Admin))
	RemoveEndpoint(cross(cur), theirs, erev(theirs))
	RemoveZone(cross(cur), "fake-mainnet", zrev("fake-mainnet"))
	_, ok := GetZone("fake-mainnet")
	uassert.False(t, ok)

	// A proposer withdrawing a PENDING zone waits out the review window, and cannot
	// while it carries somebody else's endpoint: the refund would go to them.
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "bob-again", "bob-1", "Bob again", "", "devnet", "", "https://rpc.bob.example.com", "")
	uassert.AbortsContains(t, cur, "may act on it again in", func() {
		RemoveZone(cross(cur), "bob-again", zrev("bob-again"))
	})
	testing.SetRealm(testing.NewUserRealm(Admin))
	RegisterEndpoint(cross(cur), "bob-again", "rpc", "https://curator2.example.com", "")
	testing.SkipHeights(ReviewWindow)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "must be removed first", func() {
		RemoveZone(cross(cur), "bob-again", zrev("bob-again"))
	})
}

// A registrant withdraws their endpoint only after the review window: removing and
// registering again every block would give it a new id faster than a curator
// could flag the old one.
func TestRegistrantWithdrawalWaits(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://cycle.example.com", "")
	uassert.AbortsContains(t, cur, "may be withdrawn in", func() { RemoveEndpoint(cross(cur), id, erev(id)) })
	testing.SkipHeights(ReviewWindow)
	RemoveEndpoint(cross(cur), id, erev(id))
	_, ok := GetEndpoint(id)
	uassert.False(t, ok)
}

func TestEndpointLifecycle(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://onyx-rpc.bob.example.com", "bob's node")
	e, ok := GetEndpoint(id)
	urequire.True(t, ok)
	uassert.Equal(t, string(zones.Unverified), string(e.Status))
	uassert.Equal(t, bob.String(), e.Registrant.String())

	// Unverified is listed, and a verified-only read leaves it out.
	uassert.Equal(t, 2, len(ListAddresses("onyx", "rpc", "")))
	uassert.Equal(t, 1, len(ListAddresses("onyx", "rpc", "verified")))

	uassert.AbortsContains(t, cur, "already lists that rpc", func() {
		RegisterEndpoint(cross(cur), "onyx", "rpc", "https://ONYX-rpc.bob.example.com", "")
	})
	uassert.AbortsContains(t, cur, "unknown endpoint kind", func() {
		RegisterEndpoint(cross(cur), "onyx", "grpc", "https://x.example.com", "")
	})
	uassert.AbortsContains(t, cur, "no zone", func() {
		RegisterEndpoint(cross(cur), "nope", "rpc", "https://x.example.com", "")
	})

	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "needs a reason", func() { FlagEndpoint(cross(cur), id, erev(id), "") })
	FlagEndpoint(cross(cur), id, erev(id), "answers for the wrong chain id")
	e, _ = GetEndpoint(id)
	uassert.Equal(t, string(zones.Flagged), string(e.Status))
	uassert.Equal(t, 1, len(ListEndpoints("onyx", "rpc", "flagged")))
	UnverifyEndpoint(cross(cur), id, erev(id), "bob fixed it")
	VerifyEndpoint(cross(cur), id, zr(id), erev(id), "")
	uassert.Equal(t, 2, len(ListAddresses("onyx", "rpc", "verified")))

	// Flagged, it is a warning: its registrant cannot take it down (and so
	// cannot wipe it by registering it again).
	testing.SetRealm(testing.NewUserRealm(Admin))
	FlagEndpoint(cross(cur), id, erev(id), "serves the wrong chain")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "a curator ruled on", func() { RemoveEndpoint(cross(cur), id, erev(id)) })
	// Unverified by a curator, it carries why: still not the registrant's to
	// take down, even after the review window, or removing and registering it
	// again would wipe the warning. A curator may.
	testing.SetRealm(testing.NewUserRealm(Admin))
	UnverifyEndpoint(cross(cur), id, erev(id), "key was sold; re-checking")
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	uassert.AbortsContains(t, cur, "a curator ruled on", func() { RemoveEndpoint(cross(cur), id, erev(id)) })
	testing.SetRealm(testing.NewUserRealm(Admin))
	RemoveEndpoint(cross(cur), id, erev(id))
	_, ok = GetEndpoint(id)
	uassert.False(t, ok)
	uassert.AbortsContains(t, cur, "no endpoint", func() { RemoveEndpoint(cross(cur), id, erev(id)) })
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
	uassert.AbortsContains(t, cur, "already invited", func() { AddCurator(cross(cur), alice) })
	// An invitation is not a seat: until alice accepts, the admin is still the
	// last curator, so a mistyped invite cannot strand the registry.
	uassert.True(t, IsInvited(alice))
	uassert.False(t, IsCurator(alice))
	uassert.Equal(t, 1, len(Curators()))
	uassert.AbortsContains(t, cur, "is the last curator", func() { RemoveCurator(cross(cur), Admin) })
	// Withdrawing an invitation works, and a withdrawn one cannot be accepted.
	AddCurator(cross(cur), bob)
	RemoveCurator(cross(cur), bob)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "has no curator invitation", func() { AcceptCurator(cross(cur)) })

	testing.SetRealm(testing.NewUserRealm(alice))
	AcceptCurator(cross(cur))
	uassert.True(t, IsCurator(alice))
	uassert.False(t, IsInvited(alice))
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "already a curator", func() { AddCurator(cross(cur), alice) })
	uassert.Equal(t, 2, len(Curators()))

	// A curator added by the admin curates on equal terms, the admin included.
	testing.SetRealm(testing.NewUserRealm(alice))
	ProposeZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "", "devnet", "", "https://rpc.alice.example.com", "")
	ApproveZone(cross(cur), "alice-dev", zrev("alice-dev"), "")
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
	ProposeZone(cross(cur), "evil", "evil-1", "[click](https://evil.example.com)", "**bold** | col",
		"devnet", "", "https://rpc.evil.example.com", "")
	RegisterEndpoint(cross(cur), "evil", "rpc", "https://rpc2.evil.example.com", "a|b")

	page := Render("zone/evil")
	uassert.False(t, strings.Contains(page, "[click](https://evil.example.com)"), "a title renders as text, not a link")
	uassert.False(t, strings.Contains(page, "**bold**"), "a description renders as text, not markup")
	uassert.True(t, strings.Contains(page, `a\|b`), "a label cannot open a table column")

	// A pipe in a title cannot open a column in the zone tables.
	ProposeZone(cross(cur), "evil-pipe", "evil-9", "Alice|official", "", "devnet", "", "https://rpc.pipe.example.com", "")
	uassert.True(t, strings.Contains(Render("proposals"), `[Alice\|official](/r/moul/zones/v0:zone/evil-pipe)`))

	// A scheme and host are stored lowercased, so the link is live (the
	// sanitizer gno's md.Link uses accepts lowercase http and https only) and
	// every later lowercasing is free; the path keeps its case.
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "upper", "upper-1", "Upper", "", "devnet", "HTTPS://Upper.example.com/Web", "HTTPS://rpc.upper.example.com", "")
	z, _ := GetZone("upper")
	uassert.Equal(t, "https://upper.example.com/Web", z.GnowebURL)
	uassert.Equal(t, "https://rpc.upper.example.com", z.RPCURL)
	// A proposal's URL is shown as code, to copy and check, not as a link.
	uassert.True(t, strings.Contains(Render("zone/upper"), "`https://upper.example.com/Web`"))
	uassert.False(t, strings.Contains(Render("zone/upper"), "](https://upper.example.com/Web)"))
	id := RegisterEndpoint(cross(cur), "upper", "faucet", "HTTP://f.upper.example.com", "")
	e, _ := GetEndpoint(id)
	uassert.Equal(t, "http://f.upper.example.com", e.Address)
	testing.SetRealm(testing.NewUserRealm(alice))

	uassert.AbortsContains(t, cur, "contains", func() {
		ProposeZone(cross(cur), "evil2", "evil-2", "x", "", "devnet", "", "https://rpc.evil.example.com/)[x](y", "")
	})
	uassert.AbortsContains(t, cur, "slug", func() {
		ProposeZone(cross(cur), "evil|3", "evil-3", "x", "", "devnet", "", "https://rpc.evil.example.com", "")
	})
}

func TestRenderPagesAnswer(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render("zone/nope"), "No such zone."))
	uassert.True(t, strings.Contains(Render("nope"), "No such page."))
	uassert.True(t, strings.Contains(Render("proposals"), "Nothing waiting for review."))
	uassert.True(t, strings.Contains(Render("zone/staging"), "⚠️ flagged: did not answer when probed 2026\\-10\\-01"))
}

// Every list is paginated and clamps a reader's ?page=, which is what keeps a
// full registry inside vm/qrender's gas. What a page reads is measured
// separately; this test pins only the paging.
func TestRenderPaginates(t *testing.T) {
	reset()
	for i := 0; i < 2*PageSize; i++ {
		slug := "z" + strconv.Itoa(i)
		must(reg.Propose(alice, 1, slug, info("c-"+strconv.Itoa(i), "Zone "+strconv.Itoa(i), "", "devnet", "", "https://r"+strconv.Itoa(i)+".example.com", "")))
		must(reg.ReviewZone(slug, zones.Approved, zrev(slug), Admin, 2, ""))
	}
	// 4 seeded + 50 = 54 approved, so 3 pages of 25.
	first := Render("")
	uassert.True(t, strings.Contains(first, "page 1 of 3"))
	uassert.True(t, strings.Contains(first, "Zone 20"))
	uassert.False(t, strings.Contains(first, "Zone 21"), "row 26 is on page 2")
	last := Render("?page=3")
	uassert.True(t, strings.Contains(last, "Zone 49"))
	uassert.False(t, strings.Contains(last, "Zone 45]"))
	uassert.True(t, strings.Contains(last, "page 3 of 3"))
	uassert.Equal(t, first, Render("?page=-1"))
	uassert.Equal(t, last, Render("?page=99999999999999999"))
	uassert.Equal(t, last, Render("?page=999999999999999999999999999999"), "past int is past the end, not page 1")
	uassert.Equal(t, last, Render("?page=%2B999999999999999999999999999999"), "a + sign does not change that")
	uassert.True(t, strings.Contains(Render("?page=%2B2"), "page 2 of 3"))
	uassert.Equal(t, first, Render("?page=-999999999999999999999999999999"))
	uassert.Equal(t, first, Render("?page=nope"))
	uassert.True(t, strings.Contains(Render("?status=nope"), "No such list."))

	for i := 0; i < PageSize+3; i++ {
		who := testutils.TestAddress("reg" + strconv.Itoa(i/10))
		_, err := reg.Register(who, 3, "z0", zones.RPC, "https://e"+strconv.Itoa(i)+".example.com", "")
		must(err)
	}
	_, err := reg.Register(alice, 3, "z0", zones.Peer, nodeID+"@p.example.com:26656", "")
	must(err)
	zp := Render("zone/z0")
	uassert.True(t, strings.Contains(zp, "page 1 of 2"))
	uassert.True(t, strings.Contains(zp, "**all (29)**"))
	uassert.True(t, strings.Contains(zp, `[rpc \(28\)](/r/moul/zones/v0:zone/z0?kind=rpc)`))
	peers := Render("zone/z0?kind=peer")
	uassert.True(t, strings.Contains(peers, "p.example.com"))
	uassert.False(t, strings.Contains(peers, "e0.example.com"))
	uassert.False(t, strings.Contains(peers, "page 1 of"), "one page needs no pager")
	uassert.True(t, strings.Contains(Render("zone/z0?kind=rpc&page=2"), "[previous](/r/moul/zones/v0:zone/z0?kind=rpc&page=1)"))
	uassert.True(t, strings.Contains(Render("zone/z0?kind=grpc"), "No such endpoint kind."))
}

// zrev is a zone's current revision, what a curator who just read it approves.
func zrev(slug string) int64 {
	z, _ := GetZone(slug)
	return z.Revision
}

// erev is an endpoint's revision, what a verdict or a removal names.
func erev(id int64) int64 {
	e, ok := GetEndpoint(id)
	if !ok {
		return 0
	}
	return e.Revision
}

// zr is the revision of an endpoint's zone, what a verification also names.
func zr(id int64) int64 {
	e, ok := GetEndpoint(id)
	if !ok {
		return 0
	}
	return zrev(e.Zone)
}

// An invitation dies with its inviter, can be listed, and the set is bounded.
func TestCuratorInvitations(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Admin))
	upper := address(strings.ToUpper(alice.String()))
	uassert.AbortsContains(t, cur, "lowercase", func() { AddCurator(cross(cur), upper) })

	AddCurator(cross(cur), alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	AcceptCurator(cross(cur))
	// alice invites bob, then is removed: bob's invitation goes with her.
	AddCurator(cross(cur), bob)
	uassert.Equal(t, bob.String(), Invited()[0].String())
	testing.SetRealm(testing.NewUserRealm(Admin))
	RemoveCurator(cross(cur), alice)
	uassert.False(t, IsInvited(bob))
	uassert.Equal(t, 0, len(Invited()))
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "has no curator invitation", func() { AcceptCurator(cross(cur)) })

	// Curators and open invitations together stop at MaxCurators.
	testing.SetRealm(testing.NewUserRealm(Admin))
	for i := 1; i < MaxCurators; i++ {
		AddCurator(cross(cur), testutils.TestAddress("c"+strconv.Itoa(i)))
	}
	uassert.AbortsContains(t, cur, "remove one first", func() { AddCurator(cross(cur), bob) })
	RemoveCurator(cross(cur), testutils.TestAddress("c1"))
	AddCurator(cross(cur), bob)
}

func TestRenderRoutesAreExact(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render("zone/onyx/approved-by-gno-core"), "No such page."))
	uassert.True(t, strings.Contains(Render("proposals/x"), "No such page."))
	uassert.True(t, strings.Contains(Render("zone"), "No such page."))
	uassert.True(t, strings.Contains(Render("zone/onyx?kind=%20rpc"), "No such endpoint kind."))
	uassert.True(t, strings.Contains(Render("zone/onyx?kind=seed"), "No seed endpoint registered yet."))
	uassert.True(t, strings.Contains(Render("zone/onyx"), "Approve revision") == false, "an approved zone offers no Approve")
}

// gnoweb turns an @name into a user-profile link with an icon; free text
// carries a backslash before every @ so a label cannot vouch for an account.
func TestMentionsAreEscaped(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Admin))
	RegisterEndpoint(cross(cur), "onyx", "rpc", "https://m.example.com", "run by @gnocore")
	page := Render("zone/onyx?kind=rpc")
	uassert.True(t, strings.Contains(page, `run by \@gnocore`))
	uassert.False(t, strings.Contains(page, "run by @gnocore"))
}

// The printed -remote is never one the same page flags.
func TestQueryCommandSkipsAFlaggedRemote(cur realm, t *testing.T) {
	reset()
	z, _ := GetZone("moul-staging")
	in := zones.Info{ChainID: runtime.ChainID(), Title: z.Title, Kind: z.Kind, RPCURL: z.RPCURL, GnowebURL: z.GnowebURL}
	must(reg.Edit("moul-staging", zrev("moul-staging"), in, Admin, 1, "test"))
	uassert.True(t, strings.Contains(queryCommand("X()"), "-remote 'https://rpc.gno-staging.moul.p2p.team'"))
	e, ok := reg.EndpointByAddress("moul-staging", zones.RPC, z.RPCURL)
	urequire.True(t, ok)
	must(reg.ReviewEndpoint(e.ID, zones.Flagged, 0, erev(e.ID), Admin, 2, "down"))
	uassert.False(t, strings.Contains(queryCommand("X()"), "-remote"))
}

// A proposer cannot wipe a curator's verdict by removing the zone and
// proposing it again.
func TestProposerCannotRemoveOverAVerdict(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "bobs", "bobs-1", "Bob's", "", "devnet", "", "https://rpc.bobs.example.com", "")
	id := RegisterEndpoint(cross(cur), "bobs", "peer", nodeID+"@p.bobs.example.com:26656", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	FlagEndpoint(cross(cur), id, erev(id), "malicious peer")
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	uassert.AbortsContains(t, cur, "a curator ruled on", func() {
		RemoveZone(cross(cur), "bobs", zrev("bobs"))
	})
}

// A bare g1 address in free text would become a profile link: its 1 is
// written as a character reference so the mention parser does not match.
func TestBareAddressesAreNotMentions(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Admin))
	RegisterEndpoint(cross(cur), "onyx", "rpc", "https://g.example.com", "run by "+Admin.String())
	page := Render("zone/onyx?kind=rpc")
	uassert.False(t, strings.Contains(page, "run by g1manfred"))
	uassert.True(t, strings.Contains(page, "run by g&#49;manfred"))
}

// The main RPC is marked where it is shown when its endpoint is flagged, so the
// official table and the zone page agree (TestQueryCommandSkipsAFlaggedRemote
// covers the printed command).
func TestFlaggedMainRPCIsMarked(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render(""), "`https://rpc.staging.gno.land` ⚠️ flagged"))
	uassert.True(t, strings.Contains(Render("zone/staging"), "`https://rpc.staging.gno.land` ⚠️ flagged"))
	uassert.False(t, strings.Contains(Render(""), "`https://rpc.gno.land` ⚠️"))
}

// A flagged gnoweb URL is shown as code and marked, never as a link the page's
// own endpoint table says not to use.
func TestFlaggedGnowebIsNotALink(t *testing.T) {
	reset()
	page := Render("zone/staging")
	uassert.True(t, strings.Contains(page, "`https://staging.gno.land` ⚠️ flagged"))
	uassert.False(t, strings.Contains(page, "](https://staging.gno.land)"))
}

// A curator's flag on an rpc endpoint under the tcp:// spelling still marks a
// main RPC written as http://, and the reverse: gnokey dials them alike.
func TestFlaggedRPCMatchesAcrossTcpAndHttp(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Admin))
	z, _ := GetZone("onyx")
	id := RegisterEndpoint(cross(cur), "onyx", "rpc", "tcp://rpc.tcp.example.com:26657", "")
	FlagEndpoint(cross(cur), id, erev(id), "down")
	in := zones.Info{ChainID: z.ChainID, Title: z.Title, Description: z.Description, Kind: z.Kind,
		GnowebURL: z.GnowebURL, RPCURL: "http://rpc.tcp.example.com:26657", GenesisURL: z.GenesisURL}
	must(reg.Edit("onyx", zrev("onyx"), in, Admin, 1, "moved"))
	uassert.True(t, strings.Contains(Render("zone/onyx"), "`http://rpc.tcp.example.com:26657` ⚠️ flagged"))

	id = RegisterEndpoint(cross(cur), "onyx", "rpc", "http://rpc.http.example.com:26657", "")
	FlagEndpoint(cross(cur), id, erev(id), "down")
	in.RPCURL = "tcp://rpc.http.example.com:26657"
	must(reg.Edit("onyx", zrev("onyx"), in, Admin, 2, "moved back"))
	uassert.True(t, strings.Contains(Render("zone/onyx"), "`tcp://rpc.http.example.com:26657` ⚠️ flagged"))
}

// A page offers an action only while somebody's call can succeed: with the
// review queue full, Propose stays for curators only; with the live registry
// full, Propose and a rejected zone's Approve give way to a note.
func TestFullQueuesSayWhoMayStillAct(t *testing.T) {
	reset()
	in := func(i int) zones.Info {
		return zones.Info{ChainID: "fill-" + strconv.Itoa(i), Title: "Fill", Kind: zones.Testnet,
			RPCURL: "https://rpc" + strconv.Itoa(i) + ".example.com"}
	}
	slug := func(i int) string { return "fill-" + strconv.Itoa(i) }
	who := func(i int) address { return testutils.TestAddress("p" + strconv.Itoa(i/zones.MaxPendingPerProposer)) }

	must(reg.Propose(alice, 1, "nope", in(-1)))
	must(reg.ReviewZone("nope", zones.Rejected, zrev("nope"), Admin, 1, "no"))
	uassert.True(t, strings.Contains(Render("zone/nope"), "Approve revision"))

	for i := 0; i < zones.MaxPending; i++ {
		must(reg.Propose(who(i), 2, slug(i), in(i)))
	}
	// The queue is full for everybody but curators: the note says so, and the
	// link stays, labelled for them.
	uassert.True(t, strings.Contains(Render(""), "proposals are full until one is reviewed or removed"))
	uassert.True(t, strings.Contains(Render(""), "curators only, while full"))

	// Approve the queue away, then keep proposing and approving until the live
	// registry is full: no proposal is waiting, so Propose is hidden by the
	// live cap alone.
	for i := 0; i < zones.MaxPending; i++ {
		must(reg.ReviewZone(slug(i), zones.Approved, zrev(slug(i)), Admin, 3, ""))
	}
	uassert.True(t, strings.Contains(Render(""), "func=ProposeZone"))
	for i := zones.MaxPending; reg.Live() < zones.MaxZones; i++ {
		must(reg.Propose(who(i), 4, slug(i), in(i)))
		must(reg.ReviewZone(slug(i), zones.Approved, zrev(slug(i)), Admin, 4, ""))
	}
	uassert.Equal(t, 0, reg.ZoneCount(zones.Pending))
	uassert.False(t, strings.Contains(Render("zone/nope"), "Approve revision"))
	uassert.True(t, strings.Contains(Render("zone/nope"), "approving it waits for a free slot"))
	uassert.False(t, strings.Contains(Render(""), "func=ProposeZone"), "the live cap binds curators too")
	uassert.True(t, strings.Contains(Render(""), "the registry is full at 256 live zones"))
}

// Withdrawing the zone is no way round an endpoint's own review window: the
// proposer removing it the block an endpoint appears would delete it before a
// curator could see it.
func TestRemoveZoneWaitsForItsEndpoints(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "bobs", "bobs-1", "Bob's", "", "devnet", "", "https://rpc.bobs.example.com", "")
	testing.SkipHeights(ReviewWindow)
	RegisterEndpoint(cross(cur), "bobs", "rpc", "https://fresh.bobs.example.com", "")
	uassert.AbortsContains(t, cur, "may be withdrawn in", func() { RemoveZone(cross(cur), "bobs", zrev("bobs")) })
	testing.SkipHeights(ReviewWindow)
	RemoveZone(cross(cur), "bobs", zrev("bobs"))
	_, ok := GetZone("bobs")
	uassert.False(t, ok)
}

// A rejected zone is a record, endpoints and all: its registrant cannot strip
// the evidence a rejection cites.
func TestRejectedZoneKeepsItsEndpoints(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "fake", "fake-1", "Fake", "", "devnet", "", "https://rpc.fake.example.com", "")
	id := RegisterEndpoint(cross(cur), "fake", "rpc", "https://phish.example.com", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	RejectZone(cross(cur), "fake", zrev("fake"), "its rpc is a phishing clone")
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	uassert.AbortsContains(t, cur, "is rejected, a record", func() { RemoveEndpoint(cross(cur), id, erev(id)) })
}

// Curators pass the admission gates: a flood that fills the review queue does
// not lock out the people who clear it. The hard caps still hold.
func TestCuratorsPassTheAdmissionGates(cur realm, t *testing.T) {
	reset()
	in := func(i int) zones.Info {
		return zones.Info{ChainID: "f-" + strconv.Itoa(i), Title: "F", Kind: zones.Testnet,
			RPCURL: "https://rpc" + strconv.Itoa(i) + ".example.com"}
	}
	for i := 0; i < zones.MaxPending; i++ {
		must(reg.Propose(testutils.TestAddress("p"+strconv.Itoa(i/zones.MaxPendingPerProposer)), 1, "f-"+strconv.Itoa(i), in(i)))
	}
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "waiting for review", func() {
		ProposeZone(cross(cur), "bobs", "bobs-1", "Bob's", "", "devnet", "", "https://rpc.bobs.example.com", "")
	})
	testing.SetRealm(testing.NewUserRealm(Admin))
	ProposeZone(cross(cur), "admins", "admins-1", "Admin's", "", "devnet", "", "https://rpc.admins.example.com", "")
	for i := 0; i < zones.MaxPendingPerProposer; i++ {
		ProposeZone(cross(cur), "a-"+strconv.Itoa(i), "a-"+strconv.Itoa(i), "A", "", "devnet", "", "https://rpc.a"+strconv.Itoa(i)+".example.com", "")
	}

	for i := 0; i < zones.MaxUnverifiedPerZone; i++ {
		_, err := reg.Register(testutils.TestAddress("r"+strconv.Itoa(i/zones.MaxEndpointsPerAddress)), 2, "onyx", zones.RPC,
			"https://n"+strconv.Itoa(i)+".example.com", "")
		must(err)
	}
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "waiting for review", func() {
		RegisterEndpoint(cross(cur), "onyx", "rpc", "https://bob.example.com", "")
	})
	testing.SetRealm(testing.NewUserRealm(Admin))
	for i := 0; reg.EndpointCount("onyx", "") < zones.MaxEndpointsPerZone; i++ {
		RegisterEndpoint(cross(cur), "onyx", "rpc", "https://c"+strconv.Itoa(i)+".example.com", "")
	}
	uassert.AbortsContains(t, cur, "is full at", func() {
		RegisterEndpoint(cross(cur), "onyx", "rpc", "https://over.example.com", "")
	})
}

// A flag can be restated with a new reason, so correcting one never passes
// through a state its registrant could remove it from.
func TestAFlagsReasonCanBeAmended(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://typo.example.com", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	FlagEndpoint(cross(cur), id, erev(id), "srves the wrong chian")
	FlagEndpoint(cross(cur), id, erev(id), "serves the wrong chain")
	e, _ := GetEndpoint(id)
	uassert.Equal(t, "serves the wrong chain", e.Reason)
	uassert.AbortsContains(t, cur, "already flagged", func() { FlagEndpoint(cross(cur), id, erev(id), "serves the wrong chain") })
	uassert.Equal(t, 0, reg.Awaiting("onyx"), "restating a flag does not count it twice")
}

// Only a flag under the kind a URL is shown as marks it: a listing under
// another kind is anybody's to make, so its flag never marks the zone's own
// URL. The genesis URL, which no kind lists, is never marked.
func TestOnlyTheShownKindsFlagMarks(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	z, _ := GetZone("mainnet")
	misKinded := []int64{
		RegisterEndpoint(cross(cur), "mainnet", "explorer", z.RPCURL, ""),
		RegisterEndpoint(cross(cur), "mainnet", "faucet", z.GnowebURL, ""),
		RegisterEndpoint(cross(cur), "mainnet", "explorer", z.GenesisURL, ""),
	}
	testing.SetRealm(testing.NewUserRealm(Admin))
	for _, id := range misKinded {
		FlagEndpoint(cross(cur), id, erev(id), "not that kind")
	}
	page := Render("zone/mainnet")
	uassert.False(t, strings.Contains(page, "` ⚠️ flagged"), "no fact is marked by another kind's flag")
	uassert.True(t, strings.Contains(page, "](https://gno.land)"))
	uassert.False(t, strings.Contains(Render(""), "`"+z.RPCURL+"` ⚠️"))

	// Its own kind's flag does mark it.
	e, ok := reg.EndpointByAddress("mainnet", zones.Gnoweb, z.GnowebURL)
	urequire.True(t, ok)
	FlagEndpoint(cross(cur), e.ID, erev(e.ID), "a phishing clone took the name")
	page = Render("zone/mainnet")
	uassert.True(t, strings.Contains(page, "`https://gno.land` ⚠️ flagged"))
	uassert.False(t, strings.Contains(page, "](https://gno.land)"))
}

// The note in place of an action says which cap is full, so it names what
// would free it.
func TestFullCapsSayWhatFreesThem(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Admin))
	for i := 0; reg.EndpointCount("onyx", "") < zones.MaxEndpointsPerZone; i++ {
		id := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://c"+strconv.Itoa(i)+".example.com", "")
		FlagEndpoint(cross(cur), id, erev(id), "spam")
	}
	page := Render("zone/onyx")
	uassert.True(t, strings.Contains(page, "endpoints are full at 128 until some are removed"))
	uassert.False(t, strings.Contains(page, "func=RegisterEndpoint"))

	for i := 0; reg.EndpointCount("mainnet", "") < zones.MaxUnverifiedPerZone+8; i++ {
		RegisterEndpoint(cross(cur), "mainnet", "rpc", "https://m"+strconv.Itoa(i)+".example.com", "")
	}
	uassert.True(t, reg.Awaiting("mainnet") >= zones.MaxUnverifiedPerZone)
	page = Render("zone/mainnet")
	uassert.True(t, strings.Contains(page, "endpoints are full until some are reviewed or removed"))
	uassert.True(t, strings.Contains(page, "curators only, while full"))
}

// An edited zone names its editor in full, as it does its proposer.
func TestEditorIsShownInFull(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Admin))
	z, _ := GetZone("onyx")
	EditZone(cross(cur), "onyx", z.Revision, z.ChainID, "Onyx, edited", z.Description, string(z.Kind),
		z.GnowebURL, z.RPCURL, z.GenesisURL, "a better title")
	uassert.True(t, strings.Contains(Render("zone/onyx"), "**edited** by `"+Admin.String()+"`"))
}

// A curator clears a cycling flood in one call; whatever a curator ruled on
// stays.
func TestClearUnreviewed(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	spam := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://spam1.example.com", "")
	RegisterEndpoint(cross(cur), "onyx", "rpc", "https://spam2.example.com", "")
	ruled := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://ruled.example.com", "")
	uassert.AbortsContains(t, cur, "is not a curator", func() { ClearUnreviewed(cross(cur), "onyx", reg.Revision()) })
	testing.SetRealm(testing.NewUserRealm(Admin))
	UnverifyEndpoint(cross(cur), ruled, erev(ruled), "looking into it")
	uassert.Equal(t, 2, ClearUnreviewed(cross(cur), "onyx", reg.Revision()))
	_, ok := GetEndpoint(spam)
	uassert.False(t, ok)
	_, ok = GetEndpoint(ruled)
	uassert.True(t, ok, "a curator's ruling is kept")
	uassert.Equal(t, 1, reg.OwnerCount("onyx", bob))
	uassert.Equal(t, 0, ClearUnreviewed(cross(cur), "onyx", reg.Revision()))
}

// The review windows are the full ReviewWindow, a block short is refused, and
// the zone's runs from its last edit by anybody.
func TestReviewWindowsAreExact(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "bobs", "bobs-1", "Bob's", "", "devnet", "", "https://rpc.bobs.example.com", "")
	id := RegisterEndpoint(cross(cur), "bobs", "rpc", "https://a.bobs.example.com", "")
	testing.SkipHeights(ReviewWindow - 1)
	uassert.AbortsContains(t, cur, "may be withdrawn in 1 blocks", func() { RemoveEndpoint(cross(cur), id, erev(id)) })
	uassert.AbortsContains(t, cur, "may act on it again in 1 blocks", func() {
		RemoveZone(cross(cur), "bobs", zrev("bobs"))
	})
	testing.SkipHeights(1)
	// A curator's edit restarts the proposer's window: it runs from the last
	// edit by anybody.
	testing.SetRealm(testing.NewUserRealm(Admin))
	z, _ := GetZone("bobs")
	EditZone(cross(cur), "bobs", z.Revision, z.ChainID, "Bob's, retitled", z.Description, string(z.Kind),
		z.GnowebURL, z.RPCURL, z.GenesisURL, "")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "may act on it again in", func() {
		RemoveZone(cross(cur), "bobs", zrev("bobs"))
	})
}

// A proposer's edit off local drops private endpoints only under the rules a
// removal by the proposer has: never somebody else's, never one a curator
// ruled on.
func TestProposerLeavingLocalMeetsTheWithdrawalRules(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "lab", "lab-1", "Lab", "", "local", "", "http://127.0.0.1:26657", "")
	mine := RegisterEndpoint(cross(cur), "lab", "rpc", "http://10.1.2.3:26657", "")
	leave := func() {
		z, _ := GetZone("lab")
		EditZone(cross(cur), "lab", z.Revision, z.ChainID, z.Title, z.Description, "devnet",
			"", "https://rpc.lab.example.com", "", "")
	}
	testing.SetRealm(testing.NewUserRealm(Admin))
	theirs := RegisterEndpoint(cross(cur), "lab", "rpc", "http://10.9.9.9:26657", "")
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	uassert.AbortsContains(t, cur, "which somebody else registered", leave)
	testing.SetRealm(testing.NewUserRealm(Admin))
	RemoveEndpoint(cross(cur), theirs, erev(theirs))
	FlagEndpoint(cross(cur), mine, erev(mine), "a trap")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "a curator ruled on", leave)
	testing.SetRealm(testing.NewUserRealm(Admin))
	UnverifyEndpoint(cross(cur), mine, erev(mine), "")
	RemoveEndpoint(cross(cur), mine, erev(mine))
	testing.SetRealm(testing.NewUserRealm(bob))
	fresh := RegisterEndpoint(cross(cur), "lab", "rpc", "http://10.4.4.4:26657", "")
	// Dropping it is withdrawing it, so it waits out its own review window.
	uassert.AbortsContains(t, cur, "may be withdrawn in", leave)
	testing.SkipHeights(ReviewWindow)
	leave()
	_, ok := GetEndpoint(fresh)
	uassert.False(t, ok, "the proposer's own, never ruled on, is dropped")
}

// A verdict a proposer's chain-id edit reset is still a record: the reset
// leaves a reason, so the registrant cannot then withdraw it.
func TestAResetVerdictIsNotWithdrawable(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "bobs", "bobs-1", "Bob's", "", "devnet", "", "https://rpc.bobs.example.com", "")
	id := RegisterEndpoint(cross(cur), "bobs", "rpc", "https://a.bobs.example.com", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	VerifyEndpoint(cross(cur), id, zr(id), erev(id), "answers bobs-1")
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	z, _ := GetZone("bobs")
	EditZone(cross(cur), "bobs", z.Revision, "bobs-2", z.Title, z.Description, string(z.Kind),
		z.GnowebURL, z.RPCURL, z.GenesisURL, "")
	e, _ := GetEndpoint(id)
	uassert.Equal(t, "", e.ReviewedBy.String())
	uassert.Equal(t, zones.ChainIDChanged, e.Reason)
	uassert.AbortsContains(t, cur, "a curator ruled on", func() { RemoveEndpoint(cross(cur), id, erev(id)) })
}

// The zone's own main RPC and gnoweb, under their own kind, are its proposer's
// or a curator's to list: a stranger's listing, flagged for its label, would
// mark the zone's own URL.
func TestTheZonesOwnURLsAreReserved(cur realm, t *testing.T) {
	reset()
	z, _ := GetZone("onyx")
	reg.RemoveEndpoint(mustRPC(t, "onyx", z.RPCURL))
	ge, ok := reg.EndpointByAddress("onyx", zones.Gnoweb, z.GnowebURL)
	urequire.True(t, ok)
	reg.RemoveEndpoint(ge.ID, ge.Revision)
	testing.SetRealm(testing.NewUserRealm(bob))
	for _, a := range []string{strings.ToUpper(z.RPCURL), " " + z.RPCURL, z.RPCURL + "\t"} {
		uassert.AbortsContains(t, cur, "onyx's own rpc", func() {
			RegisterEndpoint(cross(cur), "onyx", "rpc", a, "moved: use mine")
		})
	}
	uassert.AbortsContains(t, cur, "onyx's own gnoweb", func() {
		RegisterEndpoint(cross(cur), "onyx", "gnoweb", z.GnowebURL+"\t", "")
	})
	// Under another kind it is anybody's, and its flag marks nothing.
	RegisterEndpoint(cross(cur), "onyx", "explorer", z.RPCURL, "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	RegisterEndpoint(cross(cur), "onyx", "rpc", z.RPCURL, "gno core")
}

// mustRPC returns the id and revision of the rpc endpoint listing url.
func mustRPC(t *testing.T, slug, url string) (int64, int64) {
	e, ok := reg.EndpointByAddress(slug, zones.RPC, url)
	urequire.True(t, ok, url)
	return e.ID, e.Revision
}

// ClearUnreviewed takes only what the curator read: nothing registered after
// the revision they name, nothing a curator registered, nothing a curator
// ruled on (an unverify with no reason included), nothing a reset left.
func TestClearUnreviewedIsBoundToWhatWasRead(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "no zone", func() { ClearUnreviewed(cross(cur), "nope", reg.Revision()) })
	mine := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://curators-own.example.com", "")
	testing.SetRealm(testing.NewUserRealm(bob))
	spam := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://spam.example.com", "")
	ruled := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://ruled.example.com", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	FlagEndpoint(cross(cur), ruled, erev(ruled), "checking")
	UnverifyEndpoint(cross(cur), ruled, erev(ruled), "")
	read := reg.Revision()
	testing.SetRealm(testing.NewUserRealm(alice))
	late := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://late.example.com", "alice's node")
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.Equal(t, 1, ClearUnreviewed(cross(cur), "onyx", read))
	for id, kept := range map[int64]bool{mine: true, spam: false, ruled: true, late: true} {
		_, ok := GetEndpoint(id)
		uassert.Equal(t, kept, ok, strconv.FormatInt(id, 10))
	}
	uassert.True(t, strings.Contains(Render("zone/onyx"), "func=ClearUnreviewed"))
}

// A removal names the endpoint's revision: one written before a colleague's
// verdict fails rather than delete it unseen. A verified endpoint is its
// registrant's to take down; listing it again starts it unverified.
func TestRemovalIsBoundAndAVerifiedListingIsWithdrawable(cur realm, t *testing.T) {
	reset()
	uassert.Equal(t, int64(100), int64(ReviewWindow))
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://bobs-node.example.com", "")
	read := erev(id)
	testing.SetRealm(testing.NewUserRealm(Admin))
	VerifyEndpoint(cross(cur), id, zr(id), erev(id), "answers onyx-1")
	uassert.AbortsContains(t, cur, "changed since you read it", func() { RemoveEndpoint(cross(cur), id, read) })
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	RemoveEndpoint(cross(cur), id, erev(id))
	_, ok := GetEndpoint(id)
	uassert.False(t, ok)
}

// A proposer leaving local keeps every public endpoint, a curator's included:
// the withdrawal rules apply only to what the edit drops.
func TestLeavingLocalKeepsOthersPublicEndpoints(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "lab", "lab-1", "Lab", "", "local", "", "http://127.0.0.1:26657", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	pub := RegisterEndpoint(cross(cur), "lab", "rpc", "https://rpc.lab.example.com", "")
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	z, _ := GetZone("lab")
	EditZone(cross(cur), "lab", z.Revision, z.ChainID, z.Title, z.Description, "devnet", "", "https://rpc.lab.example.com", "", "")
	_, ok := GetEndpoint(pub)
	uassert.True(t, ok)
}

// The index's example asks the zone serving this chain for its peers only
// when it lists one; otherwise it asks onyx, which does.
func TestTheIndexExampleAlwaysAnswers(t *testing.T) {
	reset()
	z, _ := GetZone("moul-staging")
	in := zones.Info{ChainID: runtime.ChainID(), Title: z.Title, Kind: z.Kind, RPCURL: z.RPCURL, GnowebURL: z.GnowebURL}
	must(reg.Edit("moul-staging", zrev("moul-staging"), in, Admin, 1, "on this chain"))
	uassert.Equal(t, 0, reg.EndpointCount("moul-staging", zones.Peer))
	uassert.True(t, strings.Contains(Render(""), `ListAddresses("onyx", "peer", "verified")`))
}

// ClearUnreviewed keeps an endpoint a reset left with a reason: a curator
// verified it, and the proposer's chain-id edit undid that.
func TestClearKeepsAResetEndpoint(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "bobs", "bobs-1", "Bob's", "", "devnet", "", "https://rpc.bobs.example.com", "")
	id := RegisterEndpoint(cross(cur), "bobs", "rpc", "https://a.bobs.example.com", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	VerifyEndpoint(cross(cur), id, zr(id), erev(id), "")
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	z, _ := GetZone("bobs")
	EditZone(cross(cur), "bobs", z.Revision, "bobs-2", z.Title, z.Description, string(z.Kind), z.GnowebURL, z.RPCURL, z.GenesisURL, "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.Equal(t, 0, ClearUnreviewed(cross(cur), "bobs", reg.Revision()))
}

// The reservation exempts the zone's proposer and any curator, each alone.
func TestTheReservationsExemptions(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "bobs", "bobs-1", "Bob's", "", "devnet", "https://gnoweb.bobs.example.com", "https://rpc.bobs.example.com", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	ApproveZone(cross(cur), "bobs", zrev("bobs"), "")
	testing.SetRealm(testing.NewUserRealm(bob))
	RegisterEndpoint(cross(cur), "bobs", "rpc", "https://rpc.bobs.example.com", "mine") // the proposer
	testing.SetRealm(testing.NewUserRealm(Admin))
	RegisterEndpoint(cross(cur), "bobs", "gnoweb", "https://gnoweb.bobs.example.com", "") // a curator, not the proposer
}

// An edit cannot make a stranger's listing the zone's own: a curator removes
// it first.
func TestAnEditCannotAdoptAStrangersListing(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://rpc2.onyx.example.com", "official onyx rpc")
	testing.SetRealm(testing.NewUserRealm(Admin))
	z, _ := GetZone("onyx")
	edit := func() {
		EditZone(cross(cur), "onyx", zrev("onyx"), z.ChainID, z.Title, z.Description, string(z.Kind),
			z.GnowebURL, "https://rpc2.onyx.example.com", z.GenesisURL, "moved")
	}
	uassert.AbortsContains(t, cur, "a curator removes it before", edit)
	RemoveEndpoint(cross(cur), id, erev(id))
	edit()
}

// The Clear link reaches every page and kind, so it is offered only on the
// unfiltered view of a zone that takes endpoints, bound to the revision the
// page was rendered at; the call keeps an endpoint registered exactly at that
// revision's successor and clears one registered at it.
func TestTheClearLinksScope(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "onyx", "faucet", "https://spam.example.com", "")
	at := strconv.FormatInt(reg.Revision(), 10)
	uassert.True(t, strings.Contains(Render("zone/onyx"), "throughRevision="+at))
	uassert.False(t, strings.Contains(Render("zone/onyx?kind=rpc"), "func=ClearUnreviewed"))
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.Equal(t, 1, ClearUnreviewed(cross(cur), "onyx", erev(id)))
	RetireZone(cross(cur), "onyx", zrev("onyx"), "shut down")
	uassert.False(t, strings.Contains(Render("zone/onyx"), "func=ClearUnreviewed"), "a retired zone takes no endpoints")
}

// A registrant cannot withdraw an endpoint a curator unverified, even with no
// reason: the reviewer is the ruling.
func TestAReasonlessUnverifyIsARuling(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "onyx", "rpc", "https://bob.example.com", "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	FlagEndpoint(cross(cur), id, erev(id), "checking")
	UnverifyEndpoint(cross(cur), id, erev(id), "")
	e, _ := GetEndpoint(id)
	uassert.Equal(t, "", e.Reason)
	testing.SetRealm(testing.NewUserRealm(bob))
	testing.SkipHeights(ReviewWindow)
	uassert.AbortsContains(t, cur, "a curator ruled on", func() { RemoveEndpoint(cross(cur), id, erev(id)) })
}

// With no listing of its own kind at all, a flag under another kind still
// does not mark the zone's URL: there is no fallback.
func TestNoCrossKindFallback(cur realm, t *testing.T) {
	reset()
	z, _ := GetZone("mainnet")
	reg.RemoveEndpoint(mustRPC(t, "mainnet", z.RPCURL))
	testing.SetRealm(testing.NewUserRealm(bob))
	id := RegisterEndpoint(cross(cur), "mainnet", "explorer", z.RPCURL, "")
	testing.SetRealm(testing.NewUserRealm(Admin))
	FlagEndpoint(cross(cur), id, erev(id), "not an explorer")
	uassert.False(t, strings.Contains(Render("zone/mainnet"), "`"+z.RPCURL+"` ⚠️"))
}
