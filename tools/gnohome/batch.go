package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// One transaction, one signature, N slots.
//
// `tx` emits one gnokey command per outdated slot, which means one passphrase
// prompt per slot and, worse, no atomicity: a failure halfway leaves the page
// assembled from a mix of old and new slots, and the layout referring to a
// placeholder that was never written.
//
// A tm2 transaction carries a LIST of messages (std.Tx.Msgs), and `gnokey
// sign` signs the document rather than the message, so the whole update can be
// one signature. Verified end to end before this was written: two m_call
// messages merged into one document, signed once, one signature recorded.
//
// It also removes the `"$(/bin/cat …)"` dance entirely. In a document the body
// is a literal JSON string, so there is no shell to quote for, no command
// substitution eating the trailing newline, and no ARG_MAX ceiling on how
// large a slot can be.

// txDoc is the amino JSON shape gnokey reads with -tx-path. Only the fields a
// document needs before signing are modelled; gnokey fills in signatures.
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
// what `gnokey maketx call -broadcast=false` emits, because that output is the
// reference this was built against.
type callMsg struct {
	Type       string   `json:"@type"`
	Caller     string   `json:"caller"`
	Send       string   `json:"send"`
	MaxDeposit string   `json:"max_deposit"`
	PkgPath    string   `json:"pkg_path"`
	Func       string   `json:"func"`
	Args       []string `json:"args"`
}

// account is the slice of auth/accounts/<addr> that signing depends on.
type account struct {
	Number   string
	Sequence string
}

// fetchAccount reads the account number and sequence the signature will be
// bound to. GetSignBytes mixes chain id, account number and sequence into the
// bytes being signed, so all three are part of the signature: if the account
// signs anything else before this document is broadcast, the sequence moves
// and the signature is void.
func fetchAccount(remote, addr string) (account, error) {
	raw, err := abciQuery(remote, "auth/accounts/"+addr, "")
	if err != nil {
		return account{}, fmt.Errorf("reading %s: %w", addr, err)
	}
	var out struct {
		BaseAccount struct {
			AccountNumber string `json:"account_number"`
			Sequence      string `json:"sequence"`
		} `json:"BaseAccount"`
	}
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return account{}, fmt.Errorf("decoding the account: %w", err)
	}
	if out.BaseAccount.AccountNumber == "" {
		return account{}, fmt.Errorf("%s has no account on chain yet; it must be funded before it can sign", addr)
	}
	return account{Number: out.BaseAccount.AccountNumber, Sequence: out.BaseAccount.Sequence}, nil
}

// buildBatch turns the outstanding changes into one unsigned document.
func buildBatch(cfg config, changes []change, opt txOptions) (*txDoc, int64, error) {
	if len(changes) == 0 {
		return nil, 0, nil
	}
	doc := &txDoc{Memo: ""}
	var gas int64
	for _, c := range changes {
		m := callMsg{
			Type:       "/vm.m_call",
			Caller:     cfg.owner,
			Send:       "",
			MaxDeposit: opt.maxDeposit,
			PkgPath:    cfg.realm,
			Func:       "Set",
			Args:       []string{c.slug},
		}
		if c.kind == kindExtra {
			m.Func = "Delete"
		} else {
			// The body goes in verbatim. normalize() already made it what the
			// realm will hash, and unlike the shell path nothing downstream
			// will trim it.
			m.Args = append(m.Args, c.slot.body)
		}
		b, err := json.Marshal(m)
		if err != nil {
			return nil, 0, err
		}
		doc.Msg = append(doc.Msg, b)

		if opt.gasWanted != 0 {
			gas += opt.gasWanted
		} else {
			gas += gasFor(len(c.slot.body))
		}
	}
	fee := opt.gasFee
	if fee == "" {
		fee = feeFor(gas)
	}
	doc.Fee = txFee{GasWanted: strconv.FormatInt(gas, 10), GasFee: fee}
	return doc, gas, nil
}

// printBatch writes the document and the two commands that act on it.
func printBatch(out *os.File, cfg config, changes []change, opt txOptions, path string) error {
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
	fmt.Fprintf(out, "# wrote %s: %d message(s) in one transaction (%s)\n",
		path, len(doc.Msg), strings.Join(slugs, ", "))
	fmt.Fprintf(out, "# gas %d, fee %s, one signature instead of %d\n#\n", gas, doc.Fee.GasFee, len(doc.Msg))
	fmt.Fprintf(out, "# The signature is bound to chain-id, account-number and sequence, so\n"+
		"# broadcast it before %s signs anything else or it is void.\n", cfg.key)
	fmt.Fprintf(out, "gnokey sign -tx-path %s \\\n"+
		"  -chainid %s -account-number %s -account-sequence %s \\\n  %s\n",
		shellQuote(path), cfg.chainID, acct.Number, acct.Sequence, cfg.key)
	fmt.Fprintf(out, "gnokey broadcast -remote %s %s\n", cfg.remote, shellQuote(path))
	return nil
}
