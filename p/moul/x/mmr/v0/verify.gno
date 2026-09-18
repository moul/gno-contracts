package mmr

import (
	"encoding/hex"
	"strings"

	"gno.land/p/moul/x/merkle/v0"
)

// peakHeights returns the mountain heights of a log of total leaves, left to
// right. They are the set bits of total, high to low: 11 leaves is 8 + 2 + 1,
// so heights 3, 1, 0.
func peakHeights(total int) []int {
	var out []int
	for h := 62; h >= 0; h-- {
		if total&(1<<uint(h)) != 0 {
			out = append(out, h)
		}
	}
	return out
}

// locate returns which mountain holds the leaf at index, and the leaf's index
// within that mountain. It returns -1 when index is out of range.
func locate(total, index int) (int, int) {
	offset := 0
	for j, h := range peakHeights(total) {
		size := 1 << uint(h)
		if index < offset+size {
			return j, index - offset
		}
		offset += size
	}
	return -1, 0
}

// Verify reports whether leaf really sits at p.Index of a log that held
// p.Total leaves and whose root is root.
//
// Every dimension of the proof is checked against p.Total rather than trusted:
// the peak count, which mountain holds the leaf, the local index, the path
// length and both peak-list lengths are all recomputed. A proof that does not
// have exactly the shape p.Total implies is rejected before any hashing.
//
// Failures are false, never a panic, so a realm chooses whether a bad proof
// aborts or branches.
func Verify(root, leaf []byte, p Proof) bool {
	if len(root) != HashSize || p.Total <= 0 || p.Index < 0 || p.Index >= p.Total {
		return false
	}
	heights := peakHeights(p.Total)
	if len(heights) > MaxPeaks {
		return false
	}
	j, local := locate(p.Total, p.Index)
	if j < 0 {
		return false
	}
	if len(p.Path) != heights[j] || len(p.Before) != j || len(p.After) != len(heights)-1-j {
		return false
	}
	if !allHashes(p.Path) || !allHashes(p.Before) || !allHashes(p.After) {
		return false
	}

	node := merkle.LeafHash(leaf)
	for d, sib := range p.Path {
		if (local>>uint(d))&1 == 1 {
			node = merkle.InnerHash(sib, node)
		} else {
			node = merkle.InnerHash(node, sib)
		}
	}

	peaks := make([][]byte, 0, len(heights))
	peaks = append(peaks, p.Before...)
	peaks = append(peaks, node)
	peaks = append(peaks, p.After...)
	return equal(bag(peaks), root)
}

func allHashes(hs [][]byte) bool {
	for _, h := range hs {
		if len(h) != HashSize {
			return false
		}
	}
	return true
}

func equal(a, b []byte) bool {
	if len(a) != len(b) || len(a) == 0 {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// Hex renders the three hash lists as comma-separated hex, in the order
// path|before|after, which is what a realm call takes as arguments.
func (p Proof) Hex() (path, before, after string) {
	return joinHex(p.Path), joinHex(p.Before), joinHex(p.After)
}

func joinHex(hs [][]byte) string {
	parts := make([]string, len(hs))
	for i, h := range hs {
		parts[i] = hex.EncodeToString(h)
	}
	return strings.Join(parts, ",")
}

// ParseProof rebuilds a Proof from realm-call arguments. Each of path, before
// and after is a comma-separated hex list, possibly empty.
func ParseProof(index, total int, path, before, after string) (Proof, error) {
	ph, err := splitHex(path)
	if err != nil {
		return Proof{}, err
	}
	bh, err := splitHex(before)
	if err != nil {
		return Proof{}, err
	}
	ah, err := splitHex(after)
	if err != nil {
		return Proof{}, err
	}
	if len(bh)+len(ah)+1 > MaxPeaks {
		return Proof{}, ErrTooManyPeaks
	}
	return Proof{Index: index, Total: total, Path: ph, Before: bh, After: ah}, nil
}

func splitHex(s string) ([][]byte, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	var out [][]byte
	for _, raw := range strings.Split(s, ",") {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		b, err := hex.DecodeString(raw)
		if err != nil {
			return nil, ErrBadHex
		}
		if len(b) != HashSize {
			return nil, ErrBadSize
		}
		out = append(out, b)
	}
	return out, nil
}
