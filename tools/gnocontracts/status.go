package main

import (
	"flag"
	"fmt"
	"os/exec"
	"time"
)

// cmdStatus refreshes the on-chain upload status of every (non-draft) contract
// across every configured network, then regenerates the README table. It is the
// entry point for the post-merge / manually-triggered CI job.
//
//	go tool gnocontracts status            # all networks in contracts.json
//	go tool gnocontracts status -net sapphire # a single network
//
// Uses read-only chain queries (vm/qfile) via gnokey — no key required.
func cmdStatus(root string, args []string) error {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	only := fs.String("net", "", "restrict to this network (default: all)")
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
		up, unknown := 0, 0
		for j := range m.Contracts {
			c := &m.Contracts[j]
			if c.Draft {
				continue
			}
			// One probe is enough: since gnolang/gno#6162 a monorepo-origin
			// package sits at OUR exact pkgpath, so a hit on a mirrored
			// package is the genesis deployment and a hit on anything else
			// was published from this repo.
			switch queryUploaded(net.RPC, c.PkgPath) {
			case probeUnknown:
				// The chain answered for others but not for this one. Leave
				// the recorded value as it was; do not invent an absence.
				unknown++
				continue
			case probePresent:
				up++
				c.setPublished(net.Name, true)
			case probeAbsent:
				c.setPublished(net.Name, false)
			}
			checks++
		}
		note := ""
		if unknown > 0 {
			note = fmt.Sprintf("  (%d unanswered, left as they were)", unknown)
		}
		fmt.Printf("  %-12s %d uploaded / %d contracts%s\n", net.Name, up, len(m.Contracts), note)
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
func (c *Contract) setPublished(net string, uploaded bool) {
	if c.Published == nil {
		c.Published = map[string]Pub{}
	}
	pub := c.Published[net]
	pub.Uploaded = uploaded
	switch {
	case !uploaded:
		pub.Which = ""
	case c.Upstream != "":
		pub.Which = "monorepo"
	default:
		pub.Which = "ours"
	}
	c.Published[net] = pub
}
