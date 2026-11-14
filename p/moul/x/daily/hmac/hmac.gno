// Package hmac implements keyed-hash message authentication (HMAC), the
// construction specified by RFC 2104 and FIPS 198-1, on top of a one-shot hash
// function.
//
// A hash answers "has this message changed". A MAC answers "did the holder of
// this key produce this message", which is a different question and the one
// almost every protocol actually asks. The naive way to key a hash,
// sha256(key || message), is not a MAC: a Merkle-Damgard hash publishes its
// internal state as its output, so anyone holding one valid tag can append to
// the message and produce a valid tag for the longer one without ever seeing
// the key. HMAC runs the hash twice, under two different derivations of the
// key, and the inner digest the attacker would need to extend never leaves the
// function.
//
//	tag = H((K' xor opad) || H((K' xor ipad) || message))
//
// K' is the key padded with zeros to the hash's block size, or the key's own
// digest first when it is longer than that. Two consequences are worth knowing
// before you choose a key, and both are pinned by tests:
//
//   - a key longer than the block size is replaced by its hash, so a long key
//     and its digest are the SAME key as far as this function is concerned;
//   - a short key is zero-padded, so a key and that key followed by zero bytes
//     are also the same key.
//
// The construction here takes the hash as a [HashFunc] rather than a streaming
// interface, because gno's crypto/sha256 exposes only Sum256 and that is all
// HMAC needs: two calls, no incremental state.
//
// # On chain
//
// Everything a realm stores is public. A secret key in realm state is not a
// secret, so the useful shapes are verification against a key the caller
// supplies in the transaction, or a commitment published now and opened later.
// Do not put a long-lived key in a realm and call the result authenticated.
//
// Live demo: [r/moul/x/daily/hmacdemo](/r/moul/x/daily/hmacdemo/v0).
package hmac

import (
	"crypto/sha256"
	"encoding/hex"
)

const (
	// BlockSizeSHA256 is SHA-256's internal block size in bytes. It is the
	// width HMAC pads the key to, and it is 64 even though the digest is 32:
	// the two are different numbers and using the digest size here produces
	// tags that look fine and match nothing.
	BlockSizeSHA256 = 64

	// SizeSHA256 is the length in bytes of an HMAC-SHA-256 tag.
	SizeSHA256 = 32

	ipad = 0x36
	opad = 0x5c
)

// HashFunc is a one-shot hash: it returns the digest of data and keeps no
// state between calls. [SHA256] is the one implementation gno's standard
// library can supply today.
type HashFunc func(data []byte) []byte

// SHA256 returns the SHA-256 digest of data as a slice. It exists so that
// crypto/sha256's array-returning Sum256 can be passed as a [HashFunc].
func SHA256(data []byte) []byte {
	sum := sha256.Sum256(data)
	return sum[:]
}

// Sum returns the HMAC of message under key, computed with h over blocks of
// blockSize bytes. blockSize is the hash's INTERNAL block size, not its digest
// size: for SHA-256 that is 64, which is what [BlockSizeSHA256] holds.
//
// It panics if h is nil, if blockSize is not positive, or, when the key is
// long enough to be folded, if h's own digest is longer than blockSize: there
// is nowhere to put the folded key and a tag produced anyway would mean
// nothing. That last check only runs on the folding path, so a mismatched
// blockSize paired with a short key is accepted and produces a tag no other
// implementation will reproduce. Pass the hash's real block size.
//
// Neither key nor message is modified.
func Sum(h HashFunc, blockSize int, key, message []byte) []byte {
	if h == nil {
		panic("hmac: nil hash function")
	}
	if blockSize <= 0 {
		panic("hmac: block size must be positive")
	}

	k := key
	if len(k) > blockSize {
		k = h(k)
		if len(k) > blockSize {
			panic("hmac: hash digest is longer than the block size")
		}
	}

	inner := make([]byte, blockSize+len(message))
	outer := make([]byte, blockSize)
	for i := 0; i < blockSize; i++ {
		var b byte
		if i < len(k) {
			b = k[i]
		}
		inner[i] = b ^ ipad
		outer[i] = b ^ opad
	}
	copy(inner[blockSize:], message)

	return h(append(outer, h(inner)...))
}

// SumSHA256 returns the HMAC-SHA-256 tag of message under key, a 32-byte
// slice. This is the one to reach for unless you have another hash.
func SumSHA256(key, message []byte) []byte {
	return Sum(SHA256, BlockSizeSHA256, key, message)
}

// HexSHA256 returns [SumSHA256] as lowercase hex, for the common case where
// both inputs and the tag are strings.
func HexSHA256(key, message string) string {
	return hex.EncodeToString(SumSHA256([]byte(key), []byte(message)))
}

// VerifySHA256 reports whether tag is the HMAC-SHA-256 of message under key.
// It compares with [Equal] rather than with a plain loop, which is the whole
// reason to call it instead of comparing [SumSHA256] yourself.
func VerifySHA256(key, message, tag []byte) bool {
	return Equal(SumSHA256(key, message), tag)
}

// Equal reports whether a and b are the same bytes, reading all of both
// whenever their lengths match instead of stopping at the first difference.
//
// The reason is that a verifier which returns early tells a caller how many
// leading bytes of a guessed tag were right, which turns forging a tag from
// 2^256 work into 32 rounds of 256 guesses. Comparing lengths first does leak
// the length, and that is deliberate: a tag's length is not a secret.
//
// What this function cannot claim is constant TIME. gno charges gas per
// operation and the loop runs the same operations either way, which is the
// thing being bought here; actual wall-clock behaviour of the host is not
// something a contract can observe or promise.
func Equal(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := 0; i < len(a); i++ {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}

// Truncate returns the first n bytes of tag as a fresh slice, the shortened
// tag RFC 2104 section 5 allows (HMAC-SHA-256-128 is Truncate(tag, 16)). It
// returns the whole tag when n is at or past its length, and panics when n is
// negative.
//
// Truncation trades authentication strength for bytes on chain, and the RFC's
// floor is half the digest, so going below 16 here is a decision to document
// rather than a parameter to tune.
func Truncate(tag []byte, n int) []byte {
	if n < 0 {
		panic("hmac: negative truncation length")
	}
	if n > len(tag) {
		n = len(tag)
	}
	out := make([]byte, n)
	copy(out, tag)
	return out
}
