package main

import (
	"fmt"
)

// plural renders ", and N more" for a list we only name the head of.
func plural(n int) string {
	if n <= 1 {
		return ""
	}
	return fmt.Sprintf(", and %d more", n-1)
}

// cmdManifest scans the contract trees and reconciles contracts.json in place:
// new packages are added, existing ones have their derived fields (dir, kind,
// name, version, deps) refreshed, and removed packages are dropped. Hand-
// authored fields (description, draft, published) are preserved by pkgpath.
func cmdManifest(root string) error {
	m, err := loadManifest(root)
	if err != nil {
		return err
	}
	// Networks are code-owned, not data-owned: reconcile them from
	// defaultNetworks() on every run. contracts.json is generated on main and
	// PRs may not touch it (no-generated-files guard), so a hand edit here could
	// never land — the only way to add or retire a chain is defaultNetworks(),
	// and this is what carries that edit into the catalog via `regen`.
	m.Networks = defaultNetworks()

	// Refuse rather than silently drop a superseded version: it would take
	// its on-chain publish status out of the catalog with it, and the catalog
	// is regenerated automatically, so nobody would be watching.
	if missing, err := unmaterialized(root); err != nil {
		return err
	} else if len(missing) > 0 {
		return fmt.Errorf("%d version(s) pinned in the lock are not materialized (%s%s). Run `gnopm sync` first",
			len(missing), missing[0], plural(len(missing)))
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
		// Mark monorepo-origin packages: since gnolang/gno#6162 every monorepo
		// package is versioned, so the counterpart sits at OUR exact pkgpath.
		//
		// Authoritative whenever $GNOROOT/examples can be read — INCLUDING the
		// negative case. A merely-sticky value survives a renumber and strands
		// the old package's upstream on whatever now occupies that pkgpath:
		// p/moul/addrset/v2 became addrset/v1 and inherited the previous
		// addrset/v1's upstream, so the catalog advertised a monorepo `src`
		// link for a package the monorepo does not have. Only when the
		// monorepo cannot be consulted do we keep what was stored.
		if monorepoAvailable() {
			if inMonorepo(c.PkgPath) {
				c.Upstream = c.PkgPath
			} else {
				c.Upstream, c.UpstreamMatch = "", ""
			}
		}
		// Classify how our copy compares to the monorepo one (needs
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
