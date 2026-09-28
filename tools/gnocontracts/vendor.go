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
	fromChain := fs.String("from-chain", "", "RPC endpoint to fall back to for deps absent from $GNOROOT/examples (e.g. https://rpc.gno.land)")
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
		deps, err := parseDepsMode(filepath.Join(root, filepath.FromSlash(c.srcDir())), true)
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

	// Seed from what is ALREADY vendored as well, not only from our contracts.
	// A vendored package is `provided`, so the walk below never opens it, and
	// its own unvendored deps would stay invisible: an interrupted run would
	// then report "nothing to do" on the next one, with the tree still missing
	// packages. Hit while vendoring GnoSwap, where one 403 mid-closure was
	// enough to produce exactly that.
	if err := enqueueVendoredDeps(vendorDir, provided, enqueued, &queue); err != nil {
		return err
	}

	var vendored []string
	for len(queue) > 0 {
		pkg := queue[0]
		queue = queue[1:]
		if provided[pkg] {
			continue
		}
		src := filepath.Join(examples, filepath.FromSlash(pkg))
		dst := filepath.Join(vendorDir, filepath.FromSlash(pkg))
		// examples wins whenever it has the package, so a dep that exists both
		// in the monorepo and on a chain is always vendored from the monorepo
		// and the two sources cannot disagree about it. The chain is the
		// fallback for what was only ever deployed.
		depsDir := src
		switch {
		case fileExists(src):
			if err := copyGnoPackage(src, dst); err != nil {
				return fmt.Errorf("vendor %s: %w", pkg, err)
			}
		case *fromChain != "":
			if err := vendorFromChain(*fromChain, pkg, dst); err != nil {
				return fmt.Errorf("vendor %s from %s: %w", pkg, *fromChain, err)
			}
			depsDir = dst
		default:
			return fmt.Errorf("dependency %q not found under %s (pass -from-chain <rpc> to fetch a package that lives only on a chain)", pkg, examples)
		}
		provided[pkg] = true
		vendored = append(vendored, pkg)
		// enqueue transitive deps
		deps, err := parseDeps(depsDir)
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
// workspace: our p/moul and r/moul contracts, anything under vendor/, and the
// superseded versions gnopm materializes into .gnopm/.
//
// .gnopm/ counts because a contract that still imports .../humanize/v0 after
// humanize was bumped resolves it from there, so vendoring it would be a second
// copy of something the workspace already answers for. It is gitignored and
// only exists after `gnopm sync`, so its absence is not an error.
func workspaceModules(root string) (map[string]bool, error) {
	set := map[string]bool{}
	scanned, err := scanContracts(root)
	if err != nil {
		return nil, err
	}
	for _, c := range scanned {
		set[c.PkgPath] = true
	}
	for _, dir := range []string{"vendor", ".gnopm"} {
		if err := collectModules(filepath.Join(root, dir), set); err != nil {
			return nil, err
		}
	}
	return set, nil
}

// collectModules adds every module path declared under dir to set. A missing
// dir contributes nothing rather than failing.
func collectModules(dir string, set map[string]bool) error {
	if !fileExists(dir) {
		return nil
	}
	return filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
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

// vendorFromChain writes one deployed package into vendor/, the chain-sourced
// counterpart of copyGnoPackage. It writes nothing until every file has been
// fetched, so an endpoint that fails halfway leaves no half-vendored package
// behind for the next run to mistake for a complete one.
func vendorFromChain(rpc, pkgpath, dst string) error {
	files, err := fetchChainPackage(rpc, pkgpath)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dst, name), []byte(body), 0o644); err != nil {
			return err
		}
	}
	return nil
}

// enqueueVendoredDeps adds the still-missing dependencies of every package
// already under vendor/ to the work queue.
func enqueueVendoredDeps(vendorDir string, provided, enqueued map[string]bool, queue *[]string) error {
	if !fileExists(vendorDir) {
		return nil
	}
	return filepath.Walk(vendorDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() || info.Name() != "gnomod.toml" {
			return nil
		}
		deps, err := parseDeps(filepath.Dir(path))
		if err != nil {
			return err
		}
		for _, d := range deps {
			if !provided[d] && !enqueued[d] {
				*queue = append(*queue, d)
				enqueued[d] = true
			}
		}
		return nil
	})
}
