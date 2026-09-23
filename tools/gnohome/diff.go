package main

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

const (
	kindMissing  = "missing"  // local file, nothing on chain
	kindOutdated = "outdated" // both exist, bodies differ
	kindExtra    = "extra"    // on chain, no local file
	kindSame     = "same"     // in sync
)

type change struct {
	kind   string
	slug   string
	detail string
	slot   slotFile // zero for kindExtra
}

// diff compares the local slots against a manifest. Only changes are returned;
// a slot that matches is dropped, so an empty result means "up to date".
func diff(local []slotFile, remote map[string]remoteSlot) []change {
	var out []change
	seen := map[string]bool{}

	for _, s := range local {
		seen[s.slug] = true
		r, ok := remote[s.slug]
		switch {
		case !ok:
			out = append(out, change{kind: kindMissing, slug: s.slug, slot: s,
				detail: fmt.Sprintf("%d bytes, not on chain", len(s.body))})
		case r.hash != s.hash:
			out = append(out, change{kind: kindOutdated, slug: s.slug, slot: s,
				detail: fmt.Sprintf("local %s (%d B) vs chain %s (%d B), chain rev %d",
					short(s.hash), len(s.body), short(r.hash), r.size, r.rev)})
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
		out = append(out, change{kind: kindExtra, slug: slug,
			detail: fmt.Sprintf("%d bytes on chain, no local file (use -prune to emit Delete)", r.size)})
	}
	return out
}

// allChanges treats every local slot as needing a push. It is what -all uses,
// and what a redeploy needs: a private redeploy re-runs init() and clears the
// tree, so every slot has to go back up without consulting the chain.
func allChanges(local []slotFile) []change {
	out := make([]change, 0, len(local))
	for _, s := range local {
		out = append(out, change{kind: kindMissing, slug: s.slug, slot: s,
			detail: fmt.Sprintf("%d bytes", len(s.body))})
	}
	return out
}

// emittable drops the changes that must not become a message.
//
// A slot on chain with no local file is only ever deleted when -prune asks for
// it, because the ordinary reason for one is that the file is being held back
// deliberately, not that the slot is garbage. Both emitters go through here:
// they disagreed once, printTx skipping the extra slot while buildBatch turned
// it into a Delete, and the batch path is the one the README recommends.
func emittable(changes []change, prune bool) []change {
	out := make([]change, 0, len(changes))
	for _, c := range changes {
		if c.kind == kindSame {
			continue
		}
		if c.kind == kindExtra && !prune {
			continue
		}
		out = append(out, c)
	}
	return out
}

// catCmd is spelled absolutely on purpose; see command().
const catCmd = "/bin/cat"

type txOptions struct {
	inline     bool
	prune      bool
	gasWanted  int64
	gasFee     string
	maxDeposit string
}

// feeRatioMicro is the fee offered per unit of gas, in millionths of a ugnot:
// 10_000 = 0.01 ugnot/gas. What the mempool enforces is the fee/gas_wanted
// RATIO, not the absolute (EnsureSufficientMempoolFees), so raising the
// ceiling raises the required fee. The lowest ratio accepted on gno.land
// mainnet is 0.001 ugnot/gas, so this is ten times the floor. gas_fee is
// deducted in full as offered and never refunded, unlike max_deposit, so
// over-offering is a real cost: the flat 1000000ugnot this tool used to emit
// was about ninety times the floor on a slot write.
//
// Kept in step with gnopm's FeeFor, which sizes a deploy the same way.
const feeRatioMicro = 10_000

// feeFor sizes the gas fee from the ceiling it accompanies, never zero.
func feeFor(gasWanted int64) string {
	fee := gasWanted * feeRatioMicro / 1_000_000
	if fee < 1 {
		fee = 1
	}
	return strconv.FormatInt(fee, 10) + "ugnot"
}

// gasFor sizes gas-wanted from the body. The floor covers the call itself; the
// per-byte term covers writing the body into the realm's tree. Generous on
// purpose: unused gas is not charged, a too-low estimate costs a failed
// transaction. Override with -gas-wanted.
func gasFor(bodyLen int) int64 {
	// Measured, not guessed. The five-slot batch broadcast at height 221309
	// (tx LUriTCSqzEamFR4lPZqvxw32uaac7y6y38Vzp8eQuhk=) used 6,133,836 gas
	// for 3,204 bytes of body across five Set calls: ~1.23M per call. The
	// previous floor of 10M per call over-estimated that batch by 9.2x.
	//
	// Over-estimating is not free, which is why this was worth fixing: the
	// mempool enforces the fee/gas_wanted RATIO, so a ceiling nine times too
	// high makes the fee nine times too high, and gas_fee is deducted in full
	// and never refunded. That batch paid 564,080ugnot where ~173,060 would
	// have done.
	//
	// Still ~2.8x the measured usage, deliberately: one sample is one sample,
	// and running out of gas loses the whole fee and gets nothing, so the
	// asymmetry favours headroom. A Set is not a code-bearing message, so
	// .app/simulate can size it exactly without a signature; doing that
	// instead of estimating is the real fix.
	const (
		floor   = 2_500_000
		perByte = 1_500
	)
	g := int64(floor) + int64(bodyLen)*perByte
	return g
}

// command renders one gnokey invocation. It is printed, never run: this tool
// does not hold a key and does not broadcast.
func command(cfg config, c change, opt txOptions) string {
	fn := "Set"
	args := []string{shellQuote(c.slug)}
	switch {
	case c.kind == kindExtra:
		fn = "Delete"
	case opt.inline:
		args = append(args, shellQuote(c.slot.body))
	default:
		// The body is read at paste time, from the absolute path, so a long
		// markdown file does not have to be inlined into the terminal.
		// normalize() strips the trailing newline that command substitution
		// would eat, so what lands on chain hashes to what status compared.
		//
		// /bin/cat, not cat: a shadowed or broken `cat` on PATH would make the
		// substitution expand to nothing, and the command would then silently
		// set the slot to the empty string instead of failing.
		args = append(args, `"$(`+catCmd+` `+shellQuote(c.slot.path)+`)"`)
	}

	gas := opt.gasWanted
	if gas == 0 {
		gas = gasFor(len(c.slot.body))
	}

	var b strings.Builder
	fmt.Fprintf(&b, "# %s: %s\n", c.slug, c.detail)
	b.WriteString("gnokey maketx call \\\n")
	b.WriteString("  -pkgpath " + cfg.realm + " \\\n")
	b.WriteString("  -func " + fn + " \\\n")
	for _, a := range args {
		b.WriteString("  -args " + a + " \\\n")
	}
	// The fee tracks the ceiling, because the mempool enforces the
	// fee/gas_wanted RATIO and not the absolute (EnsureSufficientMempoolFees).
	// An explicit -gas-fee still wins. The flat 1000000ugnot this used to
	// default to was ~92x the accepted floor on a slot write, and gas_fee is
	// deducted in full and never refunded.
	fee := opt.gasFee
	if fee == "" {
		fee = feeFor(gas)
	}
	b.WriteString("  -gas-fee " + fee + " \\\n")
	b.WriteString("  -gas-wanted " + strconv.FormatInt(gas, 10) + " \\\n")
	if opt.maxDeposit != "" {
		b.WriteString("  -max-deposit " + opt.maxDeposit + " \\\n")
	}
	b.WriteString("  -broadcast \\\n")
	b.WriteString("  -chainid " + cfg.chainID + " \\\n")
	b.WriteString("  -remote " + cfg.remote + " \\\n")
	b.WriteString("  " + cfg.key + "\n")
	return b.String()
}

// short abbreviates a hash for display without assuming its length: the chain
// side of a comparison is whatever the manifest said, and a truncated field
// must not take the tool down.
func short(h string) string {
	const n = 12
	if len(h) <= n {
		return h
	}
	return h[:n]
}

// shellQuote wraps s for /bin/sh. Single quotes take everything literally,
// including the newlines a markdown body is full of; the only byte that needs
// help is the single quote itself.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
