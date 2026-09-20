package main

import (
	"fmt"
	"sort"
	"strings"

	"github.com/moul/gno-contracts/tools/gnopm/pkg/gnomodlock"
)

// lockReport summarizes what a pull request does to gnomod.lock, for the
// sticky PR comment.
//
// Everything here comes from comparing two lock files, the one at the base ref
// and the one at HEAD, plus one git ancestry question. It deliberately does
// not re-derive whether the lock matches the working tree: `gnopm verify` is
// the hard gate for that and runs in the contracts job, and a second
// implementation of the same rule would eventually disagree with the first.
//
// The reason this is worth a section at all is the last check. A pin to a
// commit that only exists on the pull request's own branch looks fine locally
// and dies at merge time, because this repository squash-merges and those
// commits never become ancestors of the default branch. That is invisible in a
// diff, silent in tests, and only shows up later as a build nobody can fix.
func lockReport(root, base string) []string {
	headRaw := gitOut(root, "show", "HEAD:"+gnomodlock.LockFile)
	baseRaw := gitOut(root, "show", base+":"+gnomodlock.LockFile)
	if strings.TrimSpace(headRaw) == "" {
		return nil // no lock in this repository (yet)
	}
	head, err := gnomodlock.Parse(headRaw)
	if err != nil {
		return []string{fmt.Sprintf("⚠️ `%s` does not parse: %v", gnomodlock.LockFile, err)}
	}
	var prev *gnomodlock.Lock
	if strings.TrimSpace(baseRaw) != "" {
		if p, err := gnomodlock.Parse(baseRaw); err == nil {
			prev = p
		}
	}

	headBy := map[string]gnomodlock.LockEntry{}
	for _, e := range head.Modules {
		headBy[e.Module] = e
	}
	prevBy := map[string]gnomodlock.LockEntry{}
	if prev != nil {
		for _, e := range prev.Modules {
			prevBy[e.Module] = e
		}
	}

	// A bump shows up twice, once as the new version appearing and once as the
	// old one losing its directory. Report it once, as the bump.
	coveredByBump := map[string]bool{}
	for _, e := range head.Modules {
		if _, existed := prevBy[e.Module]; existed || !e.Source.InTree() {
			continue
		}
		if from, ok := bumpedFrom(e.Module, headBy, prevBy); ok {
			coveredByBump[from] = true
		}
	}

	var lines []string
	// Bumps first: they are the reason someone is reading this section.
	for _, e := range head.Modules {
		if coveredByBump[e.Module] {
			continue
		}
		p, existed := prevBy[e.Module]
		switch {
		case !existed && e.Source.InTree():
			if from, ok := bumpedFrom(e.Module, headBy, prevBy); ok {
				lines = append(lines, fmt.Sprintf("⬆️ `%s` bumped to **%s**, and %s is now pinned to history",
					unversioned(e.Module), version(e.Module), "`"+version(from)+"`"))
			} else {
				lines = append(lines, fmt.Sprintf("🆕 `%s` added to the lock", e.Module))
			}
		case !existed:
			lines = append(lines, fmt.Sprintf("🧊 `%s` added, pinned to history", e.Module))
		case p.Source.InTree() && !e.Source.InTree():
			lines = append(lines, fmt.Sprintf("🧊 `%s` no longer has a directory, pinned to `%s`",
				e.Module, shortHash(e.Source.Commit)))
		case !p.Source.InTree() && e.Source.InTree():
			lines = append(lines, fmt.Sprintf("📂 `%s` is back in the working tree at `%s`", e.Module, e.Source.Dir))
		case p.Source.Commit != e.Source.Commit && e.Source.Commit != "":
			lines = append(lines, fmt.Sprintf("🔁 `%s` re-pinned to `%s`", e.Module, shortHash(e.Source.Commit)))
		}
	}
	for _, e := range prevOnly(prev, headBy) {
		lines = append(lines, fmt.Sprintf("🗑️ `%s` dropped from the lock", e.Module))
	}

	// The check that only matters before the merge.
	var unsafe []string
	for _, e := range head.Modules {
		if e.Source.Commit == "" {
			continue
		}
		if p, existed := prevBy[e.Module]; existed && p.Source.Commit == e.Source.Commit {
			continue // not introduced here; already upstream's problem or nobody's
		}
		if !isAncestor(root, e.Source.Commit, base) {
			unsafe = append(unsafe, e.Module)
		}
	}
	if len(unsafe) > 0 {
		sort.Strings(unsafe)
		lines = append(lines, fmt.Sprintf(
			"⚠️ **%d pin(s) point at a commit that is not on `%s` yet**: %s. This repository squash-merges, so those commits do not survive and the versions stop resolving once this lands. Re-run `gnopm sync` after rebasing, or pin to a commit already upstream.",
			len(unsafe), strings.TrimPrefix(base, "origin/"), "`"+strings.Join(unsafe, "`, `")+"`"))
	}

	if len(lines) == 0 {
		return nil
	}
	sort.SliceStable(lines, func(i, j int) bool { return rank(lines[i]) < rank(lines[j]) })
	return lines
}

// rank puts warnings last, where a reader stops.
func rank(line string) int {
	if strings.HasPrefix(line, "⚠️") {
		return 1
	}
	return 0
}

func prevOnly(prev *gnomodlock.Lock, head map[string]gnomodlock.LockEntry) []gnomodlock.LockEntry {
	if prev == nil {
		return nil
	}
	var out []gnomodlock.LockEntry
	for _, e := range prev.Modules {
		if _, ok := head[e.Module]; !ok {
			out = append(out, e)
		}
	}
	return out
}

// bumpedFrom reports the version this one replaced: a module path that shares
// its unversioned prefix, was in the working tree at the base, and is pinned to
// history now.
func bumpedFrom(module string, head, prev map[string]gnomodlock.LockEntry) (string, bool) {
	base := unversioned(module)
	best := ""
	for m, p := range prev {
		if unversioned(m) != base || m == module {
			continue
		}
		if !p.Source.InTree() {
			continue
		}
		if h, ok := head[m]; ok && !h.Source.InTree() {
			if m > best {
				best = m
			}
		}
	}
	return best, best != ""
}

func unversioned(module string) string {
	if i := strings.LastIndex(module, "/"); i >= 0 {
		return module[:i]
	}
	return module
}

func version(module string) string {
	if i := strings.LastIndex(module, "/"); i >= 0 {
		return module[i+1:]
	}
	return module
}

func shortHash(c string) string {
	if len(c) > 9 {
		return c[:9]
	}
	return c
}

// isAncestor reports whether commit is reachable from ref.
func isAncestor(root, commit, ref string) bool {
	return gitOK(root, "merge-base", "--is-ancestor", commit, ref)
}
