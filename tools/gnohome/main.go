// Command gnohome drives the gno.land/r/moul/home realm from local markdown.
//
// The realm stores named markdown fragments ("slots") and assembles them
// through a layout slot. This tool is the local half of that loop:
//
//	gnohome slots     list the local slots, with sizes and hashes
//	gnohome preview   render the page locally, the way the realm would
//	gnohome status    diff local content/ against what is on chain
//	gnohome tx        print the gnokey commands for exactly what is outdated
//	gnohome packages  regenerate the packages slot from contracts.json
//
// Deploying the realm is NOT here: that is `gnopm publish`, which does it for
// any package in any workspace rather than once per contract.
//
// It has no dependencies beyond the Go standard library: the chain is read
// over plain JSON-RPC abci_query, and writes are emitted as gnokey commands
// rather than signed here, so nothing broadcasts by accident.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

// Defaults mirror the realm. Keep them in sync with r/moul/home/home.gno.
const (
	defaultRealm   = "gno.land/r/moul/home"
	defaultRemote  = "https://rpc.gno.land:443"
	defaultChainID = "gnoland-1"
	defaultKey     = "moul"
	defaultOwner   = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
)

type config struct {
	contentDir string
	realm      string
	remote     string
	chainID    string
	key        string
	owner      string
}

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "gnohome: "+err.Error())
		os.Exit(1)
	}
}

func run(args []string, out *os.File) error {
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
		usage(out)
		return nil
	}
	cmd, rest := args[0], args[1:]

	fs := flag.NewFlagSet("gnohome "+cmd, flag.ContinueOnError)
	var cfg config
	fs.StringVar(&cfg.contentDir, "content", "", "directory holding the slot markdown (default: <repo>/r/moul/home/content)")
	fs.StringVar(&cfg.realm, "realm", defaultRealm, "realm package path")
	fs.StringVar(&cfg.remote, "remote", defaultRemote, "RPC endpoint")
	fs.StringVar(&cfg.chainID, "chainid", defaultChainID, "chain id, for the emitted gnokey commands")
	fs.StringVar(&cfg.key, "key", defaultKey, "gnokey key name, for the emitted gnokey commands")
	fs.StringVar(&cfg.owner, "owner", defaultOwner, "address used for the :owner: placeholder in preview")

	// Per-command flags.
	var (
		previewOut  string
		height      int64
		rev         int
		inline      bool
		all         bool
		prune       bool
		gasWanted   int64
		gasFee      string
		maxDeposit  string
		batchOut    string
		catalogFile string
		network     string
	)
	switch cmd {
	case "preview":
		fs.StringVar(&previewOut, "out", "", "write the rendered page to this file instead of stdout")
		fs.Int64Var(&height, "height", 0, "value for the :height: placeholder")
		fs.IntVar(&rev, "rev", 0, "value for the :rev: placeholder")
	case "tx":
		fs.BoolVar(&inline, "inline", false, `embed each body as a literal instead of "$(cat <file>)"`)
		fs.BoolVar(&all, "all", false, "emit a command for every slot, not only the outdated ones")
		fs.BoolVar(&prune, "prune", false, "also emit Delete for slots on chain with no local file")
		fs.Int64Var(&gasWanted, "gas-wanted", 0, "gas-wanted override (default: sized from the body)")
		fs.StringVar(&gasFee, "gas-fee", "", "gas-fee override (default: sized from -gas-wanted at ten times the accepted floor)")
		fs.StringVar(&maxDeposit, "max-deposit", "", "max storage deposit for the emitted commands")
		fs.StringVar(&batchOut, "batch", "", "write ONE transaction holding every change to this file, to sign once")
	case "packages":
		fs.StringVar(&catalogFile, "catalog", "", "path to contracts.json (default: <repo>/contracts.json)")
		fs.StringVar(&network, "network", "mainnet", "which network's deployment status to report")
	}
	if err := fs.Parse(rest); err != nil {
		return err
	}

	// packages GENERATES a slot body, so it runs before the content directory
	// is resolved and without loading any slot: it must work on a checkout
	// where content/ is empty or absent.
	if cmd == "packages" {
		if catalogFile == "" {
			path, err := catalogPath()
			if err != nil {
				return err
			}
			catalogFile = path
		}
		c, err := loadCatalog(catalogFile)
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(out, renderPackages(c, network))
		return err
	}

	if cfg.contentDir == "" {
		dir, err := defaultContentDir()
		if err != nil {
			return err
		}
		cfg.contentDir = dir
	}

	local, err := loadSlots(cfg.contentDir)
	if err != nil {
		return err
	}

	switch cmd {
	case "slots":
		return printSlots(out, local)
	case "preview":
		page := render(local, env{
			owner:   cfg.owner,
			realm:   cfg.realm,
			chainID: cfg.chainID,
			height:  height,
			rev:     rev,
		})
		if previewOut == "" {
			_, err := fmt.Fprint(out, page)
			return err
		}
		if err := os.MkdirAll(filepath.Dir(previewOut), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(previewOut, []byte(page), 0o644); err != nil {
			return err
		}
		fmt.Fprintf(out, "wrote %s (%d bytes)\n", previewOut, len(page))
		return nil
	case "status":
		remote, err := fetchManifest(cfg.remote, cfg.realm)
		if err != nil {
			return err
		}
		return printStatus(out, diff(local, remote))
	case "tx":
		var d []change
		if all {
			d = allChanges(local)
		} else {
			remote, err := fetchManifest(cfg.remote, cfg.realm)
			if err != nil {
				return err
			}
			d = diff(local, remote)
		}
		warnOversize(out, local)
		if batchOut != "" {
			return printBatch(out, cfg, d, txOptions{
				inline: inline, prune: prune, gasWanted: gasWanted,
				gasFee: gasFee, maxDeposit: maxDeposit,
			}, batchOut)
		}
		return printTx(out, cfg, d, txOptions{
			inline:     inline,
			prune:      prune,
			gasWanted:  gasWanted,
			gasFee:     gasFee,
			maxDeposit: maxDeposit,
		})
	default:
		usage(out)
		return fmt.Errorf("unknown command %q", cmd)
	}
}

func usage(out *os.File) {
	fmt.Fprint(out, `gnohome: drive gno.land/r/moul/home from local markdown

usage: gnohome <command> [flags]

commands:
  slots     list the local slots, with sizes and hashes
  preview   render the page locally, the way the realm would
  status    diff local content/ against what is on chain
  tx        print the gnokey commands for exactly what is outdated
            -batch FILE writes ONE transaction instead, to sign once
  packages  regenerate the packages slot from contracts.json, to stdout

Deploying the realm is "gnopm publish", not a command here.

Run "gnohome <command> -h" for the flags of one command.
`)
}

// defaultContentDir walks up from the working directory to the repo root
// (the directory holding gnowork.toml) and returns the
// realm's content directory under it.
func defaultContentDir() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "gnowork.toml")); err == nil {
			return filepath.Join(dir, "r", "moul", "home", "content"), nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("no gnowork.toml above the working directory: pass -content")
		}
		dir = parent
	}
}

func printSlots(out *os.File, slots []slotFile) error {
	if len(slots) == 0 {
		fmt.Fprintln(out, "no slots")
		return nil
	}
	w := 0
	for _, s := range slots {
		if len(s.slug) > w {
			w = len(s.slug)
		}
	}
	for _, s := range slots {
		fmt.Fprintf(out, "%-*s  %6d  %s  %s\n", w, s.slug, len(s.body), short(s.hash), s.path)
	}
	return nil
}

func printStatus(out *os.File, changes []change) error {
	if len(changes) == 0 {
		fmt.Fprintln(out, "up to date: every local slot matches the chain")
		return nil
	}
	w := 0
	for _, c := range changes {
		if len(c.slug) > w {
			w = len(c.slug)
		}
	}
	n := 0
	for _, c := range changes {
		fmt.Fprintf(out, "%-9s %-*s  %s\n", c.kind, w, c.slug, c.detail)
		if c.kind != kindExtra {
			n++
		}
	}
	fmt.Fprintf(out, "\n%d slot(s) to push. Run: gnohome tx\n", n)
	return nil
}

func printTx(out *os.File, cfg config, changes []change, opt txOptions) error {
	emitted := 0
	for _, c := range emittable(changes, opt.prune) {
		fmt.Fprint(out, command(cfg, c, opt))
		fmt.Fprintln(out)
		emitted++
	}
	if emitted == 0 {
		fmt.Fprintln(out, "# nothing to do")
	}
	return nil
}

// oversizeThreshold is the body size past which a single MsgCall may not fit in
// a transaction. The realm's Append exists for exactly this case.
const oversizeThreshold = 60 * 1024

func warnOversize(out *os.File, slots []slotFile) {
	for _, s := range slots {
		if len(s.body) > oversizeThreshold {
			fmt.Fprintf(out, "# warning: slot %q is %d bytes; if the transaction is rejected,\n"+
				"#          split it with Set + Append (see the realm's README).\n",
				s.slug, len(s.body))
		}
	}
}
