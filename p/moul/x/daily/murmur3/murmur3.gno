// Package murmur3 implements MurmurHash3 x86_32, Austin Appleby's
// non-cryptographic hash, as a pure, reusable package.
//
// The function reads the input four bytes at a time. Each block is scrambled
// by two odd constants and a rotate, mixed into the accumulator, and the
// accumulator is itself rotated and run through a multiply-add. The leftover
// one to three bytes take an abbreviated version of the same scramble, the
// length is folded in, and a final avalanche of shift-xor-multiply spreads
// every input bit over every output bit. That last stage is why flipping one
// letter changes the whole result rather than a corner of it.
//
// What it is for on chain: bucketing. Spreading keys over a fixed number of
// shards, sizing a sketch, picking a deterministic slot. [Bucket] is that use
// spelled out.
//
// What it is NOT for: anything an adversary chooses the input to. MurmurHash3
// is trivially invertible and collisions can be generated on demand, so a
// hash table keyed by caller-supplied strings can be driven into its worst
// case by anyone who wants to. It is not a commitment, not a signature, and
// not a substitute for a cryptographic digest.
//
// Correctness here rests on [Verification], the SMHasher self-test: it hashes
// 256 keys of growing length under 256 different seeds and hashes the results,
// which pins every constant, every tail branch and the byte order in one
// 32-bit number.
//
// A live demo of this package is at
// [r/moul/x/daily/murmur3demo](/r/moul/x/daily/murmur3demo/v0).
package murmur3

import "math/bits"

// The two block-scramble constants, and the two avalanche multipliers. Odd,
// and chosen by search rather than derived: changing any of them gives a
// different function, not a worse one, which is why [Verification] exists.
const (
	c1 = 0xcc9e2d51
	c2 = 0x1b873593

	m1 = 0x85ebca6b
	m2 = 0xc2b2ae35
)

// Sum32 returns the MurmurHash3 x86_32 hash of s with seed 0.
func Sum32(s string) uint32 { return Sum32Seed(s, 0) }

// Sum32Seed returns the MurmurHash3 x86_32 hash of s under the given seed.
//
// The seed re-keys the entire function: the same input under two seeds gives
// two unrelated results. That is what makes a family of independent hashes out
// of one function, which is what a Bloom filter or a count-min sketch needs.
func Sum32Seed(s string, seed uint32) uint32 {
	h := seed
	n := len(s)
	nblocks := n / 4

	for i := 0; i < nblocks; i++ {
		j := i * 4
		// Little-endian, which is the reference implementation's byte order
		// and part of what Verification pins.
		k := uint32(s[j]) | uint32(s[j+1])<<8 | uint32(s[j+2])<<16 | uint32(s[j+3])<<24
		h ^= scramble(k)
		h = bits.RotateLeft32(h, 13)
		h = h*5 + 0xe6546b64
	}

	// The tail: one to three bytes that do not fill a block. They are
	// scrambled but never mixed into the rotate-multiply-add, so the tail
	// contributes less than a full block would. That asymmetry is in the
	// reference too.
	var k uint32
	switch n - nblocks*4 {
	case 3:
		k ^= uint32(s[nblocks*4+2]) << 16
		fallthrough
	case 2:
		k ^= uint32(s[nblocks*4+1]) << 8
		fallthrough
	case 1:
		k ^= uint32(s[nblocks*4])
		h ^= scramble(k)
	}

	// Folding the length in is what keeps "a" and "a\x00" apart.
	h ^= uint32(n)
	return avalanche(h)
}

// scramble applies the per-block mix shared by the main loop and the tail.
func scramble(k uint32) uint32 {
	k *= c1
	k = bits.RotateLeft32(k, 15)
	k *= c2
	return k
}

// avalanche is the finalizer: it spreads every input bit across every output
// bit, so two inputs differing by one bit give results that look unrelated.
func avalanche(h uint32) uint32 {
	h ^= h >> 16
	h *= m1
	h ^= h >> 13
	h *= m2
	h ^= h >> 16
	return h
}

// Hex renders a hash as eight lowercase hex digits, zero-padded, which is how
// Murmur results are conventionally shown.
func Hex(h uint32) string {
	const digits = "0123456789abcdef"
	var b [8]byte
	for i := 7; i >= 0; i-- {
		b[i] = digits[h&0xF]
		h >>= 4
	}
	return string(b[:])
}

// SumHex is Sum32 rendered with Hex.
func SumHex(s string) string { return Hex(Sum32(s)) }

// Bucket returns a shard index in [0, n) for s, or -1 when n is not positive.
//
// This is the thing the hash is actually good for: a deterministic, evenly
// spread slot for a key, with no storage and no ordering. Do not use it where
// the key comes from someone with a reason to collide.
func Bucket(s string, n int) int {
	if n <= 0 {
		return -1
	}
	return int(Sum32(s) % uint32(n))
}

// Verification returns the SMHasher verification value for this hash, which is
// 0xB0F57EE3 for a correct MurmurHash3 x86_32.
//
// The procedure is SMHasher's: hash the keys {0}, {0,1}, {0,1,2}, ... up to 255
// bytes, the key of length i under seed 256-i, write each 32-bit result
// little-endian into one buffer, then hash that buffer with seed 0. It is a
// self-test rather than a hash of anything useful, and it is the reason this
// package can claim to be the same function as everyone else's.
func Verification() uint32 {
	key := make([]byte, 256)
	hashes := make([]byte, 256*4)
	for i := 0; i < 256; i++ {
		key[i] = byte(i)
		h := Sum32Seed(string(key[:i]), uint32(256-i))
		hashes[i*4] = byte(h)
		hashes[i*4+1] = byte(h >> 8)
		hashes[i*4+2] = byte(h >> 16)
		hashes[i*4+3] = byte(h >> 24)
	}
	return Sum32(string(hashes))
}
