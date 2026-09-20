package main

import (
	"archive/tar"
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"sort"
	"strings"
)

// git runs a git command in root and returns its stdout.
func git(root string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			msg = err.Error()
		}
		return "", fmt.Errorf("git %s: %s", strings.Join(args, " "), msg)
	}
	return out.String(), nil
}

// gitHead resolves HEAD to a full 40-character object name. The lock records
// full hashes: an abbreviation that is unique today can collide later, and a
// lock entry that stops resolving is worse than a long string.
func gitHead(root string) (string, error) {
	s, err := git(root, "rev-parse", "HEAD")
	return strings.TrimSpace(s), err
}

// gitResolve expands any commit-ish to a full object name and proves it exists.
func gitResolve(root, rev string) (string, error) {
	s, err := git(root, "rev-parse", "--verify", rev+"^{commit}")
	if err != nil {
		return "", fmt.Errorf("commit %q is not in this repository: %w", rev, err)
	}
	return strings.TrimSpace(s), nil
}

// gitDirty returns the porcelain status lines for the given pathspecs, empty
// when they are clean. With no pathspec it reports the whole tree.
//
// Callers pass the directories they are about to pin rather than asking about
// the whole repository: `gnopm sync` writes gnomod.lock, so a whole-tree check
// would make `bump` refuse to run immediately after a `lock`, a workflow that
// is not only harmless but expected. What has to be clean is the source being
// pinned, because that is the only thing the recorded commit makes a claim
// about.
func gitDirty(root string, paths ...string) ([]string, error) {
	args := append([]string{"status", "--porcelain", "--"}, paths...)
	if len(paths) == 0 {
		args = []string{"status", "--porcelain"}
	}
	s, err := git(root, args...)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, l := range strings.Split(strings.TrimRight(s, "\n"), "\n") {
		if strings.TrimSpace(l) != "" {
			out = append(out, l)
		}
	}
	return out, nil
}

// gitTrackedIn lists the git-tracked files under a working-tree directory,
// as paths relative to that directory.
func gitTrackedIn(root, dir string) ([]string, error) {
	s, err := git(root, "ls-files", "-z", "--", dir)
	if err != nil {
		return nil, err
	}
	return ownFiles(relativizeZ(s, dir)), nil
}

// gitFilesAtCommit lists the files that belong to the package at dir as of
// commit, relative to dir.
//
// "Belong to" excludes anything under a nested package. Package directories
// nest: after de-versioning, p/moul/ulist contains p/moul/ulist/lplist, which
// is its own package with its own gnomod.toml. A recursive listing hands back
// lplist's files too, and hashing ulist with lplist's files in the set is
// wrong twice over: the hash changes when a different package changes, and the
// extraction routes those files to lplist's destination so they are not even
// there to read.
//
// This could not happen before the migration, because a version directory
// never contained another package. It is the first bug that the new layout
// created rather than removed.
func gitFilesAtCommit(root, commit, dir string) ([]string, error) {
	s, err := git(root, "ls-tree", "-r", "-z", "--name-only", commit, "--", dir)
	if err != nil {
		return nil, err
	}
	return ownFiles(relativizeZ(s, dir)), nil
}

// ownFiles drops the paths that belong to a package nested inside this one.
//
// A nested package is any subdirectory carrying its own gnomod.toml, which is
// the same rule the workspace scan uses, so the two can never disagree about
// where one package ends and the next begins.
func ownFiles(names []string) []string {
	var nested []string
	for _, n := range names {
		if i := strings.LastIndex(n, "/gnomod.toml"); i > 0 && i == len(n)-len("/gnomod.toml") {
			nested = append(nested, n[:i]+"/")
		}
	}
	if len(nested) == 0 {
		return names
	}
	out := names[:0:0]
	for _, n := range names {
		own := true
		for _, pre := range nested {
			if strings.HasPrefix(n, pre) {
				own = false
				break
			}
		}
		if own {
			out = append(out, n)
		}
	}
	return out
}

// relativizeZ turns NUL-separated repo-relative paths into names relative to
// dir, dropping anything outside it.
func relativizeZ(s, dir string) []string {
	prefix := strings.TrimSuffix(path.Clean(dir), "/") + "/"
	var out []string
	for _, p := range strings.Split(s, "\x00") {
		if p == "" {
			continue
		}
		if !strings.HasPrefix(p, prefix) {
			continue
		}
		out = append(out, strings.TrimPrefix(p, prefix))
	}
	sort.Strings(out)
	return out
}

// archiveEntry is one directory to pull out of history.
type archiveEntry struct {
	Dir  string // repo-relative source directory at Commit
	Dest string // absolute destination directory
}

// gitArchiveMany extracts several directories from one commit in a single git
// invocation, writing each into its own destination.
//
// One process for the whole batch rather than one per package: materializing a
// 193-package workspace one `git archive` at a time is a few hundred forks for
// no reason, and this path runs on every CI job.
func gitArchiveMany(root, commit string, entries []archiveEntry) error {
	if len(entries) == 0 {
		return nil
	}
	dests := make(map[string]string, len(entries))
	args := []string{"archive", "--format=tar", commit, "--"}
	for _, e := range entries {
		clean := strings.TrimSuffix(path.Clean(e.Dir), "/")
		if _, dup := dests[clean]; dup {
			return fmt.Errorf("directory %q requested twice from commit %s", clean, commit)
		}
		dests[clean] = e.Dest
		args = append(args, clean)
	}
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	var errb bytes.Buffer
	cmd.Stderr = &errb
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	untarErr := untarInto(stdout, dests)
	io.Copy(io.Discard, stdout)
	if err := cmd.Wait(); err != nil {
		msg := strings.TrimSpace(errb.String())
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf("git archive %s: %s", commit, msg)
	}
	return untarErr
}

// untarInto writes a git-archive tar stream into per-source-directory
// destinations, rebasing each member path onto its destination.
func untarInto(r io.Reader, dests map[string]string) error {
	tr := tar.NewReader(r)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		name := path.Clean(hdr.Name)
		src, rel, ok := matchDest(name, dests)
		if !ok {
			continue
		}
		dest := filepath.Join(dests[src], filepath.FromSlash(rel))
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(dest, 0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
				return err
			}
			// Mode from the tar, masked: history can carry an executable bit
			// but never anything more exotic, and honouring it keeps the
			// materialized copy byte-and-bit identical to the committed one.
			f, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(hdr.Mode)&0o755)
			if err != nil {
				return err
			}
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return err
			}
			if err := f.Close(); err != nil {
				return err
			}
		case tar.TypeSymlink:
			return fmt.Errorf("%s: symlinks are not supported in a materialized package", name)
		}
	}
}

// matchDest finds the longest requested directory that contains name.
//
// Longest wins because gno package directories nest: p/moul/x/amm/v0 lives
// inside p/moul/x, and a shortest-prefix match would file a nested package's
// files under its ancestor.
func matchDest(name string, dests map[string]string) (src, rel string, ok bool) {
	best := ""
	for d := range dests {
		if name == d || strings.HasPrefix(name, d+"/") {
			if len(d) > len(best) {
				best = d
			}
		}
	}
	if best == "" {
		return "", "", false
	}
	if name == best {
		return "", "", false
	}
	return best, strings.TrimPrefix(name, best+"/"), true
}

// gitIsAncestor reports whether commit is reachable from ref.
func gitIsAncestor(root, commit, ref string) bool {
	_, err := git(root, "merge-base", "--is-ancestor", commit, ref)
	return err == nil
}
