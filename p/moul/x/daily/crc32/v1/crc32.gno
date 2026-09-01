// Package crc32 implements the CRC-32 checksum as a pure, reusable package.
//
// CRC-32 treats a message as one enormous binary number and takes the remainder
// of dividing it by a fixed polynomial. The bit-reflected, table-driven form
// implemented here is the one everything actually uses — zip, gzip, PNG, and
// Ethernet all speak IEEE.
//
// Three polynomials are provided:
//
//   - IEEE       (0xEDB88320) — zip/gzip/PNG. The default.
//   - Castagnoli (0x82F63B78) — iSCSI/btrfs; better error detection.
//   - Koopman    (0xEB31D82E)
//
// A CRC is an ACCIDENT detector, not a security primitive: it is linear, so
// anyone can craft a different message with the same checksum. Never use it to
// authenticate anything.
//
// A live demo of this package is at
// [r/moul/x/daily/crc32demo](/r/moul/x/daily/crc32demo/v1).
package crc32

import "strings"

// Common reversed polynomials.
const (
	IEEE       = 0xEDB88320
	Castagnoli = 0x82F63B78
	Koopman    = 0xEB31D82E
)

// Table is a precomputed byte-wise lookup table for one polynomial.
type Table [256]uint32

// MakeTable builds the lookup table for a reversed polynomial. Building it once
// and reusing it is the whole point of the table-driven form: it trades 1 KiB
// for eight bit-shifts per byte.
func MakeTable(poly uint32) *Table {
	var t Table
	for i := 0; i < 256; i++ {
		crc := uint32(i)
		for j := 0; j < 8; j++ {
			if crc&1 != 0 {
				crc = (crc >> 1) ^ poly
			} else {
				crc >>= 1
			}
		}
		t[i] = crc
	}
	return &t
}

var ieeeTable = MakeTable(IEEE)

// Update adds the bytes of s to a running checksum.
//
// Takes and returns the RAW register, not the final value: the caller-visible
// checksum is the register XOR 0xFFFFFFFF, so chaining Update calls on final
// values would be wrong. Start from 0 and finish with Finalize.
func Update(crc uint32, t *Table, s string) uint32 {
	for i := 0; i < len(s); i++ {
		crc = t[byte(crc)^s[i]] ^ (crc >> 8)
	}
	return crc
}

// Finalize turns a running register into the checksum.
func Finalize(crc uint32) uint32 { return crc ^ 0xFFFFFFFF }

// ChecksumWith returns the CRC-32 of s under the given table.
func ChecksumWith(s string, t *Table) uint32 {
	return Finalize(Update(0xFFFFFFFF, t, s))
}

// Checksum returns the IEEE CRC-32 of s — the one zip, gzip and PNG use.
func Checksum(s string) uint32 { return ChecksumWith(s, ieeeTable) }

// Hex renders a checksum as eight lowercase hex digits, zero-padded, which is
// how CRCs are conventionally shown.
func Hex(crc uint32) string {
	const digits = "0123456789abcdef"
	var b [8]byte
	for i := 7; i >= 0; i-- {
		b[i] = digits[crc&0xF]
		crc >>= 4
	}
	return string(b[:])
}

// ChecksumHex is Checksum rendered with Hex.
func ChecksumHex(s string) string { return Hex(Checksum(s)) }

// Verify reports whether s has the expected checksum.
func Verify(s string, expected uint32) bool { return Checksum(s) == expected }

// Split returns the checksum of each line of s, in order.
func Split(s string) []string {
	out := []string{}
	for _, line := range strings.Split(s, "\n") {
		out = append(out, ChecksumHex(line))
	}
	return out
}
