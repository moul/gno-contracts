package main

// Chain-facing helpers shared by `status` (is this package live on that
// network) and `graph` (dependency order). They used to live in publish.go
// beside a `gnocontracts publish` subcommand; publishing is gnopm's job now,
// and these outlived it.

import (
	"context"
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

// probe is the answer to "is this package on this chain": present, absent, or
// no answer at all.
type probe int

const (
	probeAbsent probe = iota
	probePresent
	probeUnknown
)

// transportErrors are the substrings that mean the chain never answered, as
// opposed to answering "no such package". Everything that is not a clean
// answer is unknown: reporting an unreachable chain as "not published" is how
// 193 packages were recorded absent from sapphire while sapphire was simply
// down.
var transportErrors = []string{
	"connection refused", "no such host", "i/o timeout", "timeout", "deadline exceeded",
	"connection reset", "eof", "tls", "network is unreachable", "bad gateway",
	"service unavailable", "no route to host", "context canceled",
}

// absentAnswers are the substrings that mean the chain answered, and the answer
// was no.
var absentAnswers = []string{"not found", "unknown request", "invalid package", "could not read file"}

// queryUploaded asks whether pkgpath resolves on the given RPC, via
// `gnokey query vm/qfile`.
func queryUploaded(rpc, pkgpath string) probe {
	// Bound each query so an unreachable/slow RPC can't stall the job.
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "gnokey", "query", "vm/qfile", "--data", pkgpath, "--remote", rpc)
	out, err := cmd.CombinedOutput()
	s := strings.ToLower(string(out))
	if err != nil {
		if ctx.Err() != nil || containsAny(s, transportErrors) {
			return probeUnknown
		}
		if containsAny(s, absentAnswers) {
			return probeAbsent
		}
		return probeUnknown // an error we cannot classify is not evidence of absence
	}
	if containsAny(s, absentAnswers) {
		return probeAbsent
	}
	if strings.TrimSpace(string(out)) == "" {
		return probeUnknown
	}
	return probePresent
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

func containsAny(s string, subs []string) bool {
	for _, sub := range subs {
		if strings.Contains(s, sub) {
			return true
		}
	}
	return false
}
