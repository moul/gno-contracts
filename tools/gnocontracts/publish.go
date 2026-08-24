package main

import (
	"context"
	"flag"
	"fmt"
	"os/exec"
	"sort"
	"strings"
	"time"
)

// cmdPublish orders contracts by dependency (so a package is always published
// before anything that imports it) and, with -check -net <name>, queries the
// chain for current upload status and records it in contracts.json.
//
//	go run ./tools publish                 # print upload order
//	go run ./tools publish -net topaz -check   # + refresh on-chain status
func cmdPublish(root string, args []string) error {
	fs := flag.NewFlagSet("publish", flag.ContinueOnError)
	net := fs.String("net", "", "network name to check status against (see contracts.json)")
	check := fs.Bool("check", false, "query the chain for current upload status")
	if err := fs.Parse(args); err != nil {
		return err
	}
	m, err := loadManifest(root)
	if err != nil {
		return err
	}

	ordered, err := topoOrder(m.Contracts)
	if err != nil {
		return err
	}

	var network *Network
	if *net != "" {
		for i := range m.Networks {
			if m.Networks[i].Name == *net {
				network = &m.Networks[i]
			}
		}
		if network == nil {
			return fmt.Errorf("unknown network %q", *net)
		}
	}

	if *check {
		if network == nil {
			return fmt.Errorf("-check requires -net <name>")
		}
		if _, err := exec.LookPath("gnokey"); err != nil {
			return fmt.Errorf("-check needs gnokey in PATH")
		}
		byPath := m.byPkgPath()
		for _, c := range ordered {
			up := queryUploaded(network.RPC, c.PkgPath)
			pc := byPath[c.PkgPath]
			pub := pc.Published[network.Name]
			pub.Uploaded = up
			pc.Published[network.Name] = pub
		}
		if err := m.save(root); err != nil {
			return err
		}
		fmt.Printf("checked %d contracts on %s\n", len(ordered), network.Name)
	}

	fmt.Println("publish order (dependencies first):")
	for i, c := range ordered {
		status := ""
		if c.Draft {
			status = " [draft — skipped]"
		} else if network != nil {
			if m.byPkgPath()[c.PkgPath].Published[network.Name].Uploaded {
				status = " [already on " + network.Name + "]"
			} else {
				status = " [pending on " + network.Name + "]"
			}
		}
		fmt.Printf("  %2d. %s%s\n", i+1, c.PkgPath, status)
	}
	return nil
}

// topoOrder returns the contracts in dependency order (a contract appears after
// every moul contract it depends on). Non-moul deps are ignored (assumed to be
// stdlib or already on chain). Deterministic for stable output.
func topoOrder(contracts []Contract) ([]Contract, error) {
	inSet := map[string]Contract{}
	for _, c := range contracts {
		inSet[c.PkgPath] = c
	}
	// edges: dep -> dependents; indegree per node
	indeg := map[string]int{}
	deps := map[string][]string{}
	for _, c := range contracts {
		indeg[c.PkgPath] = indeg[c.PkgPath] // ensure present
		for _, d := range c.Deps {
			if d == c.PkgPath {
				continue // ignore self-deps so they can't fake a cycle
			}
			if _, ok := inSet[d]; ok {
				deps[c.PkgPath] = append(deps[c.PkgPath], d)
			}
		}
	}
	for _, c := range contracts {
		indeg[c.PkgPath] = len(deps[c.PkgPath])
	}

	// Kahn's algorithm with sorted queue for determinism.
	var ready []string
	for p, d := range indeg {
		if d == 0 {
			ready = append(ready, p)
		}
	}
	sort.Strings(ready)

	// reverse adjacency: dep -> things that depend on it
	dependents := map[string][]string{}
	for p, ds := range deps {
		for _, d := range ds {
			dependents[d] = append(dependents[d], p)
		}
	}

	var order []Contract
	for len(ready) > 0 {
		p := ready[0]
		ready = ready[1:]
		order = append(order, inSet[p])
		var newly []string
		for _, dep := range dependents[p] {
			indeg[dep]--
			if indeg[dep] == 0 {
				newly = append(newly, dep)
			}
		}
		sort.Strings(newly)
		ready = append(ready, newly...)
		sort.Strings(ready)
	}
	if len(order) != len(contracts) {
		return nil, fmt.Errorf("dependency cycle detected among contracts")
	}
	return order, nil
}

// queryUploaded reports whether pkgpath resolves on the given RPC, using
// `gnokey query vm/qfile`. A successful, non-empty response means the package
// exists on chain.
func queryUploaded(rpc, pkgpath string) bool {
	// Bound each query so an unreachable/slow RPC can't stall the job.
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "gnokey", "query", "vm/qfile", "--data", pkgpath, "--remote", rpc)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	s := strings.ToLower(string(out))
	if strings.Contains(s, "not found") || strings.Contains(s, "unknown") || strings.Contains(s, "error") {
		return false
	}
	return strings.TrimSpace(string(out)) != ""
}
