// Package bloomfilter ports the classic Bloom filter data structure to
// gno.land: a fixed-size bit array plus k independent hash functions that
// let you test set membership with zero false negatives and a small, bounded
// false-positive rate — without ever storing the actual items.
//
// Membership is checked via double hashing (Kirsch–Mitzenmacher): two base
// hashes h1, h2 are combined as h1 + i*h2 to derive k bit positions per item,
// avoiding the cost of k independent hash functions.
//
// Add is a crossing function per the gno 0.9 interrealm convention (it takes
// `cur realm` as its first parameter); MightContain and Stats are read-only.
package bloomfilter

import (
	"chain"
	"strconv"
	"strings"
)

const (
	numBits    = 2048 // m: total bits in the filter
	numBytes   = numBits / 8
	numHashes  = 5 // k: hash functions per item (double-hashed from 2 bases)
	maxHistory = 20 // most recent additions kept for Render display only
)

var (
	bits    [numBytes]byte // the bit array itself
	setBits int            // running count of bits currently set to 1
	added   int            // total Add calls (may double-count re-adds)
	history []string       // last few added items, for the Render view
)

// fnv1a is a minimal FNV-1a 32-bit hash over a string, parameterized by an
// offset basis so two calls with different seeds behave as independent
// hash functions for the double-hashing scheme below.
func fnv1a(s string, seed uint32) uint32 {
	h := seed
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619 // FNV prime
	}
	return h
}

// positions returns the k bit positions an item hashes to.
func positions(item string) [numHashes]uint32 {
	h1 := fnv1a(item, 2166136261)
	h2 := fnv1a(item, 84696351)
	if h2 == 0 {
		h2 = 1 // keep the second hash non-degenerate
	}
	var pos [numHashes]uint32
	for i := 0; i < numHashes; i++ {
		pos[i] = (h1 + uint32(i)*h2) % numBits
	}
	return pos
}

// setBit sets bit `pos` and reports whether it was previously unset.
func setBit(pos uint32) bool {
	byteIdx := pos / 8
	mask := byte(1 << (pos % 8))
	if bits[byteIdx]&mask != 0 {
		return false
	}
	bits[byteIdx] |= mask
	return true
}

// testBit reports whether bit `pos` is set.
func testBit(pos uint32) bool {
	byteIdx := pos / 8
	mask := byte(1 << (pos % 8))
	return bits[byteIdx]&mask != 0
}

// Add inserts `item` into the filter. Crossing function: any caller (user or
// realm) may add, matching this demo's open-membership model.
func Add(cur realm, item string) {
	if item == "" {
		panic("bloomfilter: empty item")
	}
	for _, pos := range positions(item) {
		if setBit(pos) {
			setBits++
		}
	}
	added++
	history = append(history, item)
	if len(history) > maxHistory {
		history = history[len(history)-maxHistory:]
	}
	chain.Emit("Add", "item", item, "totalAdded", strconv.Itoa(added))
}

// MightContain reports whether `item` was possibly added before. A false
// (definitely-not-a-member) answer is always correct; a true answer can
// occasionally be a false positive, never a false negative.
func MightContain(item string) bool {
	if item == "" {
		return false
	}
	for _, pos := range positions(item) {
		if !testBit(pos) {
			return false
		}
	}
	return true
}

// FalsePositiveRatePercent estimates the current false-positive rate, in
// percent, as (bitsSet/m)^k — the standard Bloom filter approximation once
// bits are randomly distributed. Computed with plain integer/float math to
// avoid depending on math.Exp/Pow availability.
func FalsePositiveRatePercent() float64 {
	fillRatio := float64(setBits) / float64(numBits)
	rate := 1.0
	for i := 0; i < numHashes; i++ {
		rate *= fillRatio
	}
	return rate * 100
}

// Stats returns the raw counters backing the Render view and
// FalsePositiveRatePercent: (itemsAdded, bitsSet, totalBits, hashCount).
func Stats() (int, int, int, int) {
	return added, setBits, numBits, numHashes
}

// Render draws the filter's current stats and recently-added items as
// Markdown for gnoweb.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Bloom Filter\n\n")
	b.WriteString("A probabilistic set membership test: `Add` an item, then " +
		"`MightContain` it back. False positives are possible; false " +
		"negatives never happen. The filter never stores the items " +
		"themselves — only " + strconv.Itoa(numBits) + " bits.\n\n")

	fillRatio := float64(setBits) / float64(numBits) * 100

	b.WriteString("## Stats\n\n")
	b.WriteString("- **Bits (m):** " + strconv.Itoa(numBits) + "\n")
	b.WriteString("- **Hash functions (k):** " + strconv.Itoa(numHashes) + "\n")
	b.WriteString("- **Items added:** " + strconv.Itoa(added) + "\n")
	b.WriteString("- **Bits set:** " + strconv.Itoa(setBits) + " (" +
		strconv.FormatFloat(fillRatio, 'f', 1, 64) + "% full)\n")
	b.WriteString("- **Estimated false-positive rate:** " +
		strconv.FormatFloat(FalsePositiveRatePercent(), 'f', 3, 64) + "%\n\n")

	b.WriteString("## Recently added\n\n")
	if len(history) == 0 {
		b.WriteString("_Nothing added yet — call `Add` with an item string._\n")
		return b.String()
	}
	for i := len(history) - 1; i >= 0; i-- {
		b.WriteString("- `" + history[i] + "`\n")
	}

	return b.String()
}
