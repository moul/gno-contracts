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
//	go tool gnocontracts status -net topaz # a single network
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

	now := time.Now().UTC().Format(time.RFC3339)
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
			online := queryUploaded(net.RPC, c.PkgPath)
			if c.Published == nil {
				c.Published = map[string]Pub{}
			}
			pub := c.Published[net.Name]
			pub.Uploaded = online
			pub.CheckedAt = now
			c.Published[net.Name] = pub
			if online {
				up++
			}
			checks++
		}
		fmt.Printf("  %-12s %d uploaded / %d contracts\n", net.Name, up, len(m.Contracts))
	}
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
