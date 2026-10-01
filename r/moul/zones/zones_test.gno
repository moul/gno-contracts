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
		"devnet", "", "https://rpc.alice.example", "")
	z, ok := GetZone("alice-dev")
	urequire.True(t, ok)
	uassert.Equal(t, string(zones.Pending), string(z.Status))
	uassert.Equal(t, alice.String(), z.Proposer.String())
	uassert.Equal(t, "alice-dev", slugs(ListZones("pending", "")))

	// The proposer fills in an endpoint and edits the description while pending.
	id := RegisterEndpoint(cross(cur), "alice-dev", "peer", nodeID+"@alice.example:26656", "alice")
	EditZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "for trying things",
		"devnet", "https://alice.example", "https://rpc.alice.example", "", "")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, "https://alice.example", z.GnowebURL)
	uassert.False(t, z.Reviewed()) // a pending edit is just an edit

	// Nobody but a curator approves, and bob cannot touch alice's proposal.
	uassert.AbortsContains(t, cur, "is not a curator", func() { ApproveZone(cross(cur), "alice-dev", zrev("alice-dev"), "") })
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only a curator, or the proposer", func() {
		EditZone(cross(cur), "alice-dev", "x", "x", "", "devnet", "", "https://x.example", "", "")
	})
	uassert.AbortsContains(t, cur, "only a curator, or the proposer while it is pending or rejected", func() {
		RemoveZone(cross(cur), "alice-dev")
	})
	uassert.AbortsContains(t, cur, "only a curator or its registrant", func() {
		RemoveEndpoint(cross(cur), id)
	})
	uassert.AbortsContains(t, cur, "is not a curator", func() { VerifyEndpoint(cross(cur), id, erev(id), "") })

	testing.SetRealm(testing.NewUserRealm(Admin))
	ApproveZone(cross(cur), "alice-dev", zrev("alice-dev"), "checked the node answers")
	VerifyEndpoint(cross(cur), id, erev(id), "")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, string(zones.Approved), string(z.Status))
	uassert.Equal(t, "checked the node answers", z.Reason)
	uassert.Equal(t, 1, len(ListAddresses("alice-dev", "peer", "verified")))

	// Approved, it is the curator's to edit now, not the proposer's.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "only a curator, or the proposer while it is pending", func() {
		EditZone(cross(cur), "alice-dev", "alicedev-1", "renamed", "", "devnet", "", "https://rpc.alice.example", "", "x")
	})

	// A curator's edit to a reviewed zone replaces the review on record, and
	// needs a reason, so the page never shows new values under the old review.
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "an edit needs a reason", func() {
		EditZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "", "devnet", "", "https://rpc2.alice.example", "", "")
	})
	EditZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "", "devnet", "", "https://rpc2.alice.example", "", "rpc moved")
	z, _ = GetZone("alice-dev")
	uassert.Equal(t, "https://rpc2.alice.example", z.RPCURL)
	uassert.Equal(t, "rpc moved", z.Reason)
	uassert.Equal(t, string(zones.Approved), string(z.Status))
	testing.SetRealm(testing.NewUserRealm(alice))
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
	// Nor can a curator: a retired zone is kept on record.
	testing.SetRealm(testing.NewUserRealm(Admin))
	uassert.AbortsContains(t, cur, "kept on record", func() { RemoveZone(cross(cur), "alice-dev") })
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
	in := zones.Info{ChainID: runtime.ChainID(), Title: z.Title, Kind: z.Kind, RPCURL: "https://rpc.example/;id;"}
	uassert.ErrorContains(t, reg.Edit("moul-staging", in, Admin, 1, "test"), "no path")
	in.RPCURL = "https://rpc.example:443"
	must(reg.Edit("moul-staging", in, Admin, 1, "test"))
	got := queryCommand(`GetZone("onyx")`)
	uassert.Equal(t, `gnokey query vm/qeval -remote 'https://rpc.example:443' -data 'gno.land/r/moul/zones/v0.GetZone("onyx")'`, got)

	// Two approved zones on the same chain id: no -remote, rather than a guess.
	must(reg.Edit("staging", zones.Info{ChainID: runtime.ChainID(), Title: "S", Kind: zones.Devnet,
		RPCURL: "https://other.example"}, Admin, 1, "test"))
	uassert.Equal(t, `gnokey query vm/qeval -data 'gno.land/r/moul/zones/v0.GetZone("onyx")'`, queryCommand(`GetZone("onyx")`))
	uassert.ErrorContains(t, zones.ValidateEndpoint(zones.RPC, "https://rpc.example/'x"), "contains")
}

func TestRejectAndWithdraw(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "fake-mainnet", "gnoland-1", "Mainnet (faster!)", "",
		"mainnet", "", "https://rpc.fake.example", "")
	RegisterEndpoint(cross(cur), "fake-mainnet", "rpc", "https://bob.example", "")
	// A stranger cannot pin a pending proposal with an endpoint of their own.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "only its proposer or a curator may register", func() {
		RegisterEndpoint(cross(cur), "fake-mainnet", "rpc", "https://alice.example", "")
	})
	// A curator can.
	testing.SetRealm(testing.NewUserRealm(Admin))
	theirs := RegisterEndpoint(cross(cur), "fake-mainnet", "rpc", "https://curator.example", "")

	uassert.AbortsContains(t, cur, "needs a reason", func() { RejectZone(cross(cur), "fake-mainnet", "  ") })
	RejectZone(cross(cur), "fake-mainnet", "not the mainnet RPC")
	z, _ := GetZone("fake-mainnet")
	uassert.Equal(t, string(zones.Rejected), string(z.Status))
	uassert.Equal(t, "fake-mainnet", slugs(ListZones("rejected", "")))
	uassert.Equal(t, "mainnet onyx staging moul-staging", slugs(ListZones("approved", "")))

	// The proposer can take a rejected proposal down, which frees the slug, but
	// not while it carries somebody else's endpoint: the deposit refund would
	// go to the proposer.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "must be removed first", func() { RemoveZone(cross(cur), "fake-mainnet") })
	testing.SetRealm(testing.NewUserRealm(Admin))
	RemoveEndpoint(cross(cur), theirs)
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
	VerifyEndpoint(cross(cur), id, erev(id), "")
	uassert.Equal(t, 2, len(ListAddresses("onyx", "rpc", "verified")))

	// Verified, it is a record other people rely on: its registrant cannot take
	// it down (and so cannot wipe a curator's verdict by registering it again).
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only a curator may remove it now", func() { RemoveEndpoint(cross(cur), id) })
	testing.SetRealm(testing.NewUserRealm(Admin))
	FlagEndpoint(cross(cur), id, "serves the wrong chain")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only a curator may remove it now", func() { RemoveEndpoint(cross(cur), id) })
	// Back to unverified, it is the registrant's to take down again.
	testing.SetRealm(testing.NewUserRealm(Admin))
	UnverifyEndpoint(cross(cur), id, "re-checking")
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
	ProposeZone(cross(cur), "alice-dev", "alicedev-1", "Alice's devnet", "", "devnet", "", "https://rpc.alice.example", "")
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
	ProposeZone(cross(cur), "evil", "evil-1", "[click](https://evil.example)", "**bold** | col",
		"devnet", "", "https://rpc.evil.example", "")
	RegisterEndpoint(cross(cur), "evil", "rpc", "https://rpc2.evil.example", "a|b")

	page := Render("zone/evil")
	uassert.False(t, strings.Contains(page, "[click](https://evil.example)"), "a title renders as text, not a link")
	uassert.False(t, strings.Contains(page, "**bold**"), "a description renders as text, not markup")
	uassert.True(t, strings.Contains(page, `a\|b`), "a label cannot open a table column")

	// A pipe in a title cannot open a column in the zone tables.
	ProposeZone(cross(cur), "evil-pipe", "evil-9", "Alice|official", "", "devnet", "", "https://rpc.pipe.example", "")
	uassert.True(t, strings.Contains(Render("proposals"), `[Alice\|official](/r/moul/zones/v0:zone/evil-pipe)`))

	// A scheme's case is stored lowercased, so the link is live: the sanitizer
	// gno's md.Link uses accepts lowercase http and https only.
	testing.SetRealm(testing.NewUserRealm(bob))
	ProposeZone(cross(cur), "upper", "upper-1", "Upper", "", "devnet", "HTTPS://Upper.example/Web", "HTTPS://rpc.upper.example", "")
	z, _ := GetZone("upper")
	uassert.Equal(t, "https://Upper.example/Web", z.GnowebURL)
	uassert.Equal(t, "https://rpc.upper.example", z.RPCURL)
	// A proposal's URL is shown as code, to copy and check, not as a link.
	uassert.True(t, strings.Contains(Render("zone/upper"), "`https://Upper.example/Web`"))
	uassert.False(t, strings.Contains(Render("zone/upper"), "](https://Upper.example/Web)"))
	id := RegisterEndpoint(cross(cur), "upper", "faucet", "HTTP://f.upper.example", "")
	e, _ := GetEndpoint(id)
	uassert.Equal(t, "http://f.upper.example", e.Address)
	testing.SetRealm(testing.NewUserRealm(alice))

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
	uassert.True(t, strings.Contains(Render("zone/staging"), "⚠️ flagged: did not answer when probed 2026\\-10\\-01"))
}

// Every list is paginated and clamps a reader's ?page=, and a page reads only
// its own rows: what keeps a full registry inside vm/qrender's gas.
func TestRenderPaginates(t *testing.T) {
	reset()
	for i := 0; i < 2*PageSize; i++ {
		slug := "z" + strconv.Itoa(i)
		must(reg.Propose(alice, 1, slug, info("c-"+strconv.Itoa(i), "Zone "+strconv.Itoa(i), "", "devnet", "", "https://r"+strconv.Itoa(i)+".example", "")))
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
		_, err := reg.Register(who, 3, "z0", zones.RPC, "https://e"+strconv.Itoa(i)+".example", "")
		must(err)
	}
	_, err := reg.Register(alice, 3, "z0", zones.Peer, nodeID+"@p.example:26656", "")
	must(err)
	zp := Render("zone/z0")
	uassert.True(t, strings.Contains(zp, "page 1 of 2"))
	uassert.True(t, strings.Contains(zp, "**all (29)**"))
	uassert.True(t, strings.Contains(zp, `[rpc \(28\)](/r/moul/zones/v0:zone/z0?kind=rpc)`))
	peers := Render("zone/z0?kind=peer")
	uassert.True(t, strings.Contains(peers, "p.example"))
	uassert.False(t, strings.Contains(peers, "e0.example"))
	uassert.False(t, strings.Contains(peers, "page 1 of"), "one page needs no pager")
	uassert.True(t, strings.Contains(Render("zone/z0?kind=rpc&page=2"), "[previous](/r/moul/zones/v0:zone/z0?kind=rpc&page=1)"))
	uassert.True(t, strings.Contains(Render("zone/z0?kind=grpc"), "No such endpoint kind."))
}

// zrev is a zone's current revision, what a curator who just read it approves.
func zrev(slug string) int64 {
	z, _ := GetZone(slug)
	return z.Revision
}

// erev is the revision of an endpoint's zone, what a curator verifies against.
func erev(id int64) int64 {
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
	RegisterEndpoint(cross(cur), "onyx", "rpc", "https://m.example", "run by @gnocore")
	page := Render("zone/onyx?kind=rpc")
	uassert.True(t, strings.Contains(page, `run by \@gnocore`))
	uassert.False(t, strings.Contains(page, "run by @gnocore"))
}

// The printed -remote is never one the same page flags.
func TestQueryCommandSkipsAFlaggedRemote(cur realm, t *testing.T) {
	reset()
	z, _ := GetZone("moul-staging")
	in := zones.Info{ChainID: runtime.ChainID(), Title: z.Title, Kind: z.Kind, RPCURL: z.RPCURL, GnowebURL: z.GnowebURL}
	must(reg.Edit("moul-staging", in, Admin, 1, "test"))
	uassert.True(t, strings.Contains(queryCommand("X()"), "-remote 'https://rpc.gno-staging.moul.p2p.team'"))
	e, ok := reg.EndpointByAddress("moul-staging", zones.RPC, z.RPCURL)
	urequire.True(t, ok)
	must(reg.ReviewEndpoint(e.ID, zones.Flagged, 0, Admin, 2, "down"))
	uassert.False(t, strings.Contains(queryCommand("X()"), "-remote"))
}
