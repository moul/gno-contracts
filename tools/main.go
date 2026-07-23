// Command gno-contracts is the maintenance CLI for the moul/gno-contracts repo.
//
// Subcommands:
//
//	manifest   scan p/moul and r/moul, refresh contracts.json (preserving
//	           hand-authored descriptions and per-network upload status)
//	readme     regenerate the contracts table in README.md from contracts.json
//	gen        manifest + readme
//	check      gen, then fail if it changed anything (CI drift guard)
//	vendor     fetch every external gno.land dependency into vendor/
//	sync       report drift between our versioned contracts and the monorepo
//	publish    topologically order contracts and (optionally) check on-chain
//	           upload status per network
//
// It is invoked from the repository root, typically via the Makefile
// (`go run ./tools <cmd>`).
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	root, err := repoRoot()
	if err != nil {
		fatal(err)
	}
	cmd := os.Args[1]
	args := os.Args[2:]
	switch cmd {
	case "manifest":
		err = cmdManifest(root)
	case "readme":
		err = cmdReadme(root)
	case "gen":
		if err = cmdManifest(root); err == nil {
			err = cmdReadme(root)
		}
	case "check":
		err = cmdCheck(root)
	case "vendor":
		err = cmdVendor(root)
	case "sync":
		err = cmdSync(root, args)
	case "publish":
		err = cmdPublish(root, args)
	case "help", "-h", "--help":
		usage()
		return
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n", cmd)
		usage()
		os.Exit(2)
	}
	if err != nil {
		fatal(err)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `gno-contracts — repository maintenance CLI

usage: go run ./tools <command> [flags]

commands:
  manifest   refresh contracts.json from the p/moul and r/moul trees
  readme     regenerate the contracts table in README.md
  gen        manifest + readme
  check      gen and fail if anything changed (CI drift guard)
  vendor     fetch external gno.land dependencies into vendor/
  sync       report drift vs the gnolang/gno monorepo (needs GNOROOT)
  publish    order contracts by dependency; -net <name> [-check] for status
`)
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}
