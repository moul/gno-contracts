// Package wesh implements the publishable, non-secret half of the Wesh
// protocol (weshnet, the network layer behind Berty) as a pure gno library.
//
// # What this is, and what it deliberately is not
//
// Wesh is an off-grid, peer-to-peer, end-to-end-encrypted messaging protocol.
// A public blockchain is the opposite of that in almost every dimension:
// globally replicated, permanent, publicly readable and totally ordered. So
// "put Wesh on chain" is the wrong goal, and this package does not pursue it.
//
// What a chain *is* good at is the one thing Wesh has no answer for: an
// authenticated, ordered, publicly auditable record that no single party owns.
// Wesh has three gaps of exactly that shape:
//
//  1. A Berty identity travels out of band, as a QR code or a
//     https://berty.tech/id# link. There is no way to look one up, and the
//     web prefix is a single host that can be blocked or spoofed.
//  2. Resetting the public rendezvous seed (ContactRequestResetReference)
//     silently invalidates every link ever shared. There is no revocation
//     channel, so a business card keeps pointing at a dead rendezvous point.
//  3. A device, once linked to an account, can never be revoked. The Wesh
//     protocol documentation states this outright. The account metadata log is
//     append-only and there is no authority that can mark an entry void.
//
// This package carries the pieces needed to address those on chain, and
// nothing else. Everything here is public by construction:
//
//   - [Contact], the publishable identity, weshnet's ShareableContact
//     (account public key + public rendezvous seed + display name).
//   - The Berty link codec, byte-compatible with berty's own MarshalLink.
//   - [RendezvousPoint], the rotating DHT address derivation.
//   - The canonical statements an account signs to bind itself to a gno
//     address, rotate its seed, and append to a device sigchain.
//
// # What must never reach a chain
//
// Group secrets (weshnet's Group.secret, Group.link_key), device chain keys,
// message keys, ciphertexts. Publishing a group secret hands the group to
// everyone; publishing ciphertext is permanent, expensive, and leaks the
// social graph through access patterns. This package has no type that can
// hold one, which is the point: there is no struct field here for a secret to
// accidentally land in.
//
// # The privacy trade-off, stated plainly
//
// Publishing a rendezvous seed is equivalent to printing your Berty QR code on
// a billboard. Anyone can then derive today's rendezvous point with
// [RendezvousPoint] and watch the DHT for who shows up. That is a real
// deanonymization surface, and it is why publication must be an explicit,
// opt-in act for an identity that *wants* to be found: a support line, a shop,
// a DAO's public channel.
//
// For an identity that does not want that, [SeedCommitment] publishes
// H(seed ‖ salt) instead. The chain then proves that a seed handed over out of
// band really does belong to the named account, without broadcasting the
// rendezvous point to the world.
//
// Live realm using this library: [r/moul/x/wesh](/r/moul/x/wesh/v0).
package wesh

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
)

const (
	// SeedLen is the length of a public rendezvous seed. Matches weshnet's
	// protocoltypes.RendezvousSeedLength.
	SeedLen = 32

	// AccountPKLen is the length of an account public key. weshnet validates
	// it with libp2p's UnmarshalEd25519PublicKey, which accepts raw 32-byte
	// ed25519 public keys only.
	AccountPKLen = 32

	// DevicePKLen is the length of a device public key: also a raw ed25519
	// public key.
	DevicePKLen = 32

	// MaxDisplayNameLen bounds the display name so a link stays scannable and
	// gas stays predictable. Not a protocol constant.
	MaxDisplayNameLen = 64
)

var (
	ErrBadSeedLen        = errors.New("wesh: public rendezvous seed must be 32 bytes")
	ErrBadAccountPKLen   = errors.New("wesh: account public key must be a raw 32-byte ed25519 key")
	ErrBadDevicePKLen    = errors.New("wesh: device public key must be a raw 32-byte ed25519 key")
	ErrDisplayNameTooLong = errors.New("wesh: display name exceeds MaxDisplayNameLen")
	ErrBadCommitmentLen  = errors.New("wesh: seed commitment must be 32 bytes")
	ErrBadHex            = errors.New("wesh: value is not valid hex")
)

// Contact is the publishable identity of a Wesh account: weshnet's
// ShareableContact. It is everything a stranger needs to send a contact
// request, and it contains no secret.
//
// AccountPK is the raw ed25519 account public key. Seed is the public
// rendezvous seed; together they derive the rotating rendezvous point the
// account announces on, see [RendezvousPoint]. DisplayName is free-form app
// metadata and is not authenticated by anything.
type Contact struct {
	AccountPK   []byte
	Seed        []byte
	DisplayName string
}

// Validate applies weshnet's own ShareableContact.CheckFormat rules: the seed
// must be exactly SeedLen bytes, and the account key must be a raw ed25519
// public key. It deliberately does not verify that AccountPK is a valid curve
// point; that costs a scalar multiplication and the chain gets the same
// guarantee for free the first time it verifies a signature under the key.
func (c Contact) Validate() error {
	if len(c.Seed) != SeedLen {
		return ErrBadSeedLen
	}
	if len(c.AccountPK) != AccountPKLen {
		return ErrBadAccountPKLen
	}
	if len(c.DisplayName) > MaxDisplayNameLen {
		return ErrDisplayNameTooLong
	}
	return nil
}

// SeedCommitment returns H(seed ‖ salt), the value published instead of the
// seed itself when an account wants the chain to attest the binding without
// broadcasting its rendezvous point.
//
// The salt is not optional: a seed is 32 bytes of entropy, but a commitment
// with no salt is a deterministic function of the seed, so two accounts that
// (impossibly, but still) shared a seed would be linkable, and a seed later
// disclosed out of band retroactively confirms every past commitment. The salt
// keeps disclosure a deliberate act.
func SeedCommitment(seed, salt []byte) ([]byte, error) {
	if len(seed) != SeedLen {
		return nil, ErrBadSeedLen
	}
	buf := make([]byte, 0, len(seed)+len(salt))
	buf = append(buf, seed...)
	buf = append(buf, salt...)
	sum := sha256.Sum256(buf)
	return sum[:], nil
}

// OpenCommitment reports whether commitment is H(seed ‖ salt).
//
// The comparison is constant-time over the digest: a short-circuiting compare
// leaks, through gas, how many leading bytes of a guess were right.
func OpenCommitment(commitment, seed, salt []byte) bool {
	want, err := SeedCommitment(seed, salt)
	if err != nil {
		return false
	}
	return constantTimeEqual(commitment, want)
}

// constantTimeEqual compares two byte slices without an early return.
func constantTimeEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := 0; i < len(a); i++ {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}

// Every key this package handles is 32 bytes, so a single length-checking
// helper cannot say which one was wrong. These four wrappers exist so the
// error a realm surfaces names the field the caller actually got wrong.

// DecodeAccountPK parses a hex-encoded account public key.
func DecodeAccountPK(s string) ([]byte, error) {
	return decodeFixed(s, AccountPKLen, ErrBadAccountPKLen)
}

// DecodeSeed parses a hex-encoded public rendezvous seed.
func DecodeSeed(s string) ([]byte, error) {
	return decodeFixed(s, SeedLen, ErrBadSeedLen)
}

// DecodeDevicePK parses a hex-encoded device public key.
func DecodeDevicePK(s string) ([]byte, error) {
	return decodeFixed(s, DevicePKLen, ErrBadDevicePKLen)
}

// DecodeCommitment parses a hex-encoded seed commitment.
func DecodeCommitment(s string) ([]byte, error) {
	return decodeFixed(s, DigestLen, ErrBadCommitmentLen)
}

// decodeFixed parses hex and enforces an exact byte length. Realms take keys
// as hex strings because that is what a transaction argument can carry; this
// is the single place the length rule is applied.
func decodeFixed(s string, want int, badLen error) ([]byte, error) {
	b, err := hex.DecodeString(s)
	if err != nil {
		return nil, ErrBadHex
	}
	if len(b) != want {
		return nil, badLen
	}
	return b, nil
}
