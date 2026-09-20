package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// bump promotes a package to its next major version without copying it.
//
// The old way, and the reason this tool exists, was to copy p/moul/md/v0 to
// p/moul/md/v1 and edit the copy. git pairs nothing across that, so the review
// diff of a version bump is "+400 / -0, 4 new files" and a reviewer cannot see
// what actually changed. A version bump is by definition a compatibility
// change, so that is the diff that matters most and the one that was missing.
//
// Here the directory never moves. Three things happen:
//
//  1. The current version is pinned in the lock at HEAD, so it stays
//     resolvable for every package that still imports it.
//  2. The module line in gnomod.toml is rewritten to the next version.
//  3. The package's own lock entry becomes { dir }: it is the tree copy now.
//
// Then you edit the files in place and git diffs them properly.
func bump(e *env, target string, to int, force bool) error {
	root, w := e.root, e.errw
	pkgs, err := scanPackages(root)
	if err != nil {
		return err
	}
	pkg, err := findTarget(pkgs, target)
	if err != nil {
		return err
	}
	base, cur, ok := splitVersion(pkg.Module)
	if !ok {
		return fmt.Errorf("module %q has no trailing /vN, nothing to bump", pkg.Module)
	}
	next := cur + 1
	if to != 0 {
		if to <= cur {
			return fmt.Errorf("module %q is already at v%d, cannot bump to v%d", pkg.Module, cur, to)
		}
		next = to
	}
	nextModule := fmt.Sprintf("%s/v%d", base, next)

	// A dirty tree makes the recorded commit a lie: the lock would say
	// "v0 is at HEAD:p/moul/md" while the version that was actually at HEAD
	// is not the one the author was looking at. Every later materialization
	// would silently hand out the wrong code, and nothing would catch it,
	// because the hash recorded alongside would be of the wrong bytes too.
	dirty, err := gitDirty(root, pkg.Dir)
	if err != nil {
		return err
	}
	if len(dirty) > 0 && !force {
		return fmt.Errorf("%s has uncommitted changes (%d, e.g. %s)\n"+
			"  bump pins %s at HEAD, so HEAD has to hold the version you are leaving behind.\n"+
			"  commit first, or pass -force if you are certain HEAD is right", pkg.Dir, len(dirty), strings.TrimSpace(dirty[0]), pkg.Module)
	}
	head, err := gitHead(root)
	if err != nil {
		return err
	}

	lock, err := readLock(root)
	if err != nil {
		return err
	}
	if _, clash, _ := findModule(lock, nextModule); clash {
		return fmt.Errorf("%s is already in %s", nextModule, lockFile)
	}
	h, err := hashAtCommit(root, head, pkg.Dir)
	if err != nil {
		return fmt.Errorf("pinning %s at HEAD: %w", pkg.Module, err)
	}
	// Not HEAD: a pin has to point at a commit that survives the merge.
	pin, err := choosePin(root, pkg.Dir, h, w)
	if err != nil {
		return err
	}
	// Replace the outgoing version's entry with a history pin, and add the
	// incoming one as the tree copy.
	out := &Lock{Format: lockFormat}
	for _, e := range lock.Modules {
		if e.Module == pkg.Module {
			continue
		}
		out.Modules = append(out.Modules, e)
	}
	out.Modules = append(out.Modules,
		LockEntry{Module: pkg.Module, Source: Source{Commit: pin.Commit, Dir: pkg.Dir}, Hash: h},
		LockEntry{Module: nextModule, Source: Source{Dir: pkg.Dir}},
	)
	out.Sort()

	gnomod := filepath.Join(root, filepath.FromSlash(pkg.Dir), "gnomod.toml")
	if err := setModuleLine(gnomod, nextModule); err != nil {
		return err
	}
	if err := writeLock(root, out); err != nil {
		return err
	}
	where := short(pin.Commit)
	if pin.Ref != "" {
		where += " (" + pin.Ref + ")"
	}
	fmt.Fprintf(w, "bumped %s\n  %s -> %s\n  %s: one-line module change, files unchanged\n  %s: v%d pinned at %s\n",
		pkg.Dir, pkg.Module, nextModule, filepath.Join(pkg.Dir, "gnomod.toml"), lockFile, cur, where)
	fmt.Fprintf(w, "\nnow edit %s in place. Importers of %s still resolve.\n", pkg.Dir, pkg.Module)
	return nil
}

// findTarget accepts either a directory or a module path, because both are
// natural to type and the whole point of the tool is that they are no longer
// the same string.
func findTarget(pkgs []Package, target string) (Package, error) {
	t := strings.TrimSuffix(filepath.ToSlash(strings.TrimSpace(target)), "/")
	if t == "" {
		return Package{}, fmt.Errorf("no package given")
	}
	var byDir, byModule []Package
	for _, p := range pkgs {
		if p.Dir == t {
			byDir = append(byDir, p)
		}
		if p.Module == t {
			byModule = append(byModule, p)
		}
	}
	switch {
	case len(byModule) == 1:
		return byModule[0], nil
	case len(byDir) == 1:
		return byDir[0], nil
	}
	// Last resort: an unambiguous suffix of a module path, so `md` works when
	// only one package ends that way.
	var suffix []Package
	for _, p := range pkgs {
		if strings.HasSuffix(p.Module, "/"+t) || strings.HasPrefix(p.Module, "gno.land/") && strings.Contains(p.Module, "/"+t+"/") {
			suffix = append(suffix, p)
		}
	}
	if len(suffix) == 1 {
		return suffix[0], nil
	}
	if len(suffix) > 1 {
		names := make([]string, 0, len(suffix))
		for _, p := range suffix {
			names = append(names, p.Module)
		}
		return Package{}, fmt.Errorf("%q is ambiguous: %s", target, strings.Join(names, ", "))
	}
	return Package{}, fmt.Errorf("no package at directory or module path %q", target)
}

func findModule(l *Lock, module string) (LockEntry, bool, int) {
	for i, e := range l.Modules {
		if e.Module == module {
			return e, true, i
		}
	}
	return LockEntry{}, false, -1
}

// ensureIgnored makes sure the assembly directory is gitignored, because a
// committed .gnopm/ would reintroduce exactly the duplicated-source problem
// the tool removes.
func ensureIgnored(root string) error {
	p := filepath.Join(root, ".gitignore")
	b, err := os.ReadFile(p)
	if err != nil {
		return nil
	}
	for _, line := range strings.Split(string(b), "\n") {
		if strings.TrimSpace(line) == "/"+assemblyDir+"/" {
			return nil
		}
	}
	return fmt.Errorf(".gitignore does not ignore /%s/, add it before running install", assemblyDir)
}
