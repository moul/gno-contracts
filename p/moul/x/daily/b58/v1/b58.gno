// Package b58 ports the core of Bitcoin's Base58 codec (à la mr-tron/base58 and
// btcutil/base58) to gno — as a reusable pure package.
//
// Base58 is a base conversion from base-256 (raw bytes) to base-58 using an
// alphabet that omits the visually ambiguous characters 0 (zero), O (capital
// o), I (capital i) and l (lower L). The conversion is done with pure byte-slice
// math — the classic div/mod-by-58 carry loop — so it needs no math/big. Leading
// zero bytes map to leading '1' characters and back, exactly like the reference
// implementations.
//
// A live demo of this package (an interactive encoder / round-tripper) is at
// [r/moul/x/daily/b58demo](/r/moul/x/daily/b58demo/v1).
package b58

import "strings"

// Alphabet is the Bitcoin Base58 alphabet.
const Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

// Encode converts a byte slice to its Base58 string representation.
//
// Algorithm: treat the input as a big base-256 integer and repeatedly convert
// it into base-58 digits via a carry loop, most-significant digit first. Each
// leading zero byte becomes a leading '1'.
func Encode(input []byte) string {
	// Count leading zero bytes — they encode as '1' and are handled apart.
	zeros := 0
	for zeros < len(input) && input[zeros] == 0 {
		zeros++
	}

	// Upper bound on the base-58 digit count: log(256)/log(58) ≈ 1.365, so
	// 138/100 of the significant byte count (+1) is always enough.
	size := (len(input)-zeros)*138/100 + 1
	digits := make([]byte, size)

	length := 0
	for i := zeros; i < len(input); i++ {
		carry := int(input[i])
		j := 0
		// Walk from the least-significant end, folding the new byte in.
		for k := size - 1; (carry != 0 || j < length) && k >= 0; k-- {
			carry += 256 * int(digits[k])
			digits[k] = byte(carry % 58)
			carry /= 58
			j++
		}
		length = j
	}

	// Skip the leading zero digits produced by the over-allocation.
	it := size - length

	out := make([]byte, 0, zeros+length)
	for i := 0; i < zeros; i++ {
		out = append(out, '1')
	}
	for ; it < size; it++ {
		out = append(out, Alphabet[digits[it]])
	}
	return string(out)
}

// Decode converts a Base58 string back to the original byte slice. It returns
// nil if the string contains a character outside the alphabet.
//
// Algorithm: the mirror of Encode — treat the string as a big base-58 integer
// and convert it back to base-256 bytes with a carry loop. Each leading '1'
// becomes a leading zero byte.
func Decode(s string) []byte {
	// Count leading '1's — they decode to zero bytes.
	zeros := 0
	for zeros < len(s) && s[zeros] == '1' {
		zeros++
	}

	// Upper bound on the byte count: log(58)/log(256) ≈ 0.733.
	size := (len(s)-zeros)*733/1000 + 1
	bytesBuf := make([]byte, size)

	length := 0
	for i := zeros; i < len(s); i++ {
		carry := strings.IndexByte(Alphabet, s[i])
		if carry < 0 {
			return nil // character not in the alphabet
		}
		j := 0
		for k := size - 1; (carry != 0 || j < length) && k >= 0; k-- {
			carry += 58 * int(bytesBuf[k])
			bytesBuf[k] = byte(carry % 256)
			carry /= 256
			j++
		}
		length = j
	}

	it := size - length

	out := make([]byte, 0, zeros+length)
	for i := 0; i < zeros; i++ {
		out = append(out, 0)
	}
	for ; it < size; it++ {
		out = append(out, bytesBuf[it])
	}
	return out
}

// IsValid reports whether every character of s belongs to the Base58 alphabet.
func IsValid(s string) bool {
	for i := 0; i < len(s); i++ {
		if strings.IndexByte(Alphabet, s[i]) < 0 {
			return false
		}
	}
	return true
}
