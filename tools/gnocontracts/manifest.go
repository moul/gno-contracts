package main

import (
	"fmt"
)

// cmdManifest scans the contract trees and reconciles contracts.json in place:
// new packages are added, existing ones have their derived fields (dir, kind,
// name, version, deps) refreshed, and removed packages are dropped. Hand-
// authored fields (description, draft, published) are preserved by pkgpath.
func cmdManifest(root string) error {
	m, err := loadManifest(root)
	if err != nil {
		return err
	}
	scanned, err := scanContracts(root)
	if err != nil {
		return err
	}
	prev := m.byPkgPath()

	var added, updated, removed int
	next := make([]Contract, 0, len(scanned))
	seen := map[string]bool{}
	for _, c := range scanned {
		seen[c.PkgPath] = true
		if old, ok := prev[c.PkgPath]; ok {
			// preserve human-owned fields
			c.Description = old.Description
			c.Source = old.Source
			c.Draft = old.Draft
			c.Published = old.Published
			c.Upstream = old.Upstream           // preserved; may be refreshed below
			c.UpstreamMatch = old.UpstreamMatch // preserved; may be refreshed below
			updated++
		} else {
			added++
		}
		// Mark monorepo-origin packages: the un-versioned path exists in the
		// gnolang/gno checkout. Sticky once set (so it survives runs without
		// GNOROOT), refreshable when the monorepo copy is present.
		if u := unversioned(c.PkgPath); u != c.PkgPath && inMonorepo(u) {
			c.Upstream = u
		}
		// Classify how the versioned copy compares to the monorepo copy (needs
		// $GNOROOT/examples). Sticky: keep the stored value when unavailable.
		if mm := classifyContractUpstream(root, &c); mm != "" {
			c.UpstreamMatch = mm
		}
		if c.Published == nil {
			c.Published = map[string]Pub{}
		}
		// ensure a slot for every known network
		for _, n := range m.Networks {
			if _, ok := c.Published[n.Name]; !ok {
				c.Published[n.Name] = Pub{}
			}
		}
		next = append(next, c)
	}
	for _, old := range m.Contracts {
		if !seen[old.PkgPath] {
			removed++
			fmt.Printf("- removed %s (directory gone)\n", old.PkgPath)
		}
	}

	m.Contracts = next
	if err := m.save(root); err != nil {
		return err
	}
	fmt.Printf("manifest: %d contracts (%d added, %d updated, %d removed)\n",
		len(next), added, updated, removed)
	return nil
}
