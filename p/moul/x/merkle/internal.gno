package merkle

import "crypto/sha256"

// encodeSlices renders items in the wire shape crypto/merkle.HashFromByteSlices
// expects: a 4-byte big-endian count, then per item a 4-byte big-endian length
// followed by its bytes. The native side decodes this back into [][]byte; gno
// cannot hand a slice of slices to a native directly.
func encodeSlices(items [][]byte) []byte {
	n := 0
	for _, it := range items {
		n += 4 + len(it)
	}
	out := make([]byte, 0, 4+n)
	out = appendBE32(out, len(items))
	for _, it := range items {
		out = appendBE32(out, len(it))
		out = append(out, it...)
	}
	return out
}

func appendBE32(dst []byte, n int) []byte {
	return append(dst, byte(n>>24), byte(n>>16), byte(n>>8), byte(n))
}

// hashSortedPair is the commutative node hash: SHA256 over the two children in
// ascending byte order, so a proof needs no left/right flag. Used only by
// VerifySorted.
func hashSortedPair(a, b []byte) []byte {
	d := make([]byte, 0, len(a)+len(b))
	if less(a, b) {
		d = append(append(d, a...), b...)
	} else {
		d = append(append(d, b...), a...)
	}
	h := sha256.Sum256(d)
	return h[:]
}

// less reports a < b in lexicographic byte order. gno's bytes package is
// available, but keeping the comparison here keeps this package import-light.
func less(a, b []byte) bool {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	for i := 0; i < n; i++ {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return len(a) < len(b)
}

func equal(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
