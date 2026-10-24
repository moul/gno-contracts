// Package bech32 implements the Bech32 and Bech32m string formats of BIP-173
// and BIP-350 as a pure, reusable package.
//
// A Bech32 string is a human-readable part ("g", "bc", "cosmos"), the separator
// '1', and a data part written in a 32-character alphabet that ends in a 6-character
// BCH checksum. The checksum is the point: it detects every error of up to four
// characters, and locates a single wrong character well enough for a wallet to say
// which one it is. That is why a gno.land address, a Bitcoin segwit address and a
// Cosmos account address all look the way they do.
//
// Two variants, differing only in the constant the checksum is xored with:
//
//   - [Bech32] (constant 1), BIP-173. What gno.land addresses use.
//   - [Bech32m] (constant 0x2bc830a3), BIP-350. Adopted after a length-extension
//     weakness was found in the original: a Bech32 string ending in 'p' keeps its
//     checksum valid when 'q' characters are inserted before that final 'p'.
//
// [Decode] accepts either and reports which one it read, so a caller that cares
// (segwit v1 and later must be Bech32m) can check rather than assume.
//
// The data part is a sequence of 5-bit groups. [ConvertBits] regroups an ordinary
// 8-bit payload into those groups and back, and [EncodeBytes] / [DecodeBytes] are
// the two wrapped together for the common case:
//
//	hrp, payload, _, err := bech32.DecodeBytes("g1manfred47kzduec920z88wfr64ylksmdcedlf5")
//	// hrp == "g", payload is the 20-byte address
//
// A live demo of this package is at
// [r/moul/x/daily/bech32demo](/r/moul/x/daily/bech32demo/v0).
package bech32

import "errors"

// Variant distinguishes the two checksum constants.
type Variant int

// The two variants.
const (
	// Bech32 is BIP-173, checksum constant 1.
	Bech32 Variant = iota
	// Bech32m is BIP-350, checksum constant 0x2bc830a3.
	Bech32m
)

// String names the variant, "bech32" or "bech32m".
func (v Variant) String() string {
	switch v {
	case Bech32:
		return "bech32"
	case Bech32m:
		return "bech32m"
	}
	return "invalid"
}

func (v Variant) constant() uint32 {
	if v == Bech32m {
		return 0x2bc830a3
	}
	return 1
}

var (
	// ErrTooLong is returned when a string exceeds MaxLen.
	ErrTooLong = errors.New("bech32: string too long")
	// ErrTooShort is returned when a string is shorter than the minimum.
	ErrTooShort = errors.New("bech32: string too short")
	// ErrMixedCase is returned when a string mixes upper and lower case.
	ErrMixedCase = errors.New("bech32: mixed case")
	// ErrNoSeparator is returned when the '1' separator is missing.
	ErrNoSeparator = errors.New("bech32: no separator")
	// ErrInvalidHRP is returned for an out-of-range human-readable part.
	ErrInvalidHRP = errors.New("bech32: invalid human-readable part")
	// ErrInvalidChar is returned when the data part holds a non-charset byte.
	ErrInvalidChar = errors.New("bech32: invalid data character")
	// ErrInvalidData is returned when a group does not fit its bit width.
	ErrInvalidData = errors.New("bech32: invalid data value")
	// ErrChecksum is returned when the trailing checksum does not verify.
	ErrChecksum = errors.New("bech32: bad checksum")
	// ErrInvalidBits is returned for an unsupported ConvertBits width.
	ErrInvalidBits = errors.New("bech32: invalid bit width")
	// ErrInvalidPadding is returned when unpadded conversion leaves bits over.
	ErrInvalidPadding = errors.New("bech32: invalid padding")
	// ErrInvalidVariant is returned for a Variant that is neither constant.
	ErrInvalidVariant = errors.New("bech32: invalid variant")
)


// MaxLen is BIP-173's cap on the whole encoded string, separator and checksum
// included. It exists so that a wrong character can always be located, and it is
// what keeps a decode bounded in gas.
const MaxLen = 90

// ChecksumLen is the number of data characters the checksum occupies.
const ChecksumLen = 6

// Charset is the 32-character data alphabet. It omits '1', 'b', 'i' and 'o',
// the four that are easiest to misread.
const Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

// Encode builds a Bech32 string from a human-readable part and 5-bit groups.
func Encode(hrp string, data []byte) (string, error) {
	return EncodeVariant(hrp, data, Bech32)
}

// EncodeVariant is [Encode] with an explicit checksum variant.
//
// hrp is lowercased; every data byte must be below 32. The result is always
// lowercase, which is the form BIP-173 requires anything machine-generated to use.
func EncodeVariant(hrp string, data []byte, v Variant) (string, error) {
	if v != Bech32 && v != Bech32m {
		return "", ErrInvalidVariant
	}
	hrp = toLower(hrp)
	if err := checkHRP(hrp); err != nil {
		return "", err
	}
	for _, d := range data {
		if d >= 32 {
			return "", ErrInvalidData
		}
	}
	if len(hrp)+1+len(data)+ChecksumLen > MaxLen {
		return "", ErrTooLong
	}

	out := make([]byte, 0, len(hrp)+1+len(data)+ChecksumLen)
	out = append(out, hrp...)
	out = append(out, '1')
	for _, d := range data {
		out = append(out, Charset[d])
	}
	for _, d := range checksum(hrp, data, v) {
		out = append(out, Charset[d])
	}
	return string(out), nil
}

// Decode parses a Bech32 or Bech32m string into its human-readable part, its
// 5-bit data groups (checksum removed) and the variant whose checksum verified.
//
// The input may be all upper or all lower case, never a mix; the returned
// human-readable part is lowercase.
func Decode(s string) (string, []byte, Variant, error) {
	if len(s) > MaxLen {
		return "", nil, Bech32, ErrTooLong
	}
	hasUpper, hasLower := false, false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < 33 || c > 126 {
			return "", nil, Bech32, ErrInvalidChar
		}
		if c >= 'A' && c <= 'Z' {
			hasUpper = true
		}
		if c >= 'a' && c <= 'z' {
			hasLower = true
		}
	}
	if hasUpper && hasLower {
		return "", nil, Bech32, ErrMixedCase
	}
	s = toLower(s)

	sep := lastIndexByte(s, '1')
	if sep < 0 {
		return "", nil, Bech32, ErrNoSeparator
	}
	hrp := s[:sep]
	if err := checkHRP(hrp); err != nil {
		return "", nil, Bech32, err
	}
	part := s[sep+1:]
	if len(part) < ChecksumLen {
		return "", nil, Bech32, ErrTooShort
	}

	data := make([]byte, 0, len(part))
	for i := 0; i < len(part); i++ {
		idx := indexByte(Charset, part[i])
		if idx < 0 {
			return "", nil, Bech32, ErrInvalidChar
		}
		data = append(data, byte(idx))
	}

	v := Bech32
	got := polymod(append(hrpExpand(hrp), data...))
	if got != v.constant() {
		v = Bech32m
		if got != v.constant() {
			return "", nil, Bech32, ErrChecksum
		}
	}
	return hrp, data[:len(data)-ChecksumLen], v, nil
}

// ConvertBits regroups data from one bit width to another, most significant bit
// first. Going 8 to 5 needs pad set, since the last group is rarely full; coming
// back 5 to 8 must not pad, so that leftover bits are reported rather than turned
// into a trailing zero byte.
func ConvertBits(data []byte, from, to uint8, pad bool) ([]byte, error) {
	if from < 1 || from > 8 || to < 1 || to > 8 {
		return nil, ErrInvalidBits
	}
	maxv := uint32(1)<<to - 1
	acc := uint32(0)
	bits := uint8(0)
	out := make([]byte, 0, len(data)*int(from)/int(to)+1)
	for _, b := range data {
		if from < 8 && uint32(b) >= uint32(1)<<from {
			return nil, ErrInvalidData
		}
		acc = acc<<from | uint32(b)
		bits += from
		for bits >= to {
			bits -= to
			out = append(out, byte(acc>>bits&maxv))
		}
	}
	if pad {
		if bits > 0 {
			out = append(out, byte(acc<<(to-bits)&maxv))
		}
		return out, nil
	}
	if bits >= from || acc<<(to-bits)&maxv != 0 {
		return nil, ErrInvalidPadding
	}
	return out, nil
}

// EncodeBytes encodes an 8-bit payload as Bech32, converting to 5-bit groups
// first. This is the call an address wants.
func EncodeBytes(hrp string, payload []byte) (string, error) {
	if err := checkHRP(toLower(hrp)); err != nil {
		return "", err
	}
	// Refuse before regrouping, not after: ConvertBits would otherwise scan and
	// materialise a payload of any size only for Encode to reject the result.
	if len(payload) > MaxPayloadLen(hrp) {
		return "", ErrTooLong
	}
	data, err := ConvertBits(payload, 8, 5, true)
	if err != nil {
		return "", err
	}
	return Encode(hrp, data)
}

// DecodeBytes decodes a string and converts its data part back to 8-bit bytes.
func DecodeBytes(s string) (string, []byte, Variant, error) {
	hrp, data, v, err := Decode(s)
	if err != nil {
		return "", nil, Bech32, err
	}
	payload, err := ConvertBits(data, 5, 8, false)
	if err != nil {
		return "", nil, Bech32, err
	}
	return hrp, payload, v, nil
}

// MaxPayloadLen is the largest 8-bit payload [EncodeBytes] can fit under hrp
// without passing MaxLen. It is 51 bytes for a gno.land address, whose
// human-readable part is one character, and 0 when hrp leaves no room at all.
func MaxPayloadLen(hrp string) int {
	groups := MaxLen - len(hrp) - 1 - ChecksumLen
	if groups <= 0 {
		return 0
	}
	// A payload of b bytes needs ceil(8b/5) groups, so b groups fit exactly
	// while 8b <= 5*groups.
	return groups * 5 / 8
}

// checksum returns the six 5-bit groups that terminate the data part.
func checksum(hrp string, data []byte, v Variant) []byte {
	values := append(hrpExpand(hrp), data...)
	values = append(values, 0, 0, 0, 0, 0, 0)
	mod := polymod(values) ^ v.constant()
	out := make([]byte, ChecksumLen)
	for i := 0; i < ChecksumLen; i++ {
		out[i] = byte(mod>>uint(5*(5-i))) & 31
	}
	return out
}

// polymod is the BCH code of BIP-173 over GF(32).
func polymod(values []byte) uint32 {
	gen := [5]uint32{0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3}
	chk := uint32(1)
	for _, v := range values {
		top := chk >> 25
		chk = (chk&0x1ffffff)<<5 ^ uint32(v)
		for i := 0; i < 5; i++ {
			if (top>>uint(i))&1 == 1 {
				chk ^= gen[i]
			}
		}
	}
	return chk
}

// hrpExpand spreads the human-readable part into the 5-bit groups the checksum
// is computed over: every high 3 bits, a zero, then every low 5 bits.
func hrpExpand(hrp string) []byte {
	out := make([]byte, 0, len(hrp)*2+1)
	for i := 0; i < len(hrp); i++ {
		out = append(out, hrp[i]>>5)
	}
	out = append(out, 0)
	for i := 0; i < len(hrp); i++ {
		out = append(out, hrp[i]&31)
	}
	return out
}

// checkHRP rejects an empty human-readable part and any byte outside printable
// US-ASCII, which is what BIP-173 allows there.
func checkHRP(hrp string) error {
	if len(hrp) == 0 {
		return ErrInvalidHRP
	}
	for i := 0; i < len(hrp); i++ {
		if hrp[i] < 33 || hrp[i] > 126 {
			return ErrInvalidHRP
		}
	}
	return nil
}

func toLower(s string) string {
	out := []byte(s)
	for i := 0; i < len(out); i++ {
		if out[i] >= 'A' && out[i] <= 'Z' {
			out[i] += 32
		}
	}
	return string(out)
}

func indexByte(s string, c byte) int {
	for i := 0; i < len(s); i++ {
		if s[i] == c {
			return i
		}
	}
	return -1
}

func lastIndexByte(s string, c byte) int {
	for i := len(s) - 1; i >= 0; i-- {
		if s[i] == c {
			return i
		}
	}
	return -1
}
