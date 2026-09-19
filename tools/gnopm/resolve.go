package main

import (
	"fmt"
	"io"
	"os"
	"path"
	"sort"
)

// buildLock computes the lock a workspace should have.
//
// Two rules, and the whole design falls out of them:
//
//  1. Every package in the working tree is a { dir } entry. It is the version
//     you edit; git already pins it, so the lock only has to say where it is.
//  2. Every entry already in the lock whose module is NOT in the working tree
//     is carried over untouched. That is the archive: a version whose
//     directory is gone, still resolvable because the lock remembers the
//     commit that held it.
//
// Nothing else is inferred. A version that was never locked before it was
// deleted is simply lost, which is why `freeze` exists and why the migration
// runs it before it moves anything.
func buildLock(old *Lock, pkgs []Package) (*Lock, error) {
	// Reject a malformed lock up front rather than silently carrying a
	// duplicate entry through into the regenerated one.
	if _, err := old.ByModule(); err != nil {
		return nil, err
	}
	inTree := make(map[string]Package, len(pkgs))
	for _, p := range pkgs {
		inTree[p.Module] = p
	}
	next := &Lock{Format: lockFormat}
	for _, p := range pkgs {
		next.Modules = append(next.Modules, LockEntry{
			Module: p.Module,
			Source: Source{Dir: p.Dir},
		})
	}
	for _, e := range old.Modules {
		if _, live := inTree[e.Module]; live {
			// Superseded by the working tree. If the old entry pinned a
			// commit, that pin is now stale by definition: the tree holds
			// this version and is the thing being edited.
			continue
		}
		next.Modules = append(next.Modules, e)
	}
	next.Sort()
	return next, nil
}

// freezeLock pins every working-tree package to a commit that still holds it,
// so the directories can be moved or deleted without the versions becoming
// unresolvable.
//
// This is the load-bearing step of the de-versioning migration and the reason
// it is safe: history is made addressable BEFORE anything is removed from the
// tree, and each entry carries the hash of what it pinned, so a later
// `gnopm verify` can prove the archive still reproduces byte-for-byte.
//
// The commit is chosen by choosePin, not taken as HEAD: this repository
// squash-merges, so a pin to a feature branch's HEAD dangles the moment the
// pull request lands.
func freezeLock(root string, old *Lock, pkgs []Package, w io.Writer) (*Lock, error) {
	next := &Lock{Format: lockFormat}
	if _, err := old.ByModule(); err != nil {
		return nil, err
	}
	head, err := gitHead(root)
	if err != nil {
		return nil, err
	}
	dirs := make([]string, len(pkgs))
	for i, p := range pkgs {
		dirs[i] = p.Dir
	}
	// What each package's content is, as committed.
	atHead, err := hashDirsAtCommit(root, head, dirs)
	if err != nil {
		return nil, err
	}
	// The overwhelmingly common case in one batch: the default branch's tip
	// already holds exactly this content, because the branch has not touched
	// these packages. Resolving that here turns 193 per-package probes into
	// a single one.
	base, baseRef := "", ""
	for _, ref := range baseRefs {
		if c, err := gitResolve(root, ref); err == nil {
			base, baseRef = c, ref
			break
		}
	}
	atBase := map[string]string{}
	if base != "" {
		atBase, _ = hashDirsAtCommit(root, base, dirs)
	}

	fallbacks := 0
	for _, p := range pkgs {
		h, ok := atHead[p.Dir]
		if !ok {
			return nil, fmt.Errorf("%s: nothing tracked at %s, commit the package before freezing it", p.Dir, short(head))
		}
		commit := ""
		if atBase[p.Dir] == h {
			commit = base
		} else {
			pin, err := choosePin(root, p.Dir, h, w)
			if err != nil {
				return nil, err
			}
			commit = pin.Commit
			if pin.Ref == "" {
				fallbacks++
			}
		}
		next.Modules = append(next.Modules, LockEntry{
			Module: p.Module,
			Source: Source{Commit: commit, Dir: p.Dir},
			Hash:   h,
		})
	}
	if w != nil && base != "" && fallbacks == 0 {
		fmt.Fprintf(w, "pinned to %s (%s), which survives a squash merge\n", short(base), baseRef)
	}

	// Carry over versions that are not in the tree at all.
	inTree := make(map[string]bool, len(pkgs))
	for _, p := range pkgs {
		inTree[p.Module] = true
	}
	for _, e := range old.Modules {
		if !inTree[e.Module] {
			next.Modules = append(next.Modules, e)
		}
	}
	next.Sort()
	return next, nil
}

// hashDirsAtCommit hashes many directories as they existed at one commit,
// using a single `git archive`. Directories absent at that commit are simply
// missing from the result.
func hashDirsAtCommit(root, commit string, dirs []string) (map[string]string, error) {
	tmp, err := os.MkdirTemp("", "gnopm-hash-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp)
	entries := make([]archiveEntry, 0, len(dirs))
	dests := make([]string, 0, len(dirs))
	for i, d := range dirs {
		dest := path.Join(tmp, fmt.Sprint(i))
		entries = append(entries, archiveEntry{Dir: d, Dest: dest})
		dests = append(dests, dest)
	}
	if err := gitArchiveMany(root, commit, entries); err != nil {
		return nil, err
	}
	out := make(map[string]string, len(dirs))
	for i, d := range dirs {
		names, err := gitFilesAtCommit(root, commit, d)
		if err != nil || len(names) == 0 {
			continue
		}
		h, err := hashDirFiles(dests[i], names)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", d, err)
		}
		out[d] = h
	}
	return out, nil
}

// materializedEntries returns the lock entries that need extracting, i.e.
// everything that is not already in the working tree.
func materializedEntries(l *Lock) []LockEntry {
	var out []LockEntry
	for _, e := range l.Modules {
		if !e.Source.InTree() {
			out = append(out, e)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Module < out[j].Module })
	return out
}

func short(commit string) string {
	if len(commit) > 12 {
		return commit[:12]
	}
	return commit
}
