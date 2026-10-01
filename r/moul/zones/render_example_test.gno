package zones

// ExampleRender pins the index: the four seeded zones, official.
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # Zones
	//
	// A curated registry of gno.land networks and the endpoints that reach them. Anybody can propose a zone or register an endpoint; a curator approves, rejects, verifies or flags it, and every decision carries a public reason.
	//
	// ## Official
	//
	// | zone | chain id | kind | rpc | endpoints |
	// | --- | --- | --- | --- | --- |
	// | [gno\.land mainnet](/r/moul/zones/v0:zone/mainnet) | `gnoland-1` | mainnet | `https://rpc.gno.land` | 6 verified of 6 |
	// | [Onyx testnet](/r/moul/zones/v0:zone/onyx) | `onyx-1` | testnet | `https://rpc.onyx.testnets.gno.land` | 7 verified of 7 |
	// | [gno\.land staging](/r/moul/zones/v0:zone/staging) | `staging` | devnet | `https://rpc.staging.gno.land` | 0 verified of 2 |
	// | [moul's gnodev staging](/r/moul/zones/v0:zone/moul-staging) | `moulstaging-1` | devnet | `https://rpc.gno-staging.moul.p2p.team` | 3 verified of 3 |
	//
	// [0 proposal\(s\) waiting for review](/r/moul/zones/v0:proposals) · [Propose a zone](/r/moul/zones/v0$help&func=ProposeZone&chainID=&description=&genesisURL=&gnowebURL=&kind=testnet&rpcURL=&slug=&title=)
	//
	// ## Read it from a node
	//
	// Every list is a plain function, so a node operator or a script can ask for it directly. An empty argument matches anything.
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

// ExampleRender_zone pins one zone's page, endpoints grouped by kind.
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
	// - **genesis**: [genesis\.json](https://github.com/gnolang/gno/releases/download/chain/onyx/genesis.json)
	// - **proposed** by `g1manfre…dlf5` at block 123
	// - **approved** by `g1manfre…dlf5` at block 123: seeded at deploy; probed 2026\-10\-01
	//
	// ## Endpoints
	//
	// ### rpc
	//
	// | # | address | label | status | registered by |
	// | --- | --- | --- | --- | --- |
	// | 7 | `https://rpc.onyx.testnets.gno.land` | gno core | ✅ verified | `g1manfre…dlf5` |
	//
	// ### gnoweb
	//
	// | # | address | label | status | registered by |
	// | --- | --- | --- | --- | --- |
	// | 8 | `https://onyx.testnets.gno.land` | gno core | ✅ verified | `g1manfre…dlf5` |
	//
	// ### peer
	//
	// | # | address | label | status | registered by |
	// | --- | --- | --- | --- | --- |
	// | 9 | `g1x5mlj5ava0dw9vkf4j6admjlzswm6f06p44krn@seed-1.onyx.testnets.gno.land:26656` | seed\-1, gno core | ✅ verified | `g1manfre…dlf5` |
	// | 10 | `g1grq5zswt0dlwwe7clr4359w70k2ewgse0gcwck@seed-2.onyx.testnets.gno.land:26656` | seed\-2, gno core | ✅ verified | `g1manfre…dlf5` |
	//
	// ### indexer
	//
	// | # | address | label | status | registered by |
	// | --- | --- | --- | --- | --- |
	// | 11 | `https://indexer.onyx.testnets.gno.land/graphql/query` | gno core tx\-indexer | ✅ verified | `g1manfre…dlf5` |
	//
	// ### faucet
	//
	// | # | address | label | status | registered by |
	// | --- | --- | --- | --- | --- |
	// | 12 | `https://onyx.testnets.gno.land/faucet` | gno core | ✅ verified | `g1manfre…dlf5` |
	//
	// ### explorer
	//
	// | # | address | label | status | registered by |
	// | --- | --- | --- | --- | --- |
	// | 13 | `https://gnoscope.com/?network=onyx` | gnoscope | ✅ verified | `g1manfre…dlf5` |
	//
	// [Register an endpoint](/r/moul/zones/v0$help&func=RegisterEndpoint&addr=&kind=rpc&label=&slug=onyx) · [Retire](/r/moul/zones/v0$help&func=RetireZone&reason=&slug=onyx)
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
	must(reg.ReviewZone("fake-mainnet", "rejected", Admin, 202, "not the mainnet RPC"))
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
	// | [Alice's devnet](/r/moul/zones/v0:zone/alice-dev) | `alicedev-1` | devnet | `g1v9kxjc…40gh` | [Approve](/r/moul/zones/v0$help&func=ApproveZone&reason=&slug=alice-dev) · [Reject](/r/moul/zones/v0$help&func=RejectZone&reason=&slug=alice-dev) |
	//
	// ## Rejected
	//
	// | zone | chain id | proposed by | why |
	// | --- | --- | --- | --- |
	// | [Mainnet \(faster\!\)](/r/moul/zones/v0:zone/fake-mainnet) | `gnoland-1` | `g1vfhkyh…vdhu` | not the mainnet RPC |
	//
	// [All zones](/r/moul/zones/v0)
}
