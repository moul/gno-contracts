package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// Signing and broadcasting, instead of printing two commands to paste.
//
// The rest of this tool deliberately emits commands rather than running them,
// and that is still the default. What -run removes is not the review step but
// the PASTE step, and the paste is where this particular flow goes wrong: the
// signature covers the account sequence, so a document is valid only until the
// key signs anything else, and the window between reading the commands and
// running them is exactly the window in which that happens. Copying two long
// lines out of a terminal is also how the wrong document gets broadcast, since
// gnokey broadcast does not check locally that a document was signed at all.
//
// gnohome still holds no key. gnokey does, and it prompts for the passphrase
// exactly as it would if the command had been typed by hand, which is why the
// child process inherits stdin rather than being fed from a pipe: a pipe takes
// stdin away and the prompt fails with "inappropriate ioctl for device".

// execCommand runs one command with the terminal attached. It is a variable so
// a test can record what would have run without a gnokey on PATH, and without
// a chain to broadcast at.
var execCommand = func(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s %s: %w", name, args[0], err)
	}
	return nil
}

// signAndBroadcast runs the two steps in order, stopping at the first failure.
//
// Sequential and gated, for the reason printBatch gives for chaining its
// printed commands with &&: broadcasting a document that was not signed is not
// refused locally, it is sent and rejected by the ante handler as "no signers",
// which turns a mistake visible on disk into a confusing round trip.
func signAndBroadcast(out *os.File, cfg config, path string, acct account) error {
	fmt.Fprintf(out, "#\n# signing as %s (account %s, sequence %s)\n", cfg.key, acct.Number, acct.Sequence)
	if err := execCommand("gnokey", "sign",
		"-tx-path", path,
		"-chainid", cfg.chainID,
		"-account-number", acct.Number,
		"-account-sequence", acct.Sequence,
		cfg.key,
	); err != nil {
		return err
	}
	fmt.Fprintf(out, "# broadcasting to %s\n", cfg.remote)
	return execCommand("gnokey", "broadcast", "-remote", cfg.remote, path)
}

// defaultBatchPath is where -run writes when no -batch was named.
//
// Keyed by chain id so a staging run and a mainnet run cannot overwrite each
// other's document: they carry different sequences and broadcasting the wrong
// one is a rejection at best.
func defaultBatchPath(cfg config) string {
	return filepath.Join(os.TempDir(), "gnohome-"+cfg.chainID+".tx.json")
}
