// Package commit provides small, deterministic commitment helpers shared by
// the agent demos. On-chain realms store *commitments* to off-chain data
// (reports, patches, verdicts) rather than the data itself; this package is
// the one place that defines how those commitments are computed, so several
// realms agree on the scheme.
package commit

import (
	"crypto/sha256"
	"encoding/hex"
)

// Hash returns the hex-encoded SHA-256 over its parts, length-prefixed so
// that Hash("ab","c") != Hash("a","bc"). Use it to commit to structured
// off-chain material without revealing it.
func Hash(parts ...string) string {
	var buf []byte
	for _, p := range parts {
		buf = appendUvarint(buf, uint64(len(p)))
		buf = append(buf, p...)
	}
	sum := sha256.Sum256(buf)
	return hex.EncodeToString(sum[:])
}

// Verdict is the canonical commitment used by commit-reveal voting: a hidden
// boolean plus a salt. Reveal the same (verdict, salt) later and any observer
// can recompute this and confirm the vote was not changed after the fact.
func Verdict(verdict bool, salt string) string {
	v := "no"
	if verdict {
		v = "yes"
	}
	return Hash("verdict", v, salt)
}

// Short abbreviates a hex commitment for display.
func Short(h string) string {
	if len(h) <= 12 {
		return h
	}
	return h[:6] + "…" + h[len(h)-4:]
}

func appendUvarint(buf []byte, x uint64) []byte {
	for x >= 0x80 {
		buf = append(buf, byte(x)|0x80)
		x >>= 7
	}
	return append(buf, byte(x))
}
