package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// cmdVendor makes the repository self-contained: it copies every external
// gno.land dependency (transitively) of our contracts into vendor/<pkgpath>,
// each with its gnomod.toml, so the gno workspace resolves them without relying
// on $GNOROOT/examples. Only gno stdlib imports (non-gno.land) are left to the
// toolchain. Source is $GNOROOT/examples.
//
// By default only MISSING dependencies are fetched — an already-vendored
// package is left untouched, so a plain run is a no-op once everything resolves.
// That is deliberate (vendor/ is a pinned snapshot; bumps are explicit), but it
// means vendor/ silently rots as the monorepo moves. `-refresh` re-copies every
// dependency from the current $GNOROOT/examples: that IS the gno bump.
func cmdVendor(root string, args []string) error {
	fs := flag.NewFlagSet("vendor", flag.ContinueOnError)
	refresh := fs.Bool("refresh", false, "re-copy already-vendored packages from $GNOROOT/examples (bump the pinned snapshot)")
	if err := fs.Parse(args); err != nil {
		return err
	}

	gnoroot := os.Getenv("GNOROOT")
	if gnoroot == "" {
		return fmt.Errorf("GNOROOT must be set (path to a gnolang/gno checkout)")
	}
	examples := filepath.Join(gnoroot, "examples")
	if !fileExists(examples) {
		return fmt.Errorf("no examples/ under GNOROOT %q", gnoroot)
	}
	vendorDir := filepath.Join(root, "vendor")

	// Packages already provided by the workspace: our own contracts, plus
	// whatever is already vendored.
	provided, err := workspaceModules(root)
	if err != nil {
		return err
	}

	// On -refresh, empty vendor/ and re-derive `provided` from our own contracts
	// alone, so every external dep is re-fetched from the current examples/.
	// Wiping (rather than copying over) is what drops files deleted upstream —
	// copyGnoPackage only ever writes, so a stale leftover would survive.
	// .gitkeep is preserved: it is what keeps vendor/ present when empty.
	if *refresh {
		entries, err := os.ReadDir(vendorDir)
		if err != nil && !os.IsNotExist(err) {
			return err
		}
		for _, e := range entries {
			if e.Name() == ".gitkeep" {
				continue
			}
			if err := os.RemoveAll(filepath.Join(vendorDir, e.Name())); err != nil {
				return err
			}
		}
		ours := map[string]bool{}
		contracts, err := scanContracts(root)
		if err != nil {
			return err
		}
		for _, c := range contracts {
			ours[c.PkgPath] = true
		}
		provided = ours
	}

	// Seed the queue with our contracts' direct deps, INCLUDING test-only
	// dependencies (so `gno test` resolves everything from vendor/).
	scanned, err := scanContracts(root)
	if err != nil {
		return err
	}
	queue := []string{}
	enqueued := map[string]bool{}
	for _, c := range scanned {
		// Archived (ignore=true) packages are skipped by the gno toolchain and
		// their (often stale) imports may not resolve on master — don't try to
		// vendor their deps.
		if c.Ignored {
			continue
		}
		deps, err := parseDepsMode(filepath.Join(root, filepath.FromSlash(c.Dir)), true)
		if err != nil {
			return err
		}
		for _, d := range deps {
			if !provided[d] && !enqueued[d] {
				queue = append(queue, d)
				enqueued[d] = true
			}
		}
	}

	var vendored []string
	for len(queue) > 0 {
		pkg := queue[0]
		queue = queue[1:]
		if provided[pkg] {
			continue
		}
		src := filepath.Join(examples, filepath.FromSlash(pkg))
		if !fileExists(src) {
			return fmt.Errorf("dependency %q not found under %s (vendor from another source not yet supported)", pkg, examples)
		}
		dst := filepath.Join(vendorDir, filepath.FromSlash(pkg))
		if err := copyGnoPackage(src, dst); err != nil {
			return fmt.Errorf("vendor %s: %w", pkg, err)
		}
		provided[pkg] = true
		vendored = append(vendored, pkg)
		// enqueue transitive deps
		deps, err := parseDeps(src)
		if err != nil {
			return err
		}
		for _, d := range deps {
			if strings.HasPrefix(d, "gno.land/") && !provided[d] && !enqueued[d] {
				queue = append(queue, d)
				enqueued[d] = true
			}
		}
	}

	if len(vendored) == 0 {
		fmt.Println("vendor: nothing to do (all dependencies already provided)")
		return nil
	}
	fmt.Printf("vendor: fetched %d package(s):\n", len(vendored))
	for _, v := range vendored {
		fmt.Println("  +", v)
	}
	return nil
}

// workspaceModules returns the set of module paths already resolvable in the
// workspace: our p/moul and r/moul contracts plus anything under vendor/.
func workspaceModules(root string) (map[string]bool, error) {
	set := map[string]bool{}
	scanned, err := scanContracts(root)
	if err != nil {
		return nil, err
	}
	for _, c := range scanned {
		set[c.PkgPath] = true
	}
	vendorDir := filepath.Join(root, "vendor")
	if fileExists(vendorDir) {
		err := filepath.Walk(vendorDir, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			if !info.IsDir() && info.Name() == "gnomod.toml" {
				if mod, err := parseModule(path); err == nil {
					set[mod] = true
				}
			}
			return nil
		})
		if err != nil {
			return nil, err
		}
	}
	return set, nil
}

// copyGnoPackage copies the .gno sources and gnomod.toml of a single package
// directory (flat; gno packages are not nested).
func copyGnoPackage(src, dst string) error {
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		n := e.Name()
		if !strings.HasSuffix(n, ".gno") && n != "gnomod.toml" {
			continue
		}
		if err := copyFile(filepath.Join(src, n), filepath.Join(dst, n)); err != nil {
			return err
		}
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}
