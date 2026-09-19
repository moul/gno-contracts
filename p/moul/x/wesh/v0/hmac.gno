package wesh

import "crypto/sha256"

// blockSize is SHA-256's internal block size, the padding width HMAC uses.
const blockSize = 64

// HMACSHA256 computes HMAC-SHA256 as specified in RFC 2104.
//
// gno's standard library exposes sha256.Sum256 but no streaming hash.Hash and
// no crypto/hmac, so the construction is spelled out here:
//
//	HMAC(K, m) = H((K' ⊕ opad) ‖ H((K' ⊕ ipad) ‖ m))
//
// with K' the key hashed down when longer than the block size, then
// zero-padded up to it. This is the primitive weshnet's rendezvous point
// derivation is built on, so it has to agree byte-for-byte; see
// [RendezvousPoint].
func HMACSHA256(key, msg []byte) []byte {
	k := key
	if len(k) > blockSize {
		sum := sha256.Sum256(k)
		k = sum[:]
	}

	ipad := make([]byte, blockSize)
	opad := make([]byte, blockSize)
	copy(ipad, k)
	copy(opad, k)
	for i := 0; i < blockSize; i++ {
		ipad[i] ^= 0x36
		opad[i] ^= 0x5c
	}

	inner := sha256.Sum256(append(ipad, msg...))
	outer := sha256.Sum256(append(opad, inner[:]...))
	return outer[:]
}
