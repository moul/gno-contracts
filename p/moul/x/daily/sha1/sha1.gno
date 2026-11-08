// Package sha1 implements SHA-1 (FIPS 180-1, RFC 3174) as a pure, reusable
// package: one-shot, streaming, HMAC-SHA1, and git object ids.
//
// SHA-1 compresses the message 64 bytes at a time into five 32-bit words,
// through 80 rounds that rotate, add and mix a round constant chosen per
// quarter. The whole algorithm is those 80 rounds plus a padding rule: a single
// 0x80 byte, zeros up to 56 bytes mod 64, then the message length in bits as a
// big-endian uint64. Almost every bug in a hand-written SHA-1 is in that
// padding rule, which is why the tests walk every length across the boundary.
//
// SHA-1 is BROKEN as a collision-resistant hash: SHAttered (2017) produced two
// different PDFs with the same digest, and a chosen-prefix collision followed in
// 2020. Never use it to decide that two documents are the same document, and
// never use it for a new signature scheme. It is still correct, and still the
// only answer, where an external format specifies it: git object ids, HMAC-SHA1
// in TOTP and older AWS signatures, and legacy checksum interop.
//
// A live demo of this package is at
// [r/moul/x/daily/sha1demo](/r/moul/x/daily/sha1demo/v0).
package sha1

import "strings"

// Size is the length of a SHA-1 digest in bytes.
const Size = 20

// BlockSize is SHA-1's block size in bytes. HMAC's key padding depends on it.
const BlockSize = 64

// The five initialization constants, FIPS 180-1 section 5.
const (
	init0 = 0x67452301
	init1 = 0xEFCDAB89
	init2 = 0x98BADCFE
	init3 = 0x10325476
	init4 = 0xC3D2E1F0
)

// The four round constants, one per 20 rounds.
const (
	k0 = 0x5A827999
	k1 = 0x6ED9EBA1
	k2 = 0x8F1BBCDC
	k3 = 0xCA62C1D6
)

// Digest is a streaming SHA-1 state: feed it with Write, read it with Sum.
//
// Sum is NOT destructive. It finalizes a copy, so a Digest can be read and then
// written to again, and reading it twice gives the same answer.
type Digest struct {
	h   [5]uint32
	buf [BlockSize]byte
	n   int    // bytes currently in buf
	len uint64 // total bytes written
}

// New returns a Digest ready to hash a fresh message.
func New() *Digest {
	d := &Digest{}
	d.Reset()
	return d
}

// Reset restarts the digest as if nothing had been written.
func (d *Digest) Reset() {
	d.h = [5]uint32{init0, init1, init2, init3, init4}
	d.n = 0
	d.len = 0
}

// Write adds s to the message. Any number of calls is equivalent to one call
// with the concatenation.
func (d *Digest) Write(s string) {
	d.len += uint64(len(s))
	i := 0
	// Top up the partial block first.
	if d.n > 0 {
		for i < len(s) && d.n < BlockSize {
			d.buf[d.n] = s[i]
			d.n++
			i++
		}
		if d.n == BlockSize {
			d.block(d.buf[:])
			d.n = 0
		}
	}
	// Then consume whole blocks straight out of s.
	for i+BlockSize <= len(s) {
		var b [BlockSize]byte
		for j := 0; j < BlockSize; j++ {
			b[j] = s[i+j]
		}
		d.block(b[:])
		i += BlockSize
	}
	// Whatever is left is the new partial block.
	for i < len(s) {
		d.buf[d.n] = s[i]
		d.n++
		i++
	}
}

// Sum returns the digest of everything written so far, without finalizing the
// receiver: padding is applied to a copy.
func (d *Digest) Sum() [Size]byte {
	c := *d
	bits := c.len * 8

	// 0x80, then zeros until 56 bytes mod 64, then the bit length.
	var pad [BlockSize * 2]byte
	pad[0] = 0x80
	padLen := 56 - int(c.len%BlockSize)
	if padLen <= 0 {
		padLen += BlockSize
	}
	for i := 0; i < 8; i++ {
		pad[padLen+i] = byte(bits >> uint(56-8*i))
	}
	c.writePadding(pad[:padLen+8])

	var out [Size]byte
	for i := 0; i < 5; i++ {
		out[4*i] = byte(c.h[i] >> 24)
		out[4*i+1] = byte(c.h[i] >> 16)
		out[4*i+2] = byte(c.h[i] >> 8)
		out[4*i+3] = byte(c.h[i])
	}
	return out
}

// writePadding feeds the final padding block. It deliberately does NOT count
// the bytes into d.len: the length field is already encoded in what it writes.
func (d *Digest) writePadding(p []byte) {
	for _, b := range p {
		d.buf[d.n] = b
		d.n++
		if d.n == BlockSize {
			d.block(d.buf[:])
			d.n = 0
		}
	}
}

// block runs the 80 rounds over one 64-byte block.
func (d *Digest) block(p []byte) {
	var w [80]uint32
	for i := 0; i < 16; i++ {
		w[i] = uint32(p[4*i])<<24 | uint32(p[4*i+1])<<16 | uint32(p[4*i+2])<<8 | uint32(p[4*i+3])
	}
	// The message schedule: this one-bit rotate is the only difference
	// between SHA-1 and the withdrawn SHA-0.
	for i := 16; i < 80; i++ {
		x := w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]
		w[i] = x<<1 | x>>31
	}

	a, b, c, e5 := d.h[0], d.h[1], d.h[2], d.h[3]
	e := d.h[4]
	for i := 0; i < 80; i++ {
		var f, k uint32
		switch {
		case i < 20:
			f, k = (b&c)|(^b&e5), k0
		case i < 40:
			f, k = b^c^e5, k1
		case i < 60:
			f, k = (b&c)|(b&e5)|(c&e5), k2
		default:
			f, k = b^c^e5, k3
		}
		t := (a<<5 | a>>27) + f + e + k + w[i]
		e = e5
		e5 = c
		c = b<<30 | b>>2
		b = a
		a = t
	}
	d.h[0] += a
	d.h[1] += b
	d.h[2] += c
	d.h[3] += e5
	d.h[4] += e
}

// Sum returns the SHA-1 digest of s.
func Sum(s string) [Size]byte {
	d := New()
	d.Write(s)
	return d.Sum()
}

// SumHex returns the SHA-1 digest of s as 40 lowercase hex digits.
func SumHex(s string) string { return Hex(Sum(s)) }

// Hex renders a digest as 40 lowercase hex digits.
func Hex(sum [Size]byte) string {
	const digits = "0123456789abcdef"
	var b strings.Builder
	for _, c := range sum {
		b.WriteByte(digits[c>>4])
		b.WriteByte(digits[c&0x0F])
	}
	return b.String()
}

// Verify reports whether s hashes to hexDigest, which may be in either case.
//
// This is an equality check on a digest, not an authentication primitive: see
// the package doc on why SHA-1 must not decide that two documents match.
func Verify(s, hexDigest string) bool {
	return SumHex(s) == strings.ToLower(strings.TrimSpace(hexDigest))
}

// HMAC returns the HMAC-SHA1 of msg under key (RFC 2104).
//
// A key longer than BlockSize is hashed down to 20 bytes first, which is why
// an 80-byte key and the SHA-1 of that key are the same key.
func HMAC(key, msg string) [Size]byte {
	var k [BlockSize]byte
	if len(key) > BlockSize {
		sum := Sum(key)
		for i := 0; i < Size; i++ {
			k[i] = sum[i]
		}
	} else {
		for i := 0; i < len(key); i++ {
			k[i] = key[i]
		}
	}

	var ipad, opad [BlockSize]byte
	for i := 0; i < BlockSize; i++ {
		ipad[i] = k[i] ^ 0x36
		opad[i] = k[i] ^ 0x5C
	}

	inner := New()
	inner.Write(string(ipad[:]))
	inner.Write(msg)
	is := inner.Sum()

	outer := New()
	outer.Write(string(opad[:]))
	outer.Write(string(is[:]))
	return outer.Sum()
}

// HMACHex returns the HMAC-SHA1 of msg under key as lowercase hex.
func HMACHex(key, msg string) string { return Hex(HMAC(key, msg)) }

// GitBlobID returns the git object id of content: SHA-1 over the header
// "blob <len>\x00" followed by the bytes. It matches `git hash-object`.
func GitBlobID(content string) string {
	d := New()
	d.Write("blob ")
	d.Write(itoa(len(content)))
	d.Write("\x00")
	d.Write(content)
	return Hex(d.Sum())
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
