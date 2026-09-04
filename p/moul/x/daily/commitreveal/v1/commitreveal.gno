// Package commitreveal implements the commit-then-reveal scheme as a pure,
// reusable package.
//
// The problem it solves: anything submitted to a chain is public before it is
// executed, so a naive sealed-bid auction or simultaneous-move game lets the
// last player read everyone else's move and win for free. Commit-reveal splits
// the action in two — first publish H(value || salt), later publish the value
// and salt. The commitment binds you to a choice without disclosing it.
//
// The SALT is not optional and this package refuses to let a caller skip it.
// Without one, a commitment over a small domain is trivially brute-forced: a
// rock-paper-scissors move has three possible hashes, so hashing all three
// breaks the scheme entirely. MinSaltLen is enforced at commit time rather than
// left as advice in a comment.
//
// Verification is CONSTANT-TIME over the digest. A short-circuiting comparison
// leaks, through timing, how many leading bytes of a guess were right, which is
// enough to reconstruct a commitment byte by byte.
//
// This package computes and checks commitments; it stores nothing and knows
// nothing about phases or deadlines. The realm owns that.
//
// A live demo of this package is at
// [r/moul/x/daily/commitrevealdemo](/r/moul/x/daily/commitrevealdemo/v1).
package commitreveal

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
)

// MinSaltLen is the shortest salt accepted. Short salts make a small-domain
// commitment brute-forceable, which defeats the whole scheme.
const MinSaltLen = 16

// MaxValueLen bounds the committed value so gas stays predictable.
const MaxValueLen = 4096

var (
	ErrShortSalt   = errors.New("commitreveal: salt is shorter than MinSaltLen")
	ErrLongValue   = errors.New("commitreveal: value exceeds MaxValueLen")
	ErrMismatch    = errors.New("commitreveal: reveal does not match the commitment")
	ErrBadHexDigest = errors.New("commitreveal: commitment is not a valid hex digest")
)

// DigestLen is the length in bytes of a commitment digest (SHA-256).
const DigestLen = 32

// Commit returns the hex-encoded commitment for value and salt.
//
// The salt is length-prefixed rather than simply concatenated: with plain
// concatenation, ("ab","cd") and ("a","bcd") hash identically, so one
// commitment could be opened two different ways.
func Commit(value, salt string) (string, error) {
	if len(salt) < MinSaltLen {
		return "", ErrShortSalt
	}
	if len(value) > MaxValueLen {
		return "", ErrLongValue
	}
	return hex.EncodeToString(digest(value, salt)), nil
}

// MustCommit is Commit, panicking on invalid input. For tests and for callers
// that have already validated.
func MustCommit(value, salt string) string {
	c, err := Commit(value, salt)
	if err != nil {
		panic(err.Error())
	}
	return c
}

// Verify reports whether value and salt open the given commitment. The digest
// comparison is constant-time.
func Verify(commitment, value, salt string) bool {
	if len(salt) < MinSaltLen || len(value) > MaxValueLen {
		return false
	}
	want, err := hex.DecodeString(commitment)
	if err != nil || len(want) != DigestLen {
		return false
	}
	return equalConstantTime(want, digest(value, salt))
}

// Open verifies and reports why it failed, for callers wanting a reason rather
// than a bool.
func Open(commitment, value, salt string) error {
	if len(salt) < MinSaltLen {
		return ErrShortSalt
	}
	if len(value) > MaxValueLen {
		return ErrLongValue
	}
	want, err := hex.DecodeString(commitment)
	if err != nil || len(want) != DigestLen {
		return ErrBadHexDigest
	}
	if !equalConstantTime(want, digest(value, salt)) {
		return ErrMismatch
	}
	return nil
}

// ValidCommitment reports whether s is well-formed as a commitment: hex, and
// exactly DigestLen bytes. It says nothing about what it commits to.
func ValidCommitment(s string) bool {
	b, err := hex.DecodeString(s)
	return err == nil && len(b) == DigestLen
}

// digest computes SHA-256 over a length-prefixed encoding of value and salt.
// gno's crypto/sha256 exposes only Sum256, so the message is assembled first
// rather than streamed through a hash.Hash.
func digest(value, salt string) []byte {
	buf := make([]byte, 0, 8+len(value)+len(salt))
	buf = append(buf, lengthPrefix(len(value))...)
	buf = append(buf, value...)
	buf = append(buf, lengthPrefix(len(salt))...)
	buf = append(buf, salt...)
	sum := sha256.Sum256(buf)
	return sum[:]
}

// lengthPrefix encodes n as 4 big-endian bytes.
func lengthPrefix(n int) []byte {
	return []byte{
		byte(n >> 24), byte(n >> 16), byte(n >> 8), byte(n),
	}
}

// equalConstantTime compares two byte slices without short-circuiting, so the
// time taken does not reveal how many leading bytes matched.
func equalConstantTime(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := range a {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}
