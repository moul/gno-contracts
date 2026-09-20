// Package gnomodlock reads and writes gnomod.lock, the record of where every
// module path's source actually is.
//
// It is a separate, importable package on purpose. A lock format is only a
// format if more than one program can read it, so this carries no dependency
// on the gnopm CLI and nothing here knows about any particular repository
// layout. It sits under the tool it ships with so that the whole thing stays
// one self-contained unit when it graduates to its own repository.
//
// Named for the file rather than for the manifest: gnomod is already a package
// in the gno monorepo, and two packages called gnomod in one import graph help
// nobody.
package gnomodlock

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// LockFile is the workspace lockfile, at the repository root.
//
// Named after the manifest (gnomod.toml), not after this tool: every ecosystem
// does it that way, Cargo.toml/Cargo.lock, package.json/package-lock.json,
// Gemfile/Gemfile.lock, and always at the workspace root, never per-package.
// A file called gnopm.lock would read as one implementation's private scratch
// file, which is fatal to the goal of the format becoming a convention other
// gno repos can adopt.
const LockFile = "gnomod.lock"

// FormatVersion is the format version, bumped only on a breaking change. Readers
// must refuse a lock they do not understand rather than guess.
const FormatVersion = 1

// Lock is a parsed gnomod.lock: one entry per resolvable module path.
//
// Flat, not package-with-nested-versions. gno has no concept of an unversioned
// module path (the path *is* gno.land/p/moul/md/v0), so inventing one purely
// for the lock would make the format harder to adopt than the thing it
// describes.
type Lock struct {
	Format  int
	Modules []LockEntry
}

// LockEntry records where one module path's source actually is.
type LockEntry struct {
	// Module is the full versioned path, e.g. gno.land/p/moul/md/v0.
	Module string
	// Source says where to find it. Exactly one variant is set.
	Source Source
	// Hash is the h1: content hash, set for every materialized source and
	// deliberately EMPTY for SourceDir.
	//
	// A SourceDir entry points at a directory a human is editing right now.
	// Hashing it would rewrite gnomod.lock on every source edit, so every PR
	// would carry a lock diff and two PRs touching two unrelated packages
	// would conflict in it. That is precisely the friction this tool exists to
	// remove, so the working tree is pinned by git, not by the lock.
	Hash string
}

// Source is where a module's source lives. Four variants; the tagged union is
// defined in full now because that is what makes this a format rather than one
// repo's script, but only the first two are implemented.
//
//	{ dir }                 in the working tree, the version you edit
//	{ commit, dir }         this repository's git history
//	{ repo, commit, dir }   another git repository            (not implemented)
//	{ chain, tx }           deployed source, via vm/qfile     (not implemented)
type Source struct {
	Dir    string // repo-relative, slash-separated
	Commit string
	Repo   string
	Chain  string
	Tx     string
}

// Variant names the union arm, for errors and for `gnopm list`.
func (s Source) Variant() string {
	switch {
	case s.Chain != "":
		return "chain"
	case s.Repo != "":
		return "repo"
	case s.Commit != "":
		return "commit"
	case s.Dir != "":
		return "dir"
	}
	return "invalid"
}

// InTree reports whether this source is the working tree itself, i.e. nothing
// has to be materialized for it to resolve.
func (s Source) InTree() bool { return s.Variant() == "dir" }

// validate rejects a source that is not exactly one well-formed variant.
func (s Source) Validate() error {
	switch s.Variant() {
	case "dir":
		if s.Tx != "" {
			return fmt.Errorf("source has both dir and tx")
		}
		return nil
	case "commit":
		if s.Dir == "" {
			return fmt.Errorf("source has commit but no dir")
		}
		if len(s.Commit) < 7 {
			return fmt.Errorf("commit %q is too short to be unambiguous", s.Commit)
		}
		return nil
	case "repo":
		return fmt.Errorf("source variant {repo, commit, dir} is not implemented yet")
	case "chain":
		return fmt.Errorf("source variant {chain, tx} is not implemented yet")
	}
	return fmt.Errorf("source sets no recognised field")
}

func (l *Lock) Sort() {
	sort.Slice(l.Modules, func(i, j int) bool { return l.Modules[i].Module < l.Modules[j].Module })
}

// byModule indexes entries by module path, and reports the first duplicate.
func (l *Lock) ByModule() (map[string]*LockEntry, error) {
	out := make(map[string]*LockEntry, len(l.Modules))
	for i := range l.Modules {
		m := l.Modules[i].Module
		if _, dup := out[m]; dup {
			return nil, fmt.Errorf("duplicate entry for module %q", m)
		}
		out[m] = &l.Modules[i]
	}
	return out, nil
}

// String renders the lock in its canonical on-disk form. Deterministic: the
// same workspace always produces byte-identical output, so a regenerated lock
// that differs is a real change and not formatting noise.
func (l *Lock) String() string {
	l.Sort()
	var b strings.Builder
	b.WriteString("# gnomod.lock, generated by gnopm. Do not hand-edit.\n")
	b.WriteString("#\n")
	b.WriteString("# One entry per resolvable module path. `source` says where that version's\n")
	b.WriteString("# code actually is: `dir` for the copy in the working tree, `commit`+`dir`\n")
	b.WriteString("# for a version that now exists only in this repository's git history.\n")
	b.WriteString("# `gnopm sync` materializes the latter under .gnopm/.\n")
	b.WriteString(fmt.Sprintf("\nlock = %d\n", FormatVersion))
	for _, e := range l.Modules {
		b.WriteString("\n[[module]]\n")
		b.WriteString(fmt.Sprintf("module = %q\n", e.Module))
		b.WriteString("source = " + e.Source.inlineTable() + "\n")
		if e.Hash != "" {
			b.WriteString(fmt.Sprintf("hash = %q\n", e.Hash))
		}
	}
	return b.String()
}

// inlineTable renders a source as a TOML inline table with a stable key order.
func (s Source) inlineTable() string {
	var kv []string
	add := func(k, v string) {
		if v != "" {
			kv = append(kv, fmt.Sprintf("%s = %q", k, v))
		}
	}
	add("repo", s.Repo)
	add("chain", s.Chain)
	add("tx", s.Tx)
	add("commit", s.Commit)
	add("dir", s.Dir)
	return "{ " + strings.Join(kv, ", ") + " }"
}

// writeLock writes the lock to the repository root, creating it if absent.
func Write(root string, l *Lock) error {
	return os.WriteFile(filepath.Join(root, LockFile), []byte(l.String()), 0o644)
}

// readLock parses the lock at the repository root. A missing lock is an empty
// lock, not an error: that is a workspace that has not been locked yet.
func Read(root string) (*Lock, error) {
	b, err := os.ReadFile(filepath.Join(root, LockFile))
	if os.IsNotExist(err) {
		return &Lock{Format: FormatVersion}, nil
	}
	if err != nil {
		return nil, err
	}
	l, err := Parse(string(b))
	if err != nil {
		return nil, fmt.Errorf("%s: %w", LockFile, err)
	}
	return l, nil
}
