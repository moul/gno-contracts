package main

// `gnocontracts upload`: ask gnopm what is missing on a network, write the
// gnokey commands to a file, and run that file only when told to.
//
// Three things here are load-bearing, and each one bit while this was a
// Makefile recipe wrapping a python one-liner:
//
//  1. The script is RUN FROM A FILE, never piped. gnokey reads its passphrase
//     with term.ReadPassword on fd 0 (tm2/pkg/commands/utils.go), so the
//     `gnopm publish | sh` form gnopm's own help suggests hands gnokey a pipe
//     as stdin and the prompt fails. `sh <file>` leaves stdin the terminal.
//  2. An unknown -net is an ERROR, not an empty string. gnopm discovers the
//     chain from the package path, so `gno.land/...` means MAINNET unless told
//     otherwise, and the `$(shell)` this replaces could not fail: a typo'd
//     network name expanded to nothing and produced a mainnet script.
//  3. A run that fails leaves NO script behind, so `sh .cache/publish.sh` can
//     never replay a stale plan aimed at a different chain.

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func cmdUpload(root string, args []string) error {
	fs := flag.NewFlagSet("upload", flag.ContinueOnError)
	net := fs.String("net", "", "network from contracts.json; empty lets the package path pick, which is mainnet")
	key := fs.String("key", "", "gnokey key name for the emitted commands")
	yes := fs.Bool("yes", false, "run the script instead of printing it for review")
	out := fs.String("o", ".cache/publish.sh", "where to write the script")
	if err := fs.Parse(args); err != nil {
		return err
	}

	pub := []string{"publish"}
	if *net != "" {
		n, err := lookupNetwork(root, *net)
		if err != nil {
			return err
		}
		pub = append(pub, "-rpc", n.RPC, "-chainid", n.ChainID)
	}
	if *key != "" {
		pub = append(pub, "-key", *key)
	}
	pub = append(pub, fs.Args()...)

	script := underRoot(root, *out)
	if err := os.MkdirAll(filepath.Dir(script), 0o755); err != nil {
		return err
	}
	// Before anything that can fail (see 3 above).
	if err := os.Remove(script); err != nil && !os.IsNotExist(err) {
		return err
	}

	f, err := os.OpenFile(script, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	cmd := exec.Command("go", append([]string{"tool", "gnopm", "-C", root}, pub...)...)
	cmd.Dir = filepath.Join(root, "tools")
	cmd.Stdout, cmd.Stderr = f, os.Stderr // stdout is the script, stderr the report
	runErr := cmd.Run()
	st, statErr := f.Stat()
	f.Close()
	if runErr != nil {
		os.Remove(script)
		return fmt.Errorf("gnopm publish: %w", runErr)
	}
	if statErr != nil {
		return statErr
	}
	if st.Size() == 0 {
		os.Remove(script)
		return nil // nothing missing on that chain
	}

	rel, _ := filepath.Rel(root, script)
	if !*yes {
		body, err := os.ReadFile(script)
		if err != nil {
			return err
		}
		os.Stdout.Write(body)
		fmt.Printf("\n== reviewed? then: make upload%s YES=1  (or: sh %s) ==\n", netArg(*net), rel)
		return nil
	}
	fmt.Printf("== running %s ==\n", rel)
	sh := exec.Command("sh", script)
	sh.Dir = root
	sh.Stdin, sh.Stdout, sh.Stderr = os.Stdin, os.Stdout, os.Stderr // stdin: see 1 above
	return sh.Run()
}

func netArg(net string) string {
	if net == "" {
		return ""
	}
	return " NET=" + net
}

// lookupNetwork resolves a network name against the catalog, and names the ones
// it knows when the name is wrong.
func lookupNetwork(root, name string) (Network, error) {
	m, err := loadManifest(root)
	if err != nil {
		return Network{}, err
	}
	var known []string
	for _, n := range m.Networks {
		if n.Name == name {
			return n, nil
		}
		known = append(known, n.Name)
	}
	return Network{}, fmt.Errorf("unknown network %q; have: %s", name, strings.Join(known, ", "))
}
