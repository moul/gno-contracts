package main

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

// deployedPath is where a package actually lives on one chain, when that is not
// its canonical path.
//
// A namespace on a gno chain is either the signer's own address or a registered
// name that signer owns (examples/gno.land/r/sys/names/verifier.gno). @moul's
// key owns `moul` on mainnet and nowhere else, so an agent publishing this
// workspace to a testnet can only put it under its OWN address, and
// `gno.land/p/moul/once/v0` goes up as
// `gno.land/p/g1magld5.../once/v0`. gnopm records where it sent each one, as a
// `[[deployment]]` row in the package's gnomod.toml, and that row is the only
// thing connecting the two paths afterwards.
//
// Without this the status probe asks the canonical path, the chain says no, and
// the catalog records the package as absent from a chain that is serving it.
// That is exactly what moul.github.io/gno-contracts showed for onyx: accurate
// about the question it asked, and wrong about the world.
//
// Parsed by hand rather than through a TOML library because the file is written
// by gnopm, the shape is fixed, and the tools module carries no TOML dependency
// to add for five keys.
func deployedPath(root, dir, chainID, pkgPath string) string {
	f, err := os.Open(filepath.Join(root, dir, "gnomod.toml"))
	if err != nil {
		return ""
	}
	defer f.Close()

	var (
		module          string
		inDeployment    bool
		chain, deployed string
		found           string
	)
	// A directory holds ONE version: `p/moul/ulist` carries v1 while v0 lives
	// only on chain, and both are separate contracts sharing this Dir. So a row
	// here describes the version the file declares and nothing else; matching
	// the module line is what keeps v0 from inheriting v1's deployment.
	flush := func() {
		if inDeployment && chain == chainID && deployed != "" {
			found = deployed
		}
		chain, deployed = "", ""
	}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		switch {
		case line == "[[deployment]]":
			flush()
			inDeployment = true
			continue
		case strings.HasPrefix(line, "[["), strings.HasPrefix(line, "["):
			flush()
			inDeployment = false
			continue
		}
		key, val, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		val = strings.Trim(strings.TrimSpace(val), `"`)
		switch {
		case !inDeployment && key == "module":
			module = val
		case inDeployment && key == "chain":
			chain = val
		case inDeployment && key == "path":
			deployed = val
		}
	}
	flush()
	if err := sc.Err(); err != nil {
		return ""
	}
	if module != pkgPath || found == pkgPath {
		return ""
	}
	return found
}
