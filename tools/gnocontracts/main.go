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
//	pr         everything CI needs to know about a pull request: the sticky
//	           comment body, the path labels, the realms to preview
//	preview    render realms with gnodev into a self-contained static tree
//	gno        lint / test / fmt every contract against a stdlib-only GNOROOT
//	upload     the gnokey script for what a network is missing
//	guard-*    the CI guards (examples, render, readmes, generated artifacts)
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
	case "readmes":
		err = cmdReadmes(root)
	case "gen":
		if err = cmdManifest(root); err == nil {
			if err = cmdReadme(root); err == nil {
				err = cmdReadmes(root)
			}
		}
	case "check":
		err = cmdCheck(root)
	case "vendor":
		err = cmdVendor(root, args)
	case "sync":
		err = cmdSync(root, args)
	case "publish":
		err = cmdPublish(root, args)
	case "status":
		err = cmdStatus(root, args)
	case "pr":
		err = cmdPR(root, args)
	case "guard-examples":
		err = cmdGuardExamples(root)
	case "guard-render":
		err = cmdGuardRender(root)
	case "guard-readmes":
		err = cmdGuardReadmes(root, args)
	case "guard-generated":
		err = cmdGuardGenerated(root, args)
	case "preview":
		err = cmdPreview(root, args)
	case "graph":
		err = cmdGraph(root)
	case "gno":
		err = cmdGno(root, args)
	case "upload":
		err = cmdUpload(root, args)
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
  readmes    ensure every package has a README (repo link + disclaimer)
  gen        manifest + readme
  check      gen and fail if anything changed (CI drift guard)
  vendor     fetch external gno.land dependencies into vendor/
  sync       report drift vs the gnolang/gno monorepo (needs GNOROOT)
  publish    order contracts by dependency; -net <name> [-check] for status
  status     refresh on-chain upload status for all networks + README
  pr         analyze the PR diff (base...HEAD) → the sticky comment body, the
             path labels, and the realm selectors to preview
  preview    render the selected realms with gnodev into a static tree
  gno        run the gno toolchain over every contract:
             gno lint | gno test | gno fmt | gno toolcheck | gno list
  upload     write the gnokey script for what a network is missing; -yes runs it
  guard-examples   fail if an Example* test pins no // Output: block
  guard-render     fail if a realm declares Render that no test calls
  guard-readmes    fail if a package ships a README that documents nothing
  guard-generated  fail if a PR modifies generated artifacts
  graph      write per-package + global dependency graphs into _assets/
`)
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(1)
}
