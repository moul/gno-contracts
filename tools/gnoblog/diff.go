package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
)

const (
	kindMissing  = "missing"  // local file, nothing on chain
	kindOutdated = "outdated" // both exist, they differ
	kindExtra    = "extra"    // on chain, no local file
)

type change struct {
	kind   string
	slug   string
	detail string
	post   postFile // zero for kindExtra
}

// diff compares the local posts against a manifest. Only changes are returned,
// so an empty result means "up to date".
func diff(local []postFile, remote map[string]remotePost) []change {
	var out []change
	seen := map[string]bool{}

	for _, p := range local {
		seen[p.slug] = true
		r, ok := remote[p.slug]
		switch {
		case !ok:
			out = append(out, change{kind: kindMissing, slug: p.slug, post: p,
				detail: fmt.Sprintf("%d bytes, not on chain", len(p.body))})
		case r.hash != p.hash:
			out = append(out, change{kind: kindOutdated, slug: p.slug, post: p,
				detail: fmt.Sprintf("local %s (%d B) vs chain %s (%d B), chain rev %d",
					short(p.hash), len(p.body), short(r.hash), r.size, r.rev)})
		}
	}

	extras := make([]string, 0, len(remote))
	for slug := range remote {
		if !seen[slug] {
			extras = append(extras, slug)
		}
	}
	sort.Strings(extras)
	for _, slug := range extras {
		r := remote[slug]
		// The intro row always exists on chain, empty on a fresh realm. An
		// absent intro.md means "leave it alone", not "delete it", and there
		// is no Delete for it anyway.
		if slug == introKey {
			continue
		}
		out = append(out, change{kind: kindExtra, slug: slug,
			detail: fmt.Sprintf("%d bytes on chain, no local file (use -prune to emit Delete)", r.size)})
	}
	return out
}

// allChanges treats every local post as needing a push. It is what -all uses,
// and what a redeploy needs: a private realm redeploy re-runs init() and
// clears the trees, so every post has to go back up without consulting a
// chain that now reports nothing.
func allChanges(local []postFile) []change {
	out := make([]change, 0, len(local))
	for _, p := range local {
		out = append(out, change{kind: kindMissing, slug: p.slug, post: p,
			detail: fmt.Sprintf("%d bytes", len(p.body))})
	}
	return out
}

type txOptions struct {
	prune      bool
	print      bool
	gasWanted  int64
	gasFee     string
	maxDeposit string
}

// feeRatioMicro is the fee offered per unit of gas, in millionths of a ugnot:
// 10_000 = 0.01 ugnot/gas. The mempool enforces the fee/gas_wanted RATIO and
// not the absolute (EnsureSufficientMempoolFees), so raising the ceiling
// raises the required fee. The lowest ratio accepted on gno.land mainnet is
// 0.001 ugnot/gas, so this is ten times the floor. gas_fee is deducted in full
// as offered and never refunded, unlike max_deposit, so over-offering is a
// real cost rather than a harmless safety margin.
//
// Kept in step with tools/gnohome and with gnopm's FeeFor.
const feeRatioMicro = 10_000

func feeFor(gasWanted int64) string {
	fee := gasWanted * feeRatioMicro / 1_000_000
	if fee < 1 {
		fee = 1
	}
	return strconv.FormatInt(fee, 10) + "ugnot"
}

// gasFor sizes gas-wanted from the body length. The constants are gnohome's,
// measured on a five-message batch of slot writes at mainnet height 221309
// (~1.23M gas per call, 3,204 bytes of body): a blog Set writes into the same
// kind of avl tree with three more short string arguments, so the shape of the
// cost is the same and the floor absorbs the difference.
//
// Still roughly 2.8x the measured usage, deliberately: running out of gas
// loses the whole fee and gets nothing, so the asymmetry favours headroom.
// Sizing it exactly means .app/simulate, which a Set can use because it is not
// a code-bearing message; doing that instead of estimating is the real fix.
func gasFor(bodyLen int) int64 {
	const (
		floor   = 2_500_000
		perByte = 1_500
	)
	return int64(floor) + int64(bodyLen)*perByte
}

// One transaction, one signature, N posts.
//
// A post body is measured in kilobytes, which is what rules out the shell
// path gnohome also offers: `-args "$(cat file)"` has to quote for /bin/sh,
// loses the trailing newline to command substitution, and runs into ARG_MAX.
// In a tm2 transaction document the body is a literal JSON string, so there is
// no shell in the loop at all.
//
// A tm2 transaction carries a LIST of messages (std.Tx.Msgs) and `gnokey sign`
// signs the document rather than the message, so publishing three posts is one
// passphrase prompt and one atomic broadcast.
type txDoc struct {
	Msg        []json.RawMessage `json:"msg"`
	Fee        txFee             `json:"fee"`
	Signatures any               `json:"signatures"`
	Memo       string            `json:"memo"`
}

type txFee struct {
	GasWanted string `json:"gas_wanted"`
	GasFee    string `json:"gas_fee"`
}

// callMsg is one /vm.m_call message. The field names and their order match
// what `gnokey maketx call -broadcast=false` emits.
type callMsg struct {
	Type       string   `json:"@type"`
	Caller     string   `json:"caller"`
	Send       string   `json:"send"`
	MaxDeposit string   `json:"max_deposit"`
	PkgPath    string   `json:"pkg_path"`
	Func       string   `json:"func"`
	Args       []string `json:"args"`
}

// msgFor turns one change into the call that fixes it.
func msgFor(cfg config, c change, opt txOptions) callMsg {
	m := callMsg{
		Type:       "/vm.m_call",
		Caller:     cfg.owner,
		Send:       "",
		MaxDeposit: opt.maxDeposit,
		PkgPath:    cfg.realm,
		Func:       "Set",
		Args:       []string{c.slug},
	}
	switch {
	case c.kind == kindExtra:
		m.Func = "Delete"
	case c.post.isIntro():
		m.Func = "SetIntro"
		m.Args = []string{c.post.body}
	default:
		m.Args = []string{c.slug, c.post.title, c.post.date, c.post.tags, c.post.body}
	}
	return m
}

// buildBatch turns the outstanding changes into one unsigned document.
func buildBatch(cfg config, changes []change, opt txOptions) (*txDoc, int64, error) {
	if len(changes) == 0 {
		return nil, 0, nil
	}
	doc := &txDoc{}
	var gas int64
	for _, c := range changes {
		b, err := json.Marshal(msgFor(cfg, c, opt))
		if err != nil {
			return nil, 0, err
		}
		doc.Msg = append(doc.Msg, b)
		if opt.gasWanted != 0 {
			gas += opt.gasWanted
		} else {
			gas += gasFor(len(c.post.body))
		}
	}
	fee := opt.gasFee
	if fee == "" {
		fee = feeFor(gas)
	}
	doc.Fee = txFee{GasWanted: strconv.FormatInt(gas, 10), GasFee: fee}
	return doc, gas, nil
}

// publishBatch writes the document and then signs and broadcasts it, unless
// opt.print says to write the two commands out instead.
//
// Running by default is the same call gnopm makes, for the same reason: the
// copy-paste in the middle protected nothing and cost something real. A
// document's signature covers the account sequence, so the gap between reading
// the command and pasting it is a window in which anything else this key signs
// voids it. Closing that gap is the point.
//
// This tool still holds no key and signs nothing. gnokey does, with the
// terminal attached, prompting for a passphrase this process never sees.
func publishBatch(out *os.File, cfg config, changes []change, opt txOptions, path string) error {
	doc, gas, err := buildBatch(cfg, changes, opt)
	if err != nil {
		return err
	}
	if doc == nil {
		fmt.Fprintln(out, "# everything is up to date; nothing to sign")
		return nil
	}
	acct, err := fetchAccount(cfg.remote, cfg.owner)
	if err != nil {
		return err
	}

	body, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, append(body, '\n'), 0o644); err != nil {
		return err
	}

	var slugs []string
	for _, c := range changes {
		slugs = append(slugs, c.slug)
	}
	fmt.Fprintf(os.Stderr, "wrote %s: %d message(s) in one transaction (%s)\n",
		path, len(doc.Msg), strings.Join(slugs, ", "))
	fmt.Fprintf(os.Stderr, "gas %d, fee %s, one signature instead of %d\n", gas, doc.Fee.GasFee, len(doc.Msg))
	fmt.Fprintf(os.Stderr, "the signature covers chain-id, account-number and sequence, so it is\n"+
		"void the moment %s signs anything else.\n", cfg.key)

	// Sign then broadcast, in that order and never the reverse: `gnokey
	// broadcast` does not refuse an unsigned document locally, it sends it and
	// lets the ante handler reject it with "no signers", which is a confusing
	// round trip to the chain for a mistake visible on disk.
	cmds := []clientCmd{
		{
			what: "sign " + path,
			name: "gnokey",
			args: []string{
				"sign",
				"-tx-path", path,
				"-chainid", cfg.chainID,
				"-account-number", acct.Number,
				"-account-sequence", acct.Sequence,
				cfg.key,
			},
		},
		{
			what: "broadcast " + path,
			name: "gnokey",
			args: []string{"broadcast", "-remote", cfg.remote, path},
		},
	}

	if opt.print {
		fmt.Fprintf(out, "#!/bin/sh\n# generated by gnoblog tx -print; review, then run this file.\n")
		fmt.Fprintf(out, "# Do NOT pipe it into sh: that takes stdin away and gnokey cannot prompt.\nset -e\n")
		for _, c := range cmds {
			fmt.Fprintf(out, "\n%s %s\n", c.name, strings.Join(quoteAll(c.args), " "))
		}
		return nil
	}

	fmt.Fprintf(os.Stderr, "\npublishing %d post(s), one gnokey prompt.\n", len(doc.Msg))
	fmt.Fprintf(os.Stderr, "-print writes the commands out instead of running them.\n")
	return runClient(cmds)
}

// clientCmd is one gnokey invocation: what it is for, and how to run it.
type clientCmd struct {
	what string
	name string
	args []string
}

// startClient is the seam a test replaces. Nothing else should.
var startClient = func(name string, args []string) error {
	cmd := exec.Command(name, args...)
	// The terminal, not a pipe: gnokey prompts for the passphrase on stdin.
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}

// runClient runs each command in order, stopping at the first failure.
// Broadcasting a document that was not signed is not a recoverable state worth
// reaching, so the sign has to succeed before the broadcast is attempted.
func runClient(cmds []clientCmd) error {
	for i, c := range cmds {
		fmt.Fprintf(os.Stderr, "\nrun [%d/%d] %s\n", i+1, len(cmds), c.what)
		fmt.Fprintf(os.Stderr, "    %s %s\n", c.name, strings.Join(quoteAll(c.args), " "))
		if err := startClient(c.name, c.args); err != nil {
			return fmt.Errorf("%s failed at step %d of %d (%s): %w", c.name, i+1, len(cmds), c.what, err)
		}
	}
	fmt.Fprintf(os.Stderr, "\ndone: %d command(s) reported success\n", len(cmds))
	return nil
}

// quoteAll quotes only what a shell would otherwise reinterpret, so the
// printed script stays readable.
func quoteAll(args []string) []string {
	out := make([]string, len(args))
	for i, a := range args {
		if a == "" {
			out[i] = "''"
		} else if strings.ContainsAny(a, " \t\n'\"\\$`&|;<>()*?[]{}#~!") {
			out[i] = shellQuote(a)
		} else {
			out[i] = a
		}
	}
	return out
}

// fetchAccount reads the account number and sequence the signature binds to.
// GetSignBytes mixes chain id, account number and sequence into the bytes
// being signed, so if the account signs anything else before this document is
// broadcast, the sequence moves and the signature is void.
func fetchAccount(remote, addr string) (acct, error) {
	raw, err := abciQuery(remote, "auth/accounts/"+addr, "")
	if err != nil {
		return acct{}, fmt.Errorf("reading %s: %w", addr, err)
	}
	var out struct {
		BaseAccount struct {
			AccountNumber string `json:"account_number"`
			Sequence      string `json:"sequence"`
		} `json:"BaseAccount"`
	}
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return acct{}, fmt.Errorf("decoding the account: %w", err)
	}
	if out.BaseAccount.AccountNumber == "" {
		return acct{}, fmt.Errorf("%s has no account on chain yet; it must be funded before it can sign", addr)
	}
	return acct{Number: out.BaseAccount.AccountNumber, Sequence: out.BaseAccount.Sequence}, nil
}

type acct struct {
	Number   string
	Sequence string
}

// short abbreviates a hash for display without assuming its length: the chain
// side is whatever the manifest said, and a truncated field must not take the
// tool down.
func short(h string) string {
	const n = 12
	if len(h) <= n {
		return h
	}
	return h[:n]
}

// shellQuote wraps s for /bin/sh. Single quotes take everything literally; the
// only byte that needs help is the single quote itself.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
