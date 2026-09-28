package main

// Chain-facing helpers shared by `status` (is this package live on that
// network) and `graph` (dependency order). They used to live in publish.go
// beside a `gnocontracts publish` subcommand; publishing is gnopm's job now,
// and these outlived it.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"sort"
	"strings"
	"time"
)

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

// probe is the answer to "is this package on this chain": live, parked behind
// the submission policy, absent, or no answer at all.
type probe int

const (
	probeAbsent probe = iota
	probePresent
	probeUnknown
	probeParked
)

// pkgMeta is what vm/qpkgmeta_json answers for one path. Only Status is read
// here; creator, height, max_deposit, reason and pending come back in the same
// call and are what makes this query worth preferring, left for whoever needs
// them next.
type pkgMeta struct {
	Path   string `json:"path"`
	Status string `json:"status"` // "live" | "inert" | "absent"
}

// queryPkgStatus asks what a chain knows about pkgpath, via
// `gnokey query vm/qpkgmeta_json`.
//
// It replaces a vm/qfile probe, which cannot see a parked package. Under the
// inert code-submission policy a successful MsgAddPackage stores the bytes
// under inert_pkg:<path> and leaves the package unusable until an approver
// enables it; vm/qfile then answers "package is not available", character for
// character what it answers for a path nobody ever published. So a publish
// that is queued and a publish that never happened were the same empty cell in
// the README table, and the only way to tell them apart was to remember having
// sent it.
//
// qpkgmeta_json answers live / inert / absent in one call. Both chains that
// are up implement it (mainnet gnoland-1 and pearl, checked 2026-09-28); a
// chain that does not answers something this cannot parse, which is unknown
// and never absent.
func queryPkgStatus(rpc, pkgpath string) probe {
	// Bound each query so an unreachable/slow RPC can't stall the job.
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "gnokey", "query", "vm/qpkgmeta_json", "--data", pkgpath, "--remote", rpc)
	out, err := cmd.CombinedOutput()
	if err != nil {
		// Every failure is unknown, deliberately: an error we cannot classify
		// is not evidence of absence, and the caller leaves the recorded value
		// alone rather than inventing one.
		return probeUnknown
	}
	meta, ok := parsePkgMeta(out)
	if !ok {
		return probeUnknown
	}
	switch meta.Status {
	case "live":
		return probePresent
	case "inert":
		return probeParked
	case "absent":
		return probeAbsent
	}
	return probeUnknown
}

// parsePkgMeta pulls the JSON object out of gnokey's query output, which is a
// "height: 0" line followed by "data: {...}". Anything without a status field
// is not an answer we can read.
func parsePkgMeta(out []byte) (pkgMeta, bool) {
	i := bytes.IndexByte(out, '{')
	j := bytes.LastIndexByte(out, '}')
	if i < 0 || j < i {
		return pkgMeta{}, false
	}
	var m pkgMeta
	if err := json.Unmarshal(out[i:j+1], &m); err != nil || m.Status == "" {
		return pkgMeta{}, false
	}
	return m, true
}

// netReachable reports whether an RPC endpoint is answering at all, before any
// package is probed against it. One HTTP call decides for the whole network
// what no amount of per-package guessing can: a chain that is down and a
// package that was never published look identical from a single query.
func netReachable(rpc string) bool {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(strings.TrimSuffix(rpc, "/") + "/status")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 4096))
	return err == nil && strings.Contains(string(b), "\"result\"")
}

// chainIndex is every package path a chain holds, split by whether it is live
// or parked behind the submission policy.
//
// The two sets are disjoint and together cover everything the chain holds, so
// a path in neither is absent. That is what makes reading them worth it: a
// 288-package catalog costs two queries instead of 288, and 288 is roughly the
// number that gets rpc.gno.land's load balancer to answer 403 to everything
// for the next few minutes.
type chainIndex struct {
	live   map[string]bool
	parked map[string]bool
}

// queryChainIndex reads vm/qpaths and vm/qinertpaths, which between them name
// every package on the chain. Reports false if either query fails, so the
// caller can fall back to probing package by package: not every chain
// implements them, and a wrong answer here would be wrong for the whole
// catalog at once rather than for one row.
//
// vm/qpaths includes the stdlibs (`bufio`, `bytes`, `chain`, ...), which is
// harmless because every lookup against this index is a full `gno.land/...`
// package path and cannot collide with one.
func queryChainIndex(rpc string) (chainIndex, bool) {
	live, ok := queryPathSet(rpc, "vm/qpaths")
	if !ok {
		return chainIndex{}, false
	}
	parked, ok := queryPathSet(rpc, "vm/qinertpaths")
	if !ok {
		return chainIndex{}, false
	}
	return chainIndex{live: live, parked: parked}, true
}

// queryPathSet runs one whole-chain path query and reads its newline-separated
// answer. gnokey prints "height: N" then "data: " followed by the first path,
// with the rest on their own lines; an empty set is a "data:" line with
// nothing after it, which is a real answer and not a failure.
func queryPathSet(rpc, query string) (map[string]bool, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "gnokey", "query", query, "--remote", rpc).CombinedOutput()
	if err != nil {
		return nil, false
	}
	return parsePathSet(string(out))
}

// parsePathSet reads the newline-separated body of a whole-chain path query.
// Split out from the query so it can be tested against real gnokey output
// without a chain.
func parsePathSet(out string) (map[string]bool, bool) {
	i := strings.Index(out, "data: ")
	if i < 0 {
		return nil, false
	}
	set := map[string]bool{}
	for _, line := range strings.Split(out[i+len("data: "):], "\n") {
		if p := strings.TrimSpace(line); p != "" {
			set[p] = true
		}
	}
	return set, true
}

// lookup classifies one package path against a whole-chain index.
func (idx chainIndex) lookup(pkgpath string) probe {
	switch {
	case idx.live[pkgpath]:
		return probePresent
	case idx.parked[pkgpath]:
		return probeParked
	default:
		return probeAbsent
	}
}
