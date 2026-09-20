package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// cmdSync reports drift between our contracts and their counterparts in the
// gnolang/gno monorepo examples tree. It is how moul learns that someone changed
// one of his contracts upstream, so he can cut a new version here. Read-only.
// Requires GNOROOT.
//
// Since gnolang/gno#6162 every monorepo package carries its own version segment,
// so a counterpart is found at the SAME pkgpath rather than at an un-versioned
// one: our gno.land/p/moul/md/v0 mirrors examples' gno.land/p/moul/md/v0, and a
// drift there is a genuine upstream change. Versions above the mirrored one are
// ours alone and have no counterpart to compare against.
func cmdSync(root string, args []string) error {
	gnoroot := os.Getenv("GNOROOT")
	if gnoroot == "" {
		return fmt.Errorf("GNOROOT must be set (path to a gnolang/gno checkout)")
	}
	examples := filepath.Join(gnoroot, "examples")

	scanned, err := scanContracts(root)
	if err != nil {
		return err
	}

	// Which of our contracts have an exact monorepo counterpart, and which
	// package families we mirror at all (so a higher version of a mirrored
	// package reads as "ours" rather than "unknown upstream").
	upstreamDir := map[string]string{}
	mirrored := map[string]bool{}
	for _, c := range scanned {
		dir := filepath.Join(examples, filepath.FromSlash(c.PkgPath))
		if fileExists(dir) {
			upstreamDir[c.PkgPath] = dir
			mirrored[basePath(c.PkgPath)] = true
		}
	}

	var inSync, drifted, ours, newHere int
	fmt.Println("drift vs monorepo (", examples, "):")
	for _, c := range scanned {
		srcDir, ok := upstreamDir[c.PkgPath]
		if !ok {
			if mirrored[basePath(c.PkgPath)] {
				fmt.Printf("  [ours]  %s — our successor to the mirrored version\n", c.PkgPath)
				ours++
			} else {
				fmt.Printf("  [new]   %s — not in monorepo\n", c.PkgPath)
				newHere++
			}
			continue
		}
		diffs, err := diffGnoDirs(filepath.Join(root, filepath.FromSlash(c.srcDir())), srcDir)
		if err != nil {
			return err
		}
		if len(diffs) == 0 {
			inSync++
			continue
		}
		drifted++
		fmt.Printf("  [drift] %s — upstream changed:\n", c.PkgPath)
		for _, d := range diffs {
			fmt.Printf("            %s\n", d)
		}
	}

	// Monorepo moul packages we do not carry at all.
	for _, kind := range []string{"p", "r"} {
		base := filepath.Join(examples, "gno.land", kind, "moul")
		if !fileExists(base) {
			continue
		}
		pkgs, _ := upstreamPackages(base, "gno.land/"+kind+"/moul")
		for _, up := range pkgs {
			if _, have := upstreamDir[up]; !have {
				fmt.Printf("  [miss]  %s — in monorepo, not imported here yet\n", up)
			}
		}
	}

	fmt.Printf("summary: %d in-sync, %d drifted, %d ours, %d new-here\n",
		inSync, drifted, ours, newHere)
	return nil
}

// basePath strips a trailing /vN element from a pkgpath, yielding the version
// family: gno.land/p/moul/md/v0 -> gno.land/p/moul/md.
func basePath(pkgpath string) string {
	i := strings.LastIndex(pkgpath, "/")
	if i < 0 {
		return pkgpath
	}
	if isVersion(pkgpath[i+1:]) {
		return pkgpath[:i]
	}
	return pkgpath
}

// diffGnoDirs compares the .gno files (by content) of two package directories,
// ignoring gnomod.toml. It returns human-readable difference notes.
func diffGnoDirs(ourDir, upDir string) ([]string, error) {
	ours, err := gnoFiles(ourDir)
	if err != nil {
		return nil, err
	}
	up, err := gnoFiles(upDir)
	if err != nil {
		return nil, err
	}
	var diffs []string
	for name, ob := range ours {
		ub, ok := up[name]
		if !ok {
			diffs = append(diffs, "only here:     "+name)
			continue
		}
		if ob != ub {
			diffs = append(diffs, "differs:       "+name)
		}
	}
	for name := range up {
		if _, ok := ours[name]; !ok {
			diffs = append(diffs, "only monorepo: "+name)
		}
	}
	sort.Strings(diffs)
	return diffs, nil
}

func gnoFiles(dir string) (map[string]string, error) {
	out := map[string]string{}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".gno") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return nil, err
		}
		out[e.Name()] = string(b)
	}
	return out, nil
}

// isTestGno reports whether a .gno file is a test/filetest (not part of the
// deployed package).
func isTestGno(name string) bool {
	return strings.HasSuffix(name, "_test.gno") || strings.HasSuffix(name, "_filetest.gno")
}

// classifyContractUpstream classifies contract c against its un-versioned
// monorepo copy, or returns "" when c has no upstream or the monorepo copy is
// unavailable ($GNOROOT unset / path absent — caller keeps the stored value).
func classifyContractUpstream(root string, c *Contract) string {
	if c.Upstream == "" {
		return ""
	}
	upDir, ok := monorepoDir(c.Upstream)
	if !ok {
		return ""
	}
	return classifyUpstream(filepath.Join(root, filepath.FromSlash(c.srcDir())), upDir)
}

// classifyUpstream compares a versioned contract dir against its un-versioned
// monorepo copy: "exact" (every file byte-identical), "gno" (all .gno identical;
// non-.gno files such as gnomod.toml may differ), "gno-notest" (.gno identical
// once test files are skipped on both sides), or "diff" (production .gno differ).
func classifyUpstream(ourDir, upDir string) string {
	if allFilesEqual(ourDir, upDir) {
		return "exact"
	}
	if gnoSetsEqual(ourDir, upDir, true) {
		return "gno"
	}
	if gnoSetsEqual(ourDir, upDir, false) {
		return "gno-notest"
	}
	return "diff"
}

// gnoSetsEqual reports whether both dirs hold the same set of .gno files with
// identical content. When includeTests is false, *_test.gno / *_filetest.gno are
// ignored on both sides.
func gnoSetsEqual(ourDir, upDir string, includeTests bool) bool {
	ours, err := gnoFiles(ourDir)
	if err != nil {
		return false
	}
	up, err := gnoFiles(upDir)
	if err != nil {
		return false
	}
	keep := func(m map[string]string) map[string]string {
		if includeTests {
			return m
		}
		out := map[string]string{}
		for k, v := range m {
			if !isTestGno(k) {
				out[k] = v
			}
		}
		return out
	}
	return sameStringMap(keep(ours), keep(up))
}

// allFilesEqual reports whether both dirs hold exactly the same top-level files
// (by name) with identical content.
func allFilesEqual(ourDir, upDir string) bool {
	a, err := allFiles(ourDir)
	if err != nil {
		return false
	}
	b, err := allFiles(upDir)
	if err != nil {
		return false
	}
	return sameStringMap(a, b)
}

func allFiles(dir string) (map[string]string, error) {
	out := map[string]string{}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return nil, err
		}
		out[e.Name()] = string(b)
	}
	return out, nil
}

func sameStringMap(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if bv, ok := b[k]; !ok || bv != v {
			return false
		}
	}
	return true
}

// upstreamPackages returns the un-versioned pkgpaths of every gno package
// directory under base (a monorepo .../moul tree).
func upstreamPackages(base, prefix string) ([]string, error) {
	var out []string
	err := filepath.Walk(base, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() && info.Name() == "gnomod.toml" {
			if mod, err := parseModule(path); err == nil {
				out = append(out, mod)
			}
		}
		return nil
	})
	return out, err
}
