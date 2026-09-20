package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// install materializes every locked version that is not in the working tree
// into .gnopm/, and prunes whatever the lock no longer mentions.
//
// The assembly mirrors the module path (.gnopm/gno.land/p/moul/md/v0), which
// is the only layout where a human who opens the directory knows what they are
// looking at. The toolchain does not care: it reads the module line.
func install(e *env) error {
	root := e.root
	lock, err := readLock(root)
	if err != nil {
		return err
	}
	pkgs, err := scanPackages(root)
	if err != nil {
		return err
	}
	inTree := make(map[string]string, len(pkgs))
	for _, p := range pkgs {
		inTree[p.Module] = p.Dir
	}

	want := materializedEntries(lock)
	// A module cannot be in two places at once. Two packages declaring the
	// same module path is the one way to make the toolchain's resolution
	// ambiguous, and it is exactly what the migration risks in the window
	// between freezing history and moving the directories.
	for _, e := range want {
		if dir, clash := inTree[e.Module]; clash {
			return fmt.Errorf("module %q is locked to %s but also declared by the working tree at %s, "+
				"run `gnopm sync` to re-point it at the tree", e.Module, e.Source.Variant(), dir)
		}
	}

	stamp := hashString(lock.String())
	asm := filepath.Join(root, assemblyDir)
	if cur, err := os.ReadFile(filepath.Join(asm, stampFile)); err == nil && strings.TrimSpace(string(cur)) == stamp {
		return nil
	}

	var extract []archiveEntry
	var extractOf []LockEntry
	kept := 0
	for _, e := range want {
		dest := filepath.Join(asm, filepath.FromSlash(e.Module))
		if ok, _ := assemblyMatches(root, dest, e); ok {
			kept++
			continue
		}
		if err := os.RemoveAll(dest); err != nil {
			return err
		}
		if err := os.MkdirAll(dest, 0o755); err != nil {
			return err
		}
		extract = append(extract, archiveEntry{Dir: e.Source.Dir, Dest: dest})
		extractOf = append(extractOf, e)
	}

	// Group by commit: one `git archive` per commit, not per package.
	byCommit := map[string][]archiveEntry{}
	for i, e := range extract {
		byCommit[extractOf[i].Source.Commit] = append(byCommit[extractOf[i].Source.Commit], e)
	}
	commits := make([]string, 0, len(byCommit))
	for c := range byCommit {
		commits = append(commits, c)
	}
	sort.Strings(commits)
	for _, c := range commits {
		if _, err := gitResolve(root, c); err != nil {
			return err
		}
		if err := gitArchiveMany(root, c, byCommit[c]); err != nil {
			return err
		}
	}
	// Prove what was written is what was locked, every time. An extraction
	// that silently produced different bytes than the hash promises is the
	// one failure mode that would make every downstream build a lie.
	for i, e := range extractOf {
		ok, got := assemblyMatches(root, extract[i].Dest, e)
		if !ok {
			return fmt.Errorf("module %q: extracted from %s but hash is %s, lock says %s",
				e.Module, short(e.Source.Commit), got, e.Hash)
		}
	}

	pruned, err := pruneAssembly(asm, want)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(asm, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(asm, stampFile), []byte(stamp+"\n"), 0o644); err != nil {
		return err
	}
	if len(extract) > 0 || pruned > 0 {
		e.logf("assembly updated: %d materialized (%d extracted, %d cached, %d pruned)\n",
			len(want), len(extract), kept, pruned)
	}
	_ = kept
	return nil
}

// assemblyMatches reports whether an already-extracted directory still holds
// exactly what the lock entry pins.
func assemblyMatches(root, dest string, e LockEntry) (bool, string) {
	if _, err := os.Stat(dest); err != nil {
		return false, ""
	}
	names, err := gitFilesAtCommit(root, e.Source.Commit, e.Source.Dir)
	if err != nil || len(names) == 0 {
		return false, ""
	}
	h, err := hashDirFiles(dest, names)
	if err != nil {
		return false, ""
	}
	return h == e.Hash, h
}

// pruneAssembly removes anything under the assembly root that the lock no
// longer mentions, then drops the directories left empty.
func pruneAssembly(asm string, want []LockEntry) (int, error) {
	if _, err := os.Stat(asm); os.IsNotExist(err) {
		return 0, nil
	}
	keep := make(map[string]bool, len(want))
	for _, e := range want {
		p := filepath.Join(asm, filepath.FromSlash(e.Module))
		// Keep the package and every ancestor up to the assembly root.
		for d := p; strings.HasPrefix(d, asm) && d != asm; d = filepath.Dir(d) {
			keep[d] = true
		}
	}
	var drop []string
	err := filepath.WalkDir(asm, func(p string, d os.DirEntry, err error) error {
		if err != nil || p == asm {
			return err
		}
		if !d.IsDir() {
			if filepath.Dir(p) == asm && d.Name() == stampFile {
				return nil
			}
			if !keep[filepath.Dir(p)] {
				drop = append(drop, p)
			}
			return nil
		}
		if !keep[p] {
			drop = append(drop, p)
			return filepath.SkipDir
		}
		return nil
	})
	if err != nil {
		return 0, err
	}
	for _, p := range drop {
		if err := os.RemoveAll(p); err != nil {
			return 0, err
		}
	}
	return len(drop), nil
}

// verify is the CI guard. It writes nothing, and proves three things:
//
//  1. gnomod.lock is in canonical form, so a hand edit or a stale generator
//     is caught before it becomes a merge conflict;
//  2. the lock and the working tree agree about where every module lives;
//  3. every version pinned to history still reproduces its recorded hash.
//
// Deliberately NOT "the lock is byte-identical to what `gnopm sync` would
// write". That would be simpler, but it would also fail during the one window
// where the lock is meant to disagree with the tree: the migration pins
// packages that are still in their directories, precisely so the directories
// can then move. A guard with a documented exception is a guard with a hole,
// so the rule is consistency rather than identity.
func verify(e *env) error {
	root, w := e.root, e.errw
	raw, err := os.ReadFile(filepath.Join(root, lockFile))
	if os.IsNotExist(err) {
		return fmt.Errorf("no %s yet. Run `gnopm sync`", lockFile)
	}
	if err != nil {
		return err
	}
	lock, err := parseLock(string(raw))
	if err != nil {
		return fmt.Errorf("%s: %w", lockFile, err)
	}
	if canon := lock.String(); !sameLockData(string(raw), canon) {
		return fmt.Errorf("%s is not in canonical form. Run `gnopm sync`\n%s",
			lockFile, firstDiff(stripComments(string(raw)), stripComments(canon)))
	}
	pkgs, err := scanPackages(root)
	if err != nil {
		return err
	}
	if err := consistent(lock, pkgs); err != nil {
		return fmt.Errorf("%s is stale: %w. Run `gnopm sync`", lockFile, err)
	}

	pinned := materializedEntries(lock)
	bad := 0
	for _, e := range pinned {
		if _, err := gitResolve(root, e.Source.Commit); err != nil {
			fmt.Fprintf(w, "  %s: %v\n", e.Module, err)
			bad++
			continue
		}
		h, err := hashAtCommit(root, e.Source.Commit, e.Source.Dir)
		if err != nil {
			fmt.Fprintf(w, "  %s: %v\n", e.Module, err)
			bad++
			continue
		}
		if h != e.Hash {
			fmt.Fprintf(w, "  %s: history hashes to %s, lock says %s\n", e.Module, h, e.Hash)
			bad++
		}
	}
	if bad > 0 {
		return fmt.Errorf("%d locked version(s) do not reproduce from history", bad)
	}
	fmt.Fprintf(w, "gnopm: ok, %d modules locked (%d in tree, %d pinned to history)\n",
		len(lock.Modules), len(pkgs), len(pinned))
	return nil
}

// hashAtCommit hashes a directory as it existed at a commit, without leaving
// anything behind.
func hashAtCommit(root, commit, dir string) (string, error) {
	names, err := gitFilesAtCommit(root, commit, dir)
	if err != nil {
		return "", err
	}
	if len(names) == 0 {
		return "", fmt.Errorf("%s does not exist at %s", dir, short(commit))
	}
	tmp, err := os.MkdirTemp("", "gnopm-verify-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(tmp)
	if err := gitArchiveMany(root, commit, []archiveEntry{{Dir: dir, Dest: tmp}}); err != nil {
		return "", err
	}
	return hashDirFiles(tmp, names)
}

// firstDiff reports the first differing line, so a stale lock says what
// changed instead of dumping two files at the reader.
func firstDiff(got, want string) string {
	g, w := strings.Split(got, "\n"), strings.Split(want, "\n")
	for i := 0; i < len(g) || i < len(w); i++ {
		gl, wl := "", ""
		if i < len(g) {
			gl = g[i]
		}
		if i < len(w) {
			wl = w[i]
		}
		if gl != wl {
			return fmt.Sprintf("  line %d:\n    on disk:  %s\n    expected: %s", i+1, gl, wl)
		}
	}
	return ""
}

// consistent checks that the lock and the working tree agree about where every
// module lives. Shared by verify and status so the two can never disagree
// about what "stale" means.
func consistent(lock *Lock, pkgs []Package) error {
	byModule, err := lock.ByModule()
	if err != nil {
		return err
	}
	inTree := make(map[string]bool, len(pkgs))
	for _, p := range pkgs {
		inTree[p.Module] = true
		e, ok := byModule[p.Module]
		if !ok {
			return fmt.Errorf("%s declares %s, which is not in the lock", p.Dir, p.Module)
		}
		if e.Source.InTree() && e.Source.Dir != p.Dir {
			return fmt.Errorf("%s is locked at %s but the tree has it at %s", p.Module, e.Source.Dir, p.Dir)
		}
	}
	for _, e := range lock.Modules {
		if e.Source.InTree() && !inTree[e.Module] {
			return fmt.Errorf("%s is locked at %s, where nothing declares it", e.Module, e.Source.Dir)
		}
	}
	return nil
}

// sameLockData compares two lock files by their data, ignoring comments and
// blank lines.
//
// The header is prose, and prose gets edited. Making it load-bearing would
// mean that improving one sentence in the generated header invalidates every
// gnomod.lock in existence and fails CI on every repository using the format,
// which is an absurd price for a wording change. `sync` still rewrites the
// whole file, so headers do get refreshed; they just are not a reason to
// refuse.
func sameLockData(a, b string) bool { return stripComments(a) == stripComments(b) }

func stripComments(s string) string {
	var out []string
	for _, line := range strings.Split(s, "\n") {
		t := strings.TrimSpace(line)
		if t == "" || strings.HasPrefix(t, "#") {
			continue
		}
		out = append(out, t)
	}
	return strings.Join(out, "\n")
}
