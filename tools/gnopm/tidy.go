package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var importRe = regexp.MustCompile(`"(gno\.land/[^"]+)"`)

// workspaceImports returns every gno.land path imported by anything gnopm can
// see: the working tree and the materialized assembly both count, because a
// superseded version importing an older one is exactly how a chain of versions
// stays alive.
func workspaceImports(root string) (map[string]bool, error) {
	out := map[string]bool{}
	scan := func(dir string) error {
		return filepath.WalkDir(dir, func(p string, d os.DirEntry, err error) error {
			if err != nil {
				return nil // a missing assembly is not an error here
			}
			if d.IsDir() {
				if p != dir && (strings.HasPrefix(d.Name(), ".") && d.Name() != assemblyDir) {
					return filepath.SkipDir
				}
				return nil
			}
			if !strings.HasSuffix(d.Name(), ".gno") {
				return nil
			}
			b, err := os.ReadFile(p)
			if err != nil {
				return err
			}
			for _, m := range importRe.FindAllSubmatch(b, -1) {
				out[string(m[1])] = true
			}
			return nil
		})
	}
	pkgs, err := scanPackages(root)
	if err != nil {
		return nil, err
	}
	for _, pk := range pkgs {
		if err := scan(filepath.Join(root, filepath.FromSlash(pk.Dir))); err != nil {
			return nil, err
		}
	}
	if err := scan(filepath.Join(root, assemblyDir)); err != nil {
		return nil, err
	}
	return out, nil
}

// tidy drops pinned versions that nothing imports and that never shipped.
//
// Both conditions, not either. A version nobody in this workspace imports may
// still be deployed and imported by somebody else's code, so "unused here" is
// not permission to forget it. The second condition is what makes it safe: if
// the commit a version is pinned to is not reachable from the default branch,
// that version never existed for anyone outside the branch that created it.
// Dropping it loses nothing and un-strands a pin that a squash merge would
// have discarded anyway.
//
// That combination is the normal end state of a branch that adds v0 and then
// bumps to v1 before either has landed: the intermediate version is an editing
// artefact, not a release.
func tidy(e *env, dryRun bool) error {
	lock, err := readLock(e.root)
	if err != nil {
		return err
	}
	imports, err := workspaceImports(e.root)
	if err != nil {
		return err
	}
	upstream := upstreamRef(e.root, "")

	var drop []LockEntry
	for _, en := range materializedEntries(lock) {
		if imports[en.Module] {
			continue
		}
		if upstream != "" && gitIsAncestor(e.root, en.Source.Commit, upstream) {
			continue // it shipped; not ours to forget
		}
		drop = append(drop, en)
	}
	if len(drop) == 0 {
		fmt.Fprintln(e.errw, "nothing to tidy")
		return nil
	}
	sort.Slice(drop, func(i, j int) bool { return drop[i].Module < drop[j].Module })
	for _, en := range drop {
		why := "nothing imports it"
		if upstream != "" {
			why += ", and it never reached " + upstream
		}
		fmt.Fprintf(e.errw, "drop %s (%s)\n", en.Module, why)
	}
	if dryRun {
		return nil
	}
	next := &Lock{Format: lockFormat}
	dropped := map[string]bool{}
	for _, en := range drop {
		dropped[en.Module] = true
	}
	for _, en := range lock.Modules {
		if !dropped[en.Module] {
			next.Modules = append(next.Modules, en)
		}
	}
	if err := writeLock(e.root, next); err != nil {
		return err
	}
	return install(e)
}
