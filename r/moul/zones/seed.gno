package zones

import (
	"chain/runtime"

	"gno.land/p/moul/zones/v0"
)

// seedReason is the review every seeded zone and endpoint carries, so a reader
// can tell a deploy-time entry from one a curator reviewed later, and knows how
// old the check is.
const seedReason = "seeded at deploy; probed 2026-10-01"

// seedZone is one zone the realm starts with, approved, plus the endpoints it
// starts with. verified says whether those endpoints answered when the seed was
// written: an endpoint that did not is still listed, as unverified, because the
// curator's word is the only thing seeding may not make up.
type seedZone struct {
	slug      string
	info      zones.Info
	verified  bool
	endpoints [][3]string // kind, address, label
}

// seeds are the four zones this registry opens with. Every address below was
// probed on 2026-10-01: each RPC's /status answered with the chain id given
// here, except staging, whose RPC answered "temporarily unavailable" and whose
// gnoweb answered 503, which is why its endpoints are seeded unverified. The
// peers are the persistent_peers each network's VALIDATOR.md publishes in the
// gnolang/gno monorepo, under misc/deployments.
var seeds = []seedZone{
	{
		slug: "mainnet",
		info: zones.Info{
			ChainID:     "gnoland-1",
			Title:       "gno.land mainnet",
			Description: "The gno.land mainnet, launched 2026-09-12.",
			Kind:        zones.Mainnet,
			GnowebURL:   "https://gno.land",
			RPCURL:      "https://rpc.gno.land",
			GenesisURL:  "https://github.com/gnolang/gno/releases/download/chain/mainnet/genesis.json",
		},
		verified: true,
		endpoints: [][3]string{
			{"rpc", "https://rpc.gno.land", "gno core"},
			{"gnoweb", "https://gno.land", "gno core"},
			{"peer", "g15rcv5yqef3kvnmueqvkyw8y05sd40jz9p3n5su@seed-1.gno.land:26656", "seed-1, gno core"},
			{"peer", "g1ck2yeyvvnpl92237gcea0z68jx07a4nnyvuaan@seed-2.gno.land:26656", "seed-2, gno core"},
			{"indexer", "https://indexer.gno.land/graphql/query", "gno core tx-indexer"},
			{"explorer", "https://gnoscope.com/?network=mainnet", "gnoscope"},
		},
	},
	{
		slug: "onyx",
		info: zones.Info{
			ChainID:     "onyx-1",
			Title:       "Onyx testnet",
			Description: "The gno.land testnet, launched 2026-09-28: mainnet's code, upgraded whenever mainnet is.",
			Kind:        zones.Testnet,
			GnowebURL:   "https://onyx.testnets.gno.land",
			RPCURL:      "https://rpc.onyx.testnets.gno.land",
			GenesisURL:  "https://github.com/gnolang/gno/releases/download/chain/onyx/genesis.json",
		},
		verified: true,
		endpoints: [][3]string{
			{"rpc", "https://rpc.onyx.testnets.gno.land", "gno core"},
			{"gnoweb", "https://onyx.testnets.gno.land", "gno core"},
			{"peer", "g1x5mlj5ava0dw9vkf4j6admjlzswm6f06p44krn@seed-1.onyx.testnets.gno.land:26656", "seed-1, gno core"},
			{"peer", "g1grq5zswt0dlwwe7clr4359w70k2ewgse0gcwck@seed-2.onyx.testnets.gno.land:26656", "seed-2, gno core"},
			{"indexer", "https://indexer.onyx.testnets.gno.land/graphql/query", "gno core tx-indexer"},
			{"faucet", "https://onyx.testnets.gno.land/faucet", "gno core"},
			{"explorer", "https://gnoscope.com/?network=onyx", "gnoscope"},
		},
	},
	{
		slug: "staging",
		info: zones.Info{
			ChainID:     "staging",
			Title:       "gno.land staging",
			Description: "gno core's staging network.",
			Kind:        zones.Devnet,
			GnowebURL:   "https://staging.gno.land",
			RPCURL:      "https://rpc.staging.gno.land",
		},
		verified: false,
		endpoints: [][3]string{
			{"rpc", "https://rpc.staging.gno.land", "gno core"},
			{"gnoweb", "https://staging.gno.land", "gno core"},
		},
	},
	{
		slug: "moul-staging",
		info: zones.Info{
			ChainID:     "moulstaging-1",
			Title:       "moul's gnodev staging",
			Description: "One gnodev node in staging mode, run by moul: a single validator, no consensus, worthless GNOT. Good for trying a deploy.",
			Kind:        zones.Devnet,
			GnowebURL:   "https://gno-staging.moul.p2p.team",
			RPCURL:      "https://rpc.gno-staging.moul.p2p.team",
		},
		verified: true,
		endpoints: [][3]string{
			{"rpc", "https://rpc.gno-staging.moul.p2p.team", "moul"},
			{"gnoweb", "https://gno-staging.moul.p2p.team", "moul"},
			{"faucet", "https://gno-staging.moul.p2p.team/faucet", "moul"},
		},
	},
}

// seed files every seed through the same Registry methods a caller's
// transaction goes through, so a seed that would fail validation fails the
// deploy instead of shipping a zone no later edit could reproduce.
func seed() {
	at := runtime.ChainHeight()
	for _, s := range seeds {
		must(reg.Propose(Admin, at, s.slug, s.info))
		must(reg.ReviewZone(s.slug, zones.Approved, Admin, at, seedReason))
		for _, e := range s.endpoints {
			k, err := zones.ParseEndpointKind(e[0])
			must(err)
			id, err := reg.Register(Admin, at, s.slug, k, e[1], e[2])
			must(err)
			if s.verified {
				must(reg.ReviewEndpoint(id, zones.Verified, Admin, at, seedReason))
			}
		}
	}
}
