package main

// lookupNetwork resolves a network name against contracts.json. It used to
// serve `gnocontracts upload`, which wrapped gnopm; gnopm publishes directly
// now, and `status` still needs to name a network.

import (
	"fmt"
	"strings"
)

// lookupNetwork resolves a network name against the catalog, and names the ones
// it knows when the name is wrong.
func lookupNetwork(root, name string) (Network, error) {
	m, err := loadManifest(root)
	if err != nil {
		return Network{}, err
	}
	var known []string
	for _, n := range m.Networks {
		if n.Name == name {
			return n, nil
		}
		known = append(known, n.Name)
	}
	return Network{}, fmt.Errorf("unknown network %q; have: %s", name, strings.Join(known, ", "))
}
