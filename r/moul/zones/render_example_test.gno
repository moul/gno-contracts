package zones

// ExampleRender pins the index: the four seeded zones, official.
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # Zones
	//
	// A curated registry of gno.land networks and the endpoints that reach them. Anybody can propose a zone, and register endpoints on an official one; a curator approves, rejects or retires a zone and verifies or flags its endpoints, and every rejection, retirement and flag says why, in public.
	//
	// ## Official
	//
	// | zone | chain id | kind | rpc | endpoints |
	// | --- | --- | --- | --- | --- |
	// | [gno\.land mainnet](/r/moul/zones/v0:zone/mainnet) | `gnoland-1` | mainnet | `https://rpc.gno.land` | 6 verified of 6 |
	// | [Onyx testnet](/r/moul/zones/v0:zone/onyx) | `onyx-1` | testnet | `https://rpc.onyx.testnets.gno.land` | 7 verified of 7 |
	// | [gno\.land staging](/r/moul/zones/v0:zone/staging) | `staging` | devnet | `https://rpc.staging.gno.land` ⚠️ flagged | 0 verified of 2 |
	// | [moul's gnodev staging](/r/moul/zones/v0:zone/moul-staging) | `moulstaging-1` | devnet | `https://rpc.gno-staging.moul.p2p.team` | 3 verified of 3 |
	//
	// [0 proposal\(s\) waiting for review](/r/moul/zones/v0:proposals) · [Propose a zone](/r/moul/zones/v0$help&func=ProposeZone&chainID=&description=&genesisURL=&gnowebURL=&kind=testnet&rpcURL=&slug=&title=)
	//
	// ## Read it from a node
	//
	// Every list is a plain function, so a node operator or a script can ask for it directly. An empty kind or status matches anything.
	//
	// ```
	// gnokey query vm/qeval -data 'gno.land/r/moul/zones/v0.ListAddresses("onyx", "peer", "verified")'
	// ```
	//
	// - `ListZones(status, kind)`: `approved` is the official list
	// - `GetZone(slug)`
	// - `ListEndpoints(slug, kind, status)`: kind is rpc, gnoweb, seed, peer, indexer, faucet or explorer
	// - `ListAddresses(slug, kind, status)`: the same, reduced to what a config file wants
	//
	// Curated by `g1manfre…dlf5`.
}

// ExampleRender_zone pins one zone's page: its facts, a link per endpoint kind,
// and its endpoints in id order.
func ExampleRender_zone() {
	reset()
	print(Render("zone/onyx"))
	// Output:
	// # Onyx testnet
	//
	// ✅ **official** · `onyx`
	//
	// The gno\.land testnet, launched 2026\-09\-28: mainnet's code, upgraded whenever mainnet is\.
	//
	// - **chain id**: `onyx-1`
	// - **kind**: testnet
	// - **rpc**: `https://rpc.onyx.testnets.gno.land`
	// - **gnoweb**: [https://onyx\.testnets\.gno\.land](https://onyx.testnets.gno.land)
	// - **genesis**: [https://github\.com/gnolang/gno/releases/download/chain/onyx/genesis\.json](https://github.com/gnolang/gno/releases/download/chain/onyx/genesis.json)
	// - **proposed** by `g1manfre…dlf5` at block 123
	// - **revision**: 4
	// - **last reviewed** by `g1manfre…dlf5` at block 123: seeded at deploy; probed 2026\-10\-01
	//
	// ## Endpoints
	//
	// **all (7)** · [rpc \(1\)](/r/moul/zones/v0:zone/onyx?kind=rpc) · [gnoweb \(1\)](/r/moul/zones/v0:zone/onyx?kind=gnoweb) · [peer \(2\)](/r/moul/zones/v0:zone/onyx?kind=peer) · [indexer \(1\)](/r/moul/zones/v0:zone/onyx?kind=indexer) · [faucet \(1\)](/r/moul/zones/v0:zone/onyx?kind=faucet) · [explorer \(1\)](/r/moul/zones/v0:zone/onyx?kind=explorer)
	//
	// | # | kind | address | label | status | registered by |
	// | --- | --- | --- | --- | --- | --- |
	// | 7 | rpc | `https://rpc.onyx.testnets.gno.land` | gno core | ✅ verified: seeded at deploy; probed 2026\-10\-01 (`g1manfre…dlf5`, block 123) | `g1manfre…dlf5` |
	// | 8 | gnoweb | `https://onyx.testnets.gno.land` | gno core | ✅ verified: seeded at deploy; probed 2026\-10\-01 (`g1manfre…dlf5`, block 123) | `g1manfre…dlf5` |
	// | 9 | peer | `g1x5mlj5ava0dw9vkf4j6admjlzswm6f06p44krn@seed-1.onyx.testnets.gno.land:26656` | seed\-1, gno core | ✅ verified: seeded at deploy; probed 2026\-10\-01 (`g1manfre…dlf5`, block 123) | `g1manfre…dlf5` |
	// | 10 | peer | `g1grq5zswt0dlwwe7clr4359w70k2ewgse0gcwck@seed-2.onyx.testnets.gno.land:26656` | seed\-2, gno core | ✅ verified: seeded at deploy; probed 2026\-10\-01 (`g1manfre…dlf5`, block 123) | `g1manfre…dlf5` |
	// | 11 | indexer | `https://indexer.onyx.testnets.gno.land/graphql/query` | gno core tx\-indexer | ✅ verified: seeded at deploy; probed 2026\-10\-01 (`g1manfre…dlf5`, block 123) | `g1manfre…dlf5` |
	// | 12 | faucet | `https://onyx.testnets.gno.land/faucet` | gno core | ✅ verified: seeded at deploy; probed 2026\-10\-01 (`g1manfre…dlf5`, block 123) | `g1manfre…dlf5` |
	// | 13 | explorer | `https://gnoscope.com/?network=onyx` | gnoscope | ✅ verified: seeded at deploy; probed 2026\-10\-01 (`g1manfre…dlf5`, block 123) | `g1manfre…dlf5` |
	//
	// [Register an endpoint](/r/moul/zones/v0$help&func=RegisterEndpoint&addr=&kind=rpc&label=&slug=onyx) · [Retire](/r/moul/zones/v0$help&func=RetireZone&reason=&revision=4&slug=onyx)
	//
	// ```
	// gnokey query vm/qeval -data 'gno.land/r/moul/zones/v0.GetZone("onyx")'
	// ```
	//
	// [All zones](/r/moul/zones/v0)
}

// ExampleRender_proposals pins the proposals page with one pending and one
// rejected zone, written straight to the registry: an Example has no realm
// token to cross with.
func ExampleRender_proposals() {
	reset()
	must(reg.Propose(alice, 200, "alice-dev", info("alicedev-1", "Alice's devnet", "", "devnet", "", "https://rpc.alice.example", "")))
	must(reg.Propose(bob, 201, "fake-mainnet", info("gnoland-1", "Mainnet (faster!)", "", "mainnet", "", "https://rpc.fake.example", "")))
	must(reg.ReviewZone("fake-mainnet", "rejected", zrev("fake-mainnet"), Admin, 202, "not the mainnet RPC"))
	print(Render("proposals"))
	// Output:
	// # Proposals
	//
	// Zones somebody proposed and no curator has approved. Only an approved zone is official.
	//
	// ## Pending
	//
	// | zone | chain id | kind | proposed by | review |
	// | --- | --- | --- | --- | --- |
	// | [Alice's devnet](/r/moul/zones/v0:zone/alice-dev) | `alicedev-1` | devnet | `g1v9kxjc…40gh` | [review](/r/moul/zones/v0:zone/alice-dev) |
	//
	// [1 rejected](/r/moul/zones/v0:proposals?status=rejected) · [All zones](/r/moul/zones/v0)
}

// ExampleRender_rejected pins the rejected list, which carries the reasons.
func ExampleRender_rejected() {
	reset()
	must(reg.Propose(bob, 201, "fake-mainnet", info("gnoland-1", "Mainnet (faster!)", "", "mainnet", "", "https://rpc.fake.example", "")))
	must(reg.ReviewZone("fake-mainnet", "rejected", zrev("fake-mainnet"), Admin, 202, "not the mainnet RPC"))
	print(Render("proposals?status=rejected"))
	// Output:
	// # Proposals
	//
	// Zones somebody proposed and no curator has approved. Only an approved zone is official.
	//
	// ## Rejected
	//
	// | zone | chain id | proposed by | why |  |
	// | --- | --- | --- | --- | --- |
	// | [Mainnet \(faster\!\)](/r/moul/zones/v0:zone/fake-mainnet) | `gnoland-1` | `g1vfhkyh…vdhu` | not the mainnet RPC | [Remove](/r/moul/zones/v0$help&func=RemoveZone&revision=10&slug=fake-mainnet) |
	//
	// [pending](/r/moul/zones/v0:proposals) · [All zones](/r/moul/zones/v0)
}
