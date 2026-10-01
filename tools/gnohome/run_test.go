package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// recordExec swaps the real runner for one that records, so the order and the
// arguments can be asserted without a gnokey on PATH and without a chain to
// broadcast at. Restored by t.Cleanup so one test cannot leak into the next.
func recordExec(t *testing.T, fail string) *[][]string {
	t.Helper()
	var got [][]string
	prev := execCommand
	execCommand = func(name string, args ...string) error {
		got = append(got, append([]string{name}, args...))
		if fail != "" && len(args) > 0 && args[0] == fail {
			return os.ErrPermission
		}
		return nil
	}
	t.Cleanup(func() { execCommand = prev })
	return &got
}

// TestSignAndBroadcastRunsInOrderWithTheSignatureFields.
//
// The account number and sequence are covered by the signature, so passing the
// wrong ones produces a document the chain rejects for a reason that names
// neither. They are asserted here because nothing downstream can catch it: the
// failure surfaces as "unauthorized" from the ante handler, after the round
// trip.
func TestSignAndBroadcastRunsInOrderWithTheSignatureFields(t *testing.T) {
	got := recordExec(t, "")
	cfg := config{key: "moul", chainID: "gnoland-1", remote: "https://rpc.example:443"}

	err := signAndBroadcast(os.Stdout, cfg, "/tmp/x.tx.json", account{Number: "3096238", Sequence: "334"})
	if err != nil {
		t.Fatal(err)
	}
	if len(*got) != 2 {
		t.Fatalf("ran %d command(s), want sign then broadcast: %v", len(*got), *got)
	}
	sign, broadcast := (*got)[0], (*got)[1]
	if sign[0] != "gnokey" || sign[1] != "sign" {
		t.Errorf("first command = %v, want gnokey sign", sign)
	}
	joined := strings.Join(sign, " ")
	for _, want := range []string{
		"-tx-path /tmp/x.tx.json",
		"-chainid gnoland-1",
		"-account-number 3096238",
		"-account-sequence 334",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("sign is missing %q: %v", want, sign)
		}
	}
	if sign[len(sign)-1] != "moul" {
		t.Errorf("sign does not end with the key name: %v", sign)
	}
	if broadcast[1] != "broadcast" || broadcast[len(broadcast)-1] != "/tmp/x.tx.json" {
		t.Errorf("second command = %v, want gnokey broadcast of the same document", broadcast)
	}
}

// TestSignAndBroadcastStopsAtAFailedSign is the one ordering property that
// matters. `gnokey broadcast` does NOT refuse an unsigned document locally: it
// sends it and lets the ante handler reject it as "no signers". So a runner
// that broadcast regardless of the sign result would turn a local failure, such
// as a mistyped passphrase, into a pointless round trip and a confusing error
// naming neither cause.
func TestSignAndBroadcastStopsAtAFailedSign(t *testing.T) {
	got := recordExec(t, "sign")
	cfg := config{key: "moul", chainID: "gnoland-1", remote: "https://rpc.example:443"}

	if err := signAndBroadcast(os.Stdout, cfg, "/tmp/x.tx.json", account{Number: "1", Sequence: "2"}); err == nil {
		t.Fatal("a failed sign returned no error")
	}
	if len(*got) != 1 {
		t.Fatalf("ran %d command(s) after sign failed, want only the sign: %v", len(*got), *got)
	}
}

// TestDefaultBatchPathIsPerChain. A staging document and a mainnet document
// carry different sequences, and broadcasting one where the other was meant is
// a rejection at best. Sharing one path would make that a matter of which
// command ran last.
func TestDefaultBatchPathIsPerChain(t *testing.T) {
	main := defaultBatchPath(config{chainID: "gnoland-1"})
	staging := defaultBatchPath(config{chainID: "staging"})
	if main == staging {
		t.Fatalf("both chains write to %s", main)
	}
	// filepath.Clean on both sides, because os.TempDir() returns $TMPDIR as the
	// OS set it and macOS sets it WITH a trailing slash
	// (/var/folders/.../T/), while filepath.Dir never returns one. Comparing
	// them raw passes on Linux, where TMPDIR is usually unset and os.TempDir()
	// is a bare /tmp, and fails on every Mac. CI is Linux, so the whole local
	// suite was red for anyone on a Mac and green in the one place anybody
	// looked.
	if filepath.Clean(filepath.Dir(main)) != filepath.Clean(os.TempDir()) {
		t.Errorf("default path %s is not under the temp dir %s; a repo-relative default would litter the checkout",
			main, os.TempDir())
	}
	if !strings.HasSuffix(main, ".json") {
		t.Errorf("default path %s does not end in .json, and the .sh is derived by swapping that suffix", main)
	}
}
