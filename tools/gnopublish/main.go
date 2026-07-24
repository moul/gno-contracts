// Command gnopublish publishes moul/gno-contracts packages to a gno.land network.
//
// It reads contracts.json, resolves the path selectors you pass (./..., ./p/moul/x,
// ./r/moul/...), queries the target network to see which of the selected packages
// are missing (or, with -full, out of date vs their on-chain content), orders the
// work so every dependency is uploaded before its dependents, prints the plan,
// asks for your gnokey password ONCE, then broadcasts — either one tx per package
// (individual blocks, the default) or everything merged into a single tx (-mode merge).
//
// Build/run needs a local gno checkout (see go.mod replace) and a C toolchain.
//
//	go run . -net test6 -key mykey ./...
//	go run . -net test6 -key mykey -mode merge ./p/moul/...
//	go run . -net test6 -key mykey -full ./r/moul/hello
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/gnolang/gno/gno.land/pkg/gnoclient"
	vm "github.com/gnolang/gno/gno.land/pkg/sdk/vm"
	"github.com/gnolang/gno/gnovm/pkg/gnolang"
	rpcclient "github.com/gnolang/gno/tm2/pkg/bft/rpc/client"
	"github.com/gnolang/gno/tm2/pkg/crypto/keys"
	"github.com/gnolang/gno/tm2/pkg/std"
	"golang.org/x/term"
)

// --- contracts.json (minimal view) ---------------------------------------

type manifest struct {
	Networks  []network  `json:"networks"`
	Contracts []contract `json:"contracts"`
}

type network struct {
	Name    string `json:"name"`
	ChainID string `json:"chain_id"`
	RPC     string `json:"rpc"`
}

type contract struct {
	PkgPath string   `json:"pkgpath"`
	Dir     string   `json:"dir"`
	Deps    []string `json:"deps"`
	Draft   bool     `json:"draft"`
	Ignored bool     `json:"ignored"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run() error {
	fs := flag.NewFlagSet("gnopublish", flag.ContinueOnError)
	netName := fs.String("net", "", "network name from contracts.json (default: first network)")
	rpcURL := fs.String("rpc", "", "override RPC endpoint")
	chainID := fs.String("chain-id", "", "override chain id")
	keyName := fs.String("key", os.Getenv("GNOKEY_KEY"), "gnokey key name or bech32 address (or $GNOKEY_KEY)")
	home := fs.String("home", gnokeyHome(), "gnokey home directory")
	mode := fs.String("mode", "individual", "\"individual\" (one tx per package) or \"merge\" (one tx for all)")
	full := fs.Bool("full", false, "also re-publish packages whose on-chain content differs from local")
	gasFee := fs.String("gas-fee", "1000000ugnot", "gas fee")
	gasWanted := fs.Int64("gas-wanted", 20000000, "gas wanted")
	deposit := fs.String("deposit", "", "max storage deposit (e.g. 1000000ugnot); empty = node default")
	dryRun := fs.Bool("dry-run", false, "print the plan and exit without broadcasting")
	yes := fs.Bool("yes", false, "skip the confirmation prompt")
	fs.Usage = usage(fs)
	if err := fs.Parse(os.Args[1:]); err != nil {
		return err
	}
	selectors := fs.Args()
	if len(selectors) == 0 {
		selectors = []string{"./..."}
	}
	if *mode != "individual" && *mode != "merge" {
		return fmt.Errorf("-mode must be \"individual\" or \"merge\"")
	}

	root, err := repoRoot()
	if err != nil {
		return err
	}
	m, err := loadManifest(root)
	if err != nil {
		return err
	}
	net, err := pickNetwork(m, *netName, *rpcURL, *chainID)
	if err != nil {
		return err
	}

	// Select packages, drop draft/ignored (not publishable), then order deps-first.
	selected, skipped := selectContracts(m.Contracts, selectors)
	if len(selected) == 0 {
		return fmt.Errorf("no publishable packages match %v", selectors)
	}
	ordered, err := topoOrder(selected)
	if err != nil {
		return err
	}

	// Connect and compute per-package on-chain state.
	cli, err := rpcclient.NewHTTPClient(net.RPC)
	if err != nil {
		return fmt.Errorf("rpc %s: %w", net.RPC, err)
	}
	client := &gnoclient.Client{RPCClient: cli}

	fmt.Printf("network: %s (%s)  rpc: %s\n", net.Name, net.ChainID, net.RPC)
	fmt.Printf("selected %d package(s); %d skipped (draft/ignored)\n\n", len(ordered), len(skipped))

	type plan struct {
		c      contract
		reason string // "missing" | "out-of-date"
	}
	var todo []plan
	fmt.Println("status (dependency order):")
	for _, c := range ordered {
		absDir := filepath.Join(root, filepath.FromSlash(c.Dir))
		onchain := packageExists(client, c.PkgPath)
		state := "up-to-date"
		var reason string
		switch {
		case !onchain:
			state, reason = "MISSING", "missing"
		case *full:
			same, derr := contentUpToDate(client, c.PkgPath, absDir)
			if derr != nil {
				state = "check-failed: " + derr.Error()
			} else if !same {
				state, reason = "OUT-OF-DATE", "out-of-date"
			}
		}
		if reason != "" {
			todo = append(todo, plan{c, reason})
		}
		fmt.Printf("  %-48s %s\n", c.PkgPath, state)
	}
	for _, s := range skipped {
		fmt.Printf("  %-48s skipped (%s)\n", s.PkgPath, skipReason(s))
	}

	if len(todo) == 0 {
		fmt.Println("\nNothing to publish — everything selected is already on chain" + fullNote(*full) + ".")
		return nil
	}

	fmt.Printf("\nplan: publish %d package(s) in this order (%s mode):\n", len(todo), *mode)
	for i, p := range todo {
		fmt.Printf("  %2d. %s  [%s]\n", i+1, p.c.PkgPath, p.reason)
	}

	if *dryRun {
		fmt.Println("\n(dry-run) not broadcasting.")
		return nil
	}
	if *keyName == "" {
		return fmt.Errorf("-key <name|address> is required to broadcast (or set $GNOKEY_KEY)")
	}

	// Build the signer — password prompted ONCE, reused for every tx.
	kb, err := keys.NewKeyBaseFromDir(*home)
	if err != nil {
		return fmt.Errorf("open gnokey home %s: %w", *home, err)
	}
	info, err := kb.GetByNameOrAddress(*keyName)
	if err != nil {
		return fmt.Errorf("key %q not found in %s: %w", *keyName, *home, err)
	}
	addr := info.GetAddress()

	txCount := len(todo)
	if *mode == "merge" {
		txCount = 1
	}
	if !*yes {
		fmt.Printf("\nabout to broadcast %d tx(s) as %s (%s) on %s. proceed? [y/N] ", txCount, *keyName, addr, net.Name)
		if !confirm() {
			return fmt.Errorf("aborted")
		}
	}
	pass, err := promptPassword(fmt.Sprintf("gnokey password for %q: ", *keyName))
	if err != nil {
		return err
	}
	client.Signer = &gnoclient.SignerFromKeybase{Keybase: kb, Account: *keyName, Password: pass, ChainID: net.ChainID}

	// Account number + starting sequence.
	acc, _, err := client.QueryAccount(addr)
	if err != nil {
		return fmt.Errorf("query account %s: %w", addr, err)
	}

	// Build one MsgAddPackage per package.
	var maxDep std.Coins
	if *deposit != "" {
		if maxDep, err = std.ParseCoins(*deposit); err != nil {
			return fmt.Errorf("bad -deposit: %w", err)
		}
	}
	var msgs []vm.MsgAddPackage
	for _, p := range todo {
		absDir := filepath.Join(root, filepath.FromSlash(p.c.Dir))
		mempkg, err := gnolang.ReadMemPackage(absDir, p.c.PkgPath, gnolang.MPUserProd)
		if err != nil {
			return fmt.Errorf("read %s: %w", p.c.Dir, err)
		}
		msgs = append(msgs, vm.MsgAddPackage{Creator: addr, Package: mempkg, MaxDeposit: maxDep})
	}

	baseCfg := func(seq uint64) gnoclient.BaseTxCfg {
		return gnoclient.BaseTxCfg{
			GasFee:         *gasFee,
			GasWanted:      *gasWanted,
			AccountNumber:  acc.AccountNumber,
			SequenceNumber: seq,
			Memo:           "gnopublish",
		}
	}

	fmt.Println()
	if *mode == "merge" {
		res, err := client.AddPackage(baseCfg(acc.Sequence), msgs...)
		if err != nil {
			return fmt.Errorf("broadcast merged tx: %w", err)
		}
		fmt.Printf("✅ merged tx: %d package(s) in one block — hash %s\n", len(msgs), res.Hash)
		return nil
	}
	// individual: one tx (block) per package, sequence incremented locally.
	seq := acc.Sequence
	for i, msg := range msgs {
		res, err := client.AddPackage(baseCfg(seq), msg)
		if err != nil {
			return fmt.Errorf("broadcast %s (%d/%d): %w", todo[i].c.PkgPath, i+1, len(msgs), err)
		}
		fmt.Printf("✅ %2d/%d %s — hash %s\n", i+1, len(msgs), todo[i].c.PkgPath, res.Hash)
		seq++
	}
	fmt.Printf("\ndone: published %d package(s) on %s.\n", len(msgs), net.Name)
	return nil
}

// --- selection & ordering -------------------------------------------------

func selectContracts(cs []contract, selectors []string) (selected, skipped []contract) {
	for _, c := range cs {
		if !matchesAny(c.Dir, selectors) {
			continue
		}
		if c.Draft || c.Ignored {
			skipped = append(skipped, c)
			continue
		}
		selected = append(selected, c)
	}
	return
}

func matchesAny(dir string, selectors []string) bool {
	for _, sel := range selectors {
		s := strings.TrimSuffix(strings.TrimPrefix(sel, "./"), "/")
		switch {
		case s == "" || s == "...":
			return true
		case strings.HasSuffix(s, "/..."):
			base := strings.TrimSuffix(s, "/...")
			if dir == base || strings.HasPrefix(dir, base+"/") {
				return true
			}
		default:
			if dir == s || strings.HasPrefix(dir, s+"/") {
				return true
			}
		}
	}
	return false
}

// topoOrder returns contracts deps-first (a package after every selected package
// it imports). Deps outside the selected set are ignored (assumed already on chain).
func topoOrder(cs []contract) ([]contract, error) {
	in := map[string]contract{}
	for _, c := range cs {
		in[c.PkgPath] = c
	}
	indeg := map[string]int{}
	dependents := map[string][]string{}
	for _, c := range cs {
		n := 0
		for _, d := range c.Deps {
			if _, ok := in[d]; ok {
				n++
				dependents[d] = append(dependents[d], c.PkgPath)
			}
		}
		indeg[c.PkgPath] = n
	}
	var ready []string
	for p, d := range indeg {
		if d == 0 {
			ready = append(ready, p)
		}
	}
	sort.Strings(ready)
	var out []contract
	for len(ready) > 0 {
		p := ready[0]
		ready = ready[1:]
		out = append(out, in[p])
		var nl []string
		for _, dep := range dependents[p] {
			if indeg[dep]--; indeg[dep] == 0 {
				nl = append(nl, dep)
			}
		}
		sort.Strings(nl)
		ready = append(ready, nl...)
		sort.Strings(ready)
	}
	if len(out) != len(cs) {
		return nil, fmt.Errorf("dependency cycle among selected packages")
	}
	return out, nil
}

// --- on-chain queries -----------------------------------------------------

// packageExists reports whether pkgpath resolves on chain (vm/qfile of the dir
// returns the file listing).
func packageExists(c *gnoclient.Client, pkgpath string) bool {
	res, err := c.Query(gnoclient.QueryCfg{Path: "vm/qfile", Data: []byte(pkgpath)})
	if err != nil || res == nil || res.Response.IsErr() {
		return false
	}
	return len(res.Response.Data) > 0
}

// contentUpToDate compares every local (non-test) file against its on-chain copy.
func contentUpToDate(c *gnoclient.Client, pkgpath, absDir string) (bool, error) {
	mempkg, err := gnolang.ReadMemPackage(absDir, pkgpath, gnolang.MPUserProd)
	if err != nil {
		return false, err
	}
	for _, f := range mempkg.Files {
		res, err := c.Query(gnoclient.QueryCfg{Path: "vm/qfile", Data: []byte(pkgpath + "/" + f.Name)})
		if err != nil || res == nil || res.Response.IsErr() {
			return false, nil // file missing on chain ⇒ not up to date
		}
		if string(res.Response.Data) != f.Body {
			return false, nil
		}
	}
	return true, nil
}

// --- helpers --------------------------------------------------------------

func pickNetwork(m *manifest, name, rpc, chainID string) (network, error) {
	var n network
	switch {
	case name != "":
		found := false
		for _, x := range m.Networks {
			if x.Name == name {
				n, found = x, true
			}
		}
		if !found {
			return n, fmt.Errorf("unknown network %q (see contracts.json)", name)
		}
	case len(m.Networks) > 0:
		n = m.Networks[0]
	}
	if rpc != "" {
		n.RPC = rpc
	}
	if chainID != "" {
		n.ChainID = chainID
	}
	if n.RPC == "" {
		return n, fmt.Errorf("no RPC endpoint (pass -rpc or add a network to contracts.json)")
	}
	if n.ChainID == "" {
		return n, fmt.Errorf("no chain id for %q (pass -chain-id)", n.Name)
	}
	return n, nil
}

func loadManifest(root string) (*manifest, error) {
	b, err := os.ReadFile(filepath.Join(root, "contracts.json"))
	if err != nil {
		return nil, err
	}
	var m manifest
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, fmt.Errorf("parse contracts.json: %w", err)
	}
	return &m, nil
}

func repoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "gnowork.toml")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("gnowork.toml not found in any parent of the working directory")
		}
		dir = parent
	}
}

func gnokeyHome() string {
	if h := os.Getenv("GNOKEY_HOME"); h != "" {
		return h
	}
	if h, err := os.UserHomeDir(); err == nil {
		return filepath.Join(h, ".gnokey")
	}
	return ".gnokey"
}

func skipReason(c contract) string {
	if c.Ignored {
		return "ignored"
	}
	return "draft"
}

func fullNote(full bool) string {
	if full {
		return " and content-current"
	}
	return ""
}

func promptPassword(prompt string) (string, error) {
	if p := os.Getenv("GNOKEY_PASSWORD"); p != "" {
		return p, nil
	}
	fmt.Print(prompt)
	b, err := term.ReadPassword(int(os.Stdin.Fd()))
	fmt.Println()
	if err != nil {
		return "", fmt.Errorf("read password: %w", err)
	}
	return string(b), nil
}

func confirm() bool {
	var s string
	fmt.Scanln(&s)
	s = strings.ToLower(strings.TrimSpace(s))
	return s == "y" || s == "yes"
}

func usage(fs *flag.FlagSet) func() {
	return func() {
		fmt.Fprint(os.Stderr, `gnopublish — publish moul/gno-contracts packages to a gno.land network

usage: gnopublish [flags] [selectors...]

selectors (repo-relative; default "./..."):
  ./...              every package
  ./p/moul/hello     the hello package (all its versions)
  ./p/moul/hello/v1  one exact version
  ./r/moul/...       everything under r/moul

flags:
`)
		fs.PrintDefaults()
	}
}
