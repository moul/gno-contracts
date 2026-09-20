package main

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
)

// deversion is the one-time migration from version-in-the-directory to
// version-in-the-module-line, for a whole workspace at once.
//
// It is a gnopm command rather than a throwaway script because every gno
// repository that adopts this convention has to run exactly this migration,
// and the ordering is the part that is easy to get wrong:
//
//  1. Freeze. Pin every package in the tree at HEAD, so every version is
//     addressable from history BEFORE anything is removed from the tree.
//     Skipping this is unrecoverable: a version deleted without a pin is a
//     version nobody can resolve again without archaeology.
//  2. Move. For each package whose directory ends in the same /vN its module
//     declares, lift its files one level up with `git mv`, so git records
//     renames and a reviewer sees a rename list rather than a rewrite.
//     Where several versions of the same package exist, the highest one wins
//     the directory and the rest leave the tree; they stay resolvable from
//     the pin written in step 1.
//  3. Re-lock. The moved packages flip back to { dir } entries at their new
//     location; the ones that left the tree keep their history pins.
//
// The module lines are not touched. A realm's address derives from its
// package path, so rewriting one here would silently change an address; the
// whole point is that the migration is a pure directory move.
func deversion(e *env, dryRun bool) error {
	root, w := e.root, e.errw
	pkgs, err := scanPackages(root)
	if err != nil {
		return err
	}
	moves, drops, err := planDeversion(pkgs)
	if err != nil {
		return err
	}
	if len(moves) == 0 && len(drops) == 0 {
		fmt.Fprintln(w, "nothing to do: no package directory carries its version")
		return nil
	}

	if dryRun {
		for _, m := range moves {
			fmt.Fprintf(w, "mv   %s -> %s   (%s)\n", m.From, m.To, m.Module)
		}
		for _, d := range drops {
			fmt.Fprintf(w, "rm   %s   (%s, superseded, kept in %s)\n", d.Dir, d.Module, lockFile)
		}
		fmt.Fprintf(w, "\n%d package(s) move, %d leave the tree.\n", len(moves), len(drops))
		return nil
	}

	dirs := make([]string, 0, len(pkgs))
	for _, p := range pkgs {
		dirs = append(dirs, p.Dir)
	}
	if dirty, err := gitDirty(root, dirs...); err != nil {
		return err
	} else if len(dirty) > 0 {
		return fmt.Errorf("%d package file(s) are uncommitted (e.g. %s) - commit before migrating",
			len(dirty), strings.TrimSpace(dirty[0]))
	}

	// Step 1: freeze, so nothing below this line can lose a version.
	old, err := readLock(root)
	if err != nil {
		return err
	}
	frozen, err := freezeLock(root, old, pkgs, w)
	if err != nil {
		return err
	}
	if err := writeLock(root, frozen); err != nil {
		return err
	}
	fmt.Fprintf(w, "froze %d packages\n", len(pkgs))

	// Step 2: move, one tracked file at a time, so git sees renames.
	//
	// Collisions are checked for the whole plan first. Packages nest here
	// (p/moul/ulist/v0 and p/moul/ulist/lplist/v0 both exist), so lifting one
	// package's files up a level can in principle land on a sibling package's
	// directory. Half a migration is much worse than none, so nothing moves
	// until the whole plan is known to be collision-free.
	moveFiles := make([][]string, len(moves))
	for i, m := range moves {
		files, err := gitTrackedIn(root, m.From)
		if err != nil {
			return err
		}
		if len(files) == 0 {
			return fmt.Errorf("%s: no tracked files", m.From)
		}
		moveFiles[i] = files
	}
	if err := checkCollisions(root, moves, moveFiles); err != nil {
		return err
	}
	for i, m := range moves {
		files := moveFiles[i]
		for _, f := range files {
			src := path.Join(m.From, f)
			dst := path.Join(m.To, f)
			if err := os.MkdirAll(filepath.Join(root, filepath.FromSlash(path.Dir(dst))), 0o755); err != nil {
				return err
			}
			if _, err := git(root, "mv", src, dst); err != nil {
				return err
			}
		}
		// The version directory holds no tracked files now. git does not track
		// directories, so it will not clean this up: the empty tree would sit
		// there untracked and invisible to `git status`, while `ls` still
		// shows a v1/ that is supposed to be gone.
		//
		// Recursive, not a single Remove: a package with a subdirectory
		// (filetests/, say) leaves an empty subdirectory inside the empty
		// version directory, and one Remove would fail on "directory not
		// empty" and be silently ignored.
		if err := removeEmptyTree(filepath.Join(root, filepath.FromSlash(m.From))); err != nil {
			return err
		}
	}
	for _, d := range drops {
		if _, err := git(root, "rm", "-r", "-q", d.Dir); err != nil {
			return err
		}
	}
	fmt.Fprintf(w, "moved %d package(s), removed %d superseded version(s)\n", len(moves), len(drops))

	// Step 3: re-lock against the new layout.
	pkgs, err = scanPackages(root)
	if err != nil {
		return err
	}
	relocked, err := buildLock(frozen, pkgs)
	if err != nil {
		return err
	}
	if err := writeLock(root, relocked); err != nil {
		return err
	}
	fmt.Fprintf(w, "%s: %d modules (%d in tree, %d pinned to history)\n",
		lockFile, len(relocked.Modules), len(pkgs), len(relocked.Modules)-len(pkgs))
	fmt.Fprintf(w, "\nnext: `make lint test`, then commit the move on its own.\n")
	return nil
}

type move struct{ From, To, Module string }
type drop struct{ Dir, Module string }

// planDeversion decides what moves where, and refuses rather than guesses.
func planDeversion(pkgs []Package) ([]move, []drop, error) {
	// Group packages by the directory they would end up in.
	type cand struct {
		pkg Package
		n   int
	}
	byTarget := map[string][]cand{}
	var moves []move
	var drops []drop
	for _, p := range pkgs {
		_, n, ok := splitVersion(p.Module)
		if !ok {
			// No trailing /vN in the module path: nothing to de-version, and
			// not this migration's business to invent one.
			continue
		}
		dirBase, dirN, dirVersioned := splitVersion(p.Dir)
		if !dirVersioned {
			continue // already de-versioned
		}
		if dirN != n {
			return nil, nil, fmt.Errorf("%s declares %s but sits in a /v%d directory - "+
				"fix the mismatch by hand before migrating", p.Dir, p.Module, dirN)
		}
		byTarget[dirBase] = append(byTarget[dirBase], cand{p, n})
	}

	targets := make([]string, 0, len(byTarget))
	for t := range byTarget {
		targets = append(targets, t)
	}
	sort.Strings(targets)

	for _, target := range targets {
		cands := byTarget[target]
		// Highest version wins the unversioned directory: it is the one being
		// developed, and the one a bump will edit next.
		sort.Slice(cands, func(i, j int) bool { return cands[i].n > cands[j].n })
		moves = append(moves, move{From: cands[0].pkg.Dir, To: target, Module: cands[0].pkg.Module})
		for _, c := range cands[1:] {
			drops = append(drops, drop{Dir: c.pkg.Dir, Module: c.pkg.Module})
		}
	}
	sort.Slice(moves, func(i, j int) bool { return moves[i].From < moves[j].From })
	sort.Slice(drops, func(i, j int) bool { return drops[i].Dir < drops[j].Dir })
	return moves, drops, nil
}

// checkCollisions proves that no file a move produces lands on a path that
// already exists or that another move also claims.
func checkCollisions(root string, moves []move, files [][]string) error {
	claimed := map[string]string{}
	for i, m := range moves {
		for _, f := range files[i] {
			dst := path.Join(m.To, f)
			if prev, dup := claimed[dst]; dup {
				return fmt.Errorf("collision: %s and %s both want to produce %s", prev, m.From, dst)
			}
			claimed[dst] = m.From
			// Anything already at the destination that is not the source
			// itself is a genuine conflict: a sibling package directory, or a
			// stray file left at the unversioned path.
			abs := filepath.Join(root, filepath.FromSlash(dst))
			if _, err := os.Stat(abs); err == nil {
				return fmt.Errorf("collision: %s already exists, %s cannot move there", dst, path.Join(m.From, f))
			}
		}
	}
	return nil
}

// removeEmptyTree deletes dir if nothing but empty directories is left under
// it, and does nothing at all otherwise.
//
// Deliberately conservative: it never removes a file, so a stray untracked
// file anywhere under the directory stops the whole prune rather than being
// destroyed. Somebody's uncommitted scratch file is worth more than a tidy
// tree.
func removeEmptyTree(dir string) error {
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, e := range entries {
		if !e.IsDir() {
			return nil // a real file lives here; leave everything alone
		}
		if err := removeEmptyTree(filepath.Join(dir, e.Name())); err != nil {
			return err
		}
	}
	// Re-read: the children may or may not have gone.
	entries, err = os.ReadDir(dir)
	if err != nil {
		return err
	}
	if len(entries) == 0 {
		return os.Remove(dir)
	}
	return nil
}
