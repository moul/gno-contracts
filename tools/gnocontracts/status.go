package main

import (
	"flag"
	"fmt"
	"os/exec"
	"time"
)

// unansweredStreakLimit is how many consecutive no-answers end a network's
// pass. Well under the count that means "this chain is genuinely missing
// everything", and low enough that a rate-limited run stops instead of
// spending ten minutes being refused.
const unansweredStreakLimit = 10

// cmdStatus refreshes the on-chain upload status of every (non-draft) contract
// across every configured network, then regenerates the README table. It is the
// entry point for the post-merge / manually-triggered CI job.
//
//	go tool gnocontracts status            # all networks in contracts.json
//	go tool gnocontracts status -net sapphire # a single network
//
// Uses read-only chain queries (vm/qpkgmeta_json) via gnokey: no key required.
func cmdStatus(root string, args []string) error {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	only := fs.String("net", "", "restrict to this network (default: all)")
	pace := fs.Duration("pace", 250*time.Millisecond, "wait between per-package queries, to stay under the RPC's rate limit")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if _, err := exec.LookPath("gnokey"); err != nil {
		return fmt.Errorf("status needs gnokey in PATH")
	}
	m, err := loadManifest(root)
	if err != nil {
		return err
	}

	nets, checks, skipped := 0, 0, 0
	for i := range m.Networks {
		net := m.Networks[i]
		if *only != "" && net.Name != *only {
			continue
		}
		// Ask the chain whether it is there at all, once, before probing 193
		// packages against it. A query to a chain that is down fails exactly
		// like a query for a package that was never published, and writing
		// that difference away is how sapphire came to be recorded as
		// hosting none of these packages while it was simply unreachable.
		if !netReachable(net.RPC) {
			skipped++
			fmt.Printf("  %-12s UNREACHABLE — keeping the last known status\n", net.Name)
			continue
		}
		nets++
		// Two whole-chain reads answer for every contract at once. Falling
		// back to a query each is correct but costs one per package, which
		// is what the pacing and the circuit breaker below exist to survive.
		idx, bulk := queryChainIndex(net.RPC)
		up, parked, unknown, streak := 0, 0, 0, 0
		for j := range m.Contracts {
			c := &m.Contracts[j]
			if c.Draft {
				continue
			}
			var state probe
			if bulk {
				state = idx.lookup(c.PkgPath)
			} else {
				// rpc.gno.land sits behind a load balancer that starts answering
				// 403 to every request, /status included, once queries arrive fast
				// enough. Probing a whole catalog back to back trips it: a run on
				// 2026-09-28 got 93 answers and then 195 refusals, and kept asking.
				// Pace the queries, and stop asking a chain that has stopped
				// answering rather than deepening the block.
				if streak >= unansweredStreakLimit {
					fmt.Printf("  %-12s stopped after %d unanswered in a row: the chain is refusing, not empty\n", net.Name, streak)
					break
				}
				time.Sleep(*pace)
				state = queryPkgStatus(net.RPC, c.PkgPath)
			}
			switch state {
			case probeUnknown:
				// The chain answered for others but not for this one. Leave
				// the recorded value as it was; do not invent an absence.
				unknown++
				streak++
				continue
			case probePresent:
				up++
			case probeParked:
				parked++
			}
			streak = 0
			c.setPublished(net.Name, state)
			checks++
		}
		note := ""
		if !bulk {
			note = "  (queried one by one: the chain did not answer vm/qpaths)"
		}
		if parked > 0 {
			note = fmt.Sprintf("  (%d queued behind the submission policy)", parked)
		}
		if unknown > 0 {
			note += fmt.Sprintf("  (%d unanswered, left as they were)", unknown)
		}
		fmt.Printf("  %-12s %d live / %d contracts%s\n", net.Name, up, len(m.Contracts), note)
	}
	if nets == 0 && skipped > 0 {
		return fmt.Errorf("no network answered (%d unreachable): nothing to refresh", skipped)
	}

	// One timestamp for the whole run, so per-contract entries only change when
	// their actual on-chain status changes (no churn on unchanged catalogs).
	m.StatusCheckedAt = time.Now().UTC().Format(time.RFC3339)
	if err := m.save(root); err != nil {
		return err
	}
	// reflect the refreshed status in the README table
	if err := cmdReadme(root); err != nil {
		return err
	}
	fmt.Printf("status: %d checks across %d reachable network(s), %d skipped; contracts.json + README updated\n", checks, nets, skipped)
	return nil
}

// setPublished records a probe result for one network, labelling where an
// on-chain package came from: a mirrored package is deployed by the monorepo
// (genesis), anything else was published from here.
//
// Only probePresent counts as uploaded. A parked package keeps its own state
// instead, because it is on the chain without being usable, and flattening
// that into the same empty cell as "never sent" is the thing this stopped
// doing.
func (c *Contract) setPublished(net string, state probe) {
	if c.Published == nil {
		c.Published = map[string]Pub{}
	}
	pub := c.Published[net]
	pub.Uploaded = state == probePresent
	pub.State = ""
	if state == probeParked {
		pub.State = "inert"
	}
	switch {
	case !pub.Uploaded:
		pub.Which = ""
	case c.Upstream != "":
		pub.Which = "monorepo"
	default:
		pub.Which = "ours"
	}
	c.Published[net] = pub
}
