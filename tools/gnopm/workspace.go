package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// workspaceMarker identifies the repository root. Same marker the rest of the
// tooling uses, so gnopm and gnocontracts can never disagree about where the
// workspace is.
const workspaceMarker = "gnowork.toml"

// assemblyDir holds versions that no longer exist in the working tree.
//
// Dot-prefixed and gitignored: it is tool output, reconstructible from the lock
// at any time, and it must never be something a human edits or a reviewer
// reads. The gno toolchain scans dot-directories (verified against gno
// master, 2026-09-19), which is exactly why the layout works, and why the
// Makefile's package discovery has to keep excluding them.
const assemblyDir = ".gnopm"

// stampFile records the lock hash the assembly was built from, so `install` is
// a no-op on an up-to-date tree and Make can depend on the file.
const stampFile = ".stamp"

// skipDirs are directories the scan never descends into.
//
// vendor/ is third-party code, committed on purpose (see .gitignore) and
// pinned by being committed rather than by this lock; gnopm does not own it
// yet. .gnopm/ is gnopm's own output, and treating it as a source of
// workspace packages would make install see its own extractions as tree
// packages on the second run.
var skipDirs = map[string]bool{"vendor": true, assemblyDir: true}

// Package is one buildable gno package found in the working tree.
type Package struct {
	// Dir is repo-relative and slash-separated, e.g. "p/moul/md".
	Dir string
	// Module is the declared module path, e.g. "gno.land/p/moul/md/v1".
	//
	// This, not Dir, is the package's identity. gno resolves a workspace
	// import from the module line and ignores the directory name entirely
	// (verified against gno master, 2026-09-19: a directory named zzz/
	// declaring gno.land/p/probe/foo/v1 is resolved by a sibling importing
	// that path, while an import absent from the workspace fails to resolve).
	// Everything downstream depends on that fact.
	Module string
	// Ignored mirrors `ignore = true` in gnomod.toml.
	Ignored bool
}

// findRoot walks up from dir to the workspace root.
func findRoot(dir string) (string, error) {
	d, err := filepath.Abs(dir)
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(d, workspaceMarker)); err == nil {
			return d, nil
		}
		parent := filepath.Dir(d)
		if parent == d {
			return "", fmt.Errorf("%s not found in %q or any parent", workspaceMarker, dir)
		}
		d = parent
	}
}

// scanPackages finds every gno package in the working tree, keyed by the
// module path it declares rather than by where it sits.
func scanPackages(root string) ([]Package, error) {
	var out []Package
	err := filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if p == root {
				return nil
			}
			name := d.Name()
			if strings.HasPrefix(name, ".") || skipDirs[name] {
				return filepath.SkipDir
			}
			return nil
		}
		if d.Name() != "gnomod.toml" {
			return nil
		}
		mod, ignored, err := readGnomod(p)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(root, filepath.Dir(p))
		if err != nil {
			return err
		}
		out = append(out, Package{Dir: filepath.ToSlash(rel), Module: mod, Ignored: ignored})
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Module < out[j].Module })
	seen := make(map[string]string, len(out))
	for _, p := range out {
		if prev, dup := seen[p.Module]; dup {
			return nil, fmt.Errorf("two packages declare module %q: %s and %s", p.Module, prev, p.Dir)
		}
		seen[p.Module] = p.Dir
	}
	return out, nil
}

// readGnomod extracts the module path and the ignore flag from a gnomod.toml.
func readGnomod(p string) (module string, ignored bool, err error) {
	b, err := os.ReadFile(p)
	if err != nil {
		return "", false, err
	}
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "module"):
			rest := strings.TrimSpace(strings.TrimPrefix(line, "module"))
			if !strings.HasPrefix(rest, "=") {
				continue
			}
			if v, e := unquote(strings.TrimSpace(strings.TrimPrefix(rest, "="))); e == nil {
				module = v
			}
		case strings.HasPrefix(line, "ignore"):
			rest := strings.TrimSpace(strings.TrimPrefix(line, "ignore"))
			if strings.HasPrefix(rest, "=") {
				ignored = strings.Contains(strings.ToLower(rest), "true")
			}
		}
	}
	if module == "" {
		return "", false, fmt.Errorf("%s: no module declaration", p)
	}
	return module, ignored, nil
}

// setModuleLine rewrites the module path in a gnomod.toml, touching nothing
// else in the file: comments, key order and the gno directive all survive,
// because a bump has to be readable as a one-line diff.
func setModuleLine(p, module string) error {
	b, err := os.ReadFile(p)
	if err != nil {
		return err
	}
	lines := strings.Split(string(b), "\n")
	done := false
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if !strings.HasPrefix(trimmed, "module") {
			continue
		}
		rest := strings.TrimSpace(strings.TrimPrefix(trimmed, "module"))
		if !strings.HasPrefix(rest, "=") {
			continue
		}
		indent := line[:len(line)-len(strings.TrimLeft(line, " \t"))]
		lines[i] = fmt.Sprintf("%smodule = %q", indent, module)
		done = true
		break
	}
	if !done {
		return fmt.Errorf("%s: no module line to rewrite", p)
	}
	return os.WriteFile(p, []byte(strings.Join(lines, "\n")), 0o644)
}

// splitVersion splits a module path into its unversioned prefix and version
// number: gno.land/p/moul/md/v2 -> ("gno.land/p/moul/md", 2, true).
func splitVersion(module string) (base string, n int, ok bool) {
	i := strings.LastIndex(module, "/")
	if i < 0 {
		return "", 0, false
	}
	last := module[i+1:]
	if len(last) < 2 || last[0] != 'v' {
		return "", 0, false
	}
	for _, r := range last[1:] {
		if r < '0' || r > '9' {
			return "", 0, false
		}
		n = n*10 + int(r-'0')
	}
	return module[:i], n, true
}
