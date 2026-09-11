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

	nets, checks := 0, 0
	for i := range m.Networks {
		net := m.Networks[i]
		if *only != "" && net.Name != *only {
			continue
		}
		nets++
		up := 0
		for j := range m.Contracts {
			c := &m.Contracts[j]
			if c.Draft {
				continue
			}
			// One probe is enough: since gnolang/gno#6162 a monorepo-origin
			// package sits at OUR exact pkgpath, so a hit on a mirrored
			// package is the genesis deployment and a hit on anything else
			// was published from this repo.
			uploaded := queryUploaded(net.RPC, c.PkgPath)
			if c.Published == nil {
				c.Published = map[string]Pub{}
			}
			pub := c.Published[net.Name]
			pub.Uploaded = uploaded
			pub.Which = whichFound(uploaded, c.Upstream != "")
			c.Published[net.Name] = pub
			if pub.Uploaded {
				up++
			}
			checks++
		}
		fmt.Printf("  %-12s %d uploaded / %d contracts\n", net.Name, up, len(m.Contracts))
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
	fmt.Printf("status: %d checks across %d network(s); contracts.json + README updated\n", checks, nets)
	return nil
}

// whichFound labels where an on-chain package came from: a mirrored package is
// deployed by the monorepo (genesis), anything else was published from here.
func whichFound(uploaded, mirrored bool) string {
	switch {
	case !uploaded:
		return ""
	case mirrored:
		return "monorepo"
	default:
		return "ours"
	}
}
