package wesh

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"
)

// Statement kinds. A signature is only ever valid for the kind it was made
// under, so a binding signature can never be replayed as a device statement.
const (
	kindBind   = "gno.wesh/v0:bind"
	kindDevice = "gno.wesh/v0:device"
)

// Device sigchain operations.
const (
	OpAdd    = "add"
	OpRevoke = "revoke"
)

var (
	ErrBadOp        = errors.New("wesh: operation must be add or revoke")
	ErrBadSignature = errors.New("wesh: signature does not verify under the account key")
	ErrBadSeq       = errors.New("wesh: sequence number must not be negative")
	ErrBadPrevLen   = errors.New("wesh: previous digest must be 32 bytes")
)

// DigestLen is the length of a statement digest (SHA-256).
const DigestLen = 32

// ValidOp reports whether op is a known sigchain operation.
func ValidOp(op string) bool { return op == OpAdd || op == OpRevoke }

// BindStatement returns the canonical text an account signs, with its Wesh
// account private key, to claim a directory entry.
//
// The signature is what makes a directory entry meaningful. Without it anyone
// could publish anyone else's account key next to a seed of their choosing and
// harvest the contact requests that followed. With it, a directory entry is a
// statement by the account itself, verifiable by anyone, replayable nowhere:
//
//   - the kind prefix stops a signature made for one purpose being reused for
//     another;
//   - chainID stops a binding signed for a testnet being replayed on mainnet;
//   - gnoAddr binds the Wesh identity to exactly one gno account, so a leaked
//     signature cannot be used to claim the identity from a different address;
//   - revision is monotonic, so an old, superseded binding cannot be replayed
//     to roll a rotation back.
//
// payload is the seed for a publicly published identity, or the seed
// commitment from [SeedCommitment] for one that keeps its rendezvous point off
// chain. The two are indistinguishable on the wire, which is deliberate: an
// observer cannot tell a committed identity from a published one without the
// realm's own mode flag.
//
// Fields are newline-framed and hex-encoded, never concatenated raw: with
// plain concatenation a different split of the same bytes would produce the
// same statement.
func BindStatement(chainID, gnoAddr string, accountPK, payload []byte, revision int) string {
	var b strings.Builder
	b.WriteString(kindBind)
	b.WriteString("\n")
	b.WriteString(chainID)
	b.WriteString("\n")
	b.WriteString(gnoAddr)
	b.WriteString("\n")
	b.WriteString(hex.EncodeToString(accountPK))
	b.WriteString("\n")
	b.WriteString(hex.EncodeToString(payload))
	b.WriteString("\n")
	b.WriteString(strconv.Itoa(revision))
	return b.String()
}

// DeviceStatement returns the canonical text an account signs to append one
// entry to its device sigchain.
//
// This is the piece the Wesh protocol has no answer for. Its own documentation
// says a device, once linked, can never be revoked: the account metadata log is
// append-only and no authority can mark an entry void. A chain cannot undo
// that (the ratchets are already out there and forward secrecy is a local
// property), but it can host the record that was missing, so a revocation
// becomes publicly visible, ordered, and attributable to the account key.
//
// prev is the digest of the preceding statement, or [GenesisDigest] for seq 0.
// Chaining each entry to its predecessor means the log cannot be reordered or
// have an entry quietly dropped: any gap changes every digest after it.
func DeviceStatement(chainID string, accountPK []byte, seq int, prev []byte, op string, devicePK []byte) string {
	var b strings.Builder
	b.WriteString(kindDevice)
	b.WriteString("\n")
	b.WriteString(chainID)
	b.WriteString("\n")
	b.WriteString(hex.EncodeToString(accountPK))
	b.WriteString("\n")
	b.WriteString(strconv.Itoa(seq))
	b.WriteString("\n")
	b.WriteString(hex.EncodeToString(prev))
	b.WriteString("\n")
	b.WriteString(op)
	b.WriteString("\n")
	b.WriteString(hex.EncodeToString(devicePK))
	return b.String()
}

// StatementDigest returns SHA-256 of a canonical statement. It is the value
// the next sigchain entry chains to.
func StatementDigest(statement string) []byte {
	sum := sha256.Sum256([]byte(statement))
	return sum[:]
}

// GenesisDigest is the all-zero digest that the first sigchain entry chains to.
func GenesisDigest() []byte { return make([]byte, DigestLen) }

// VerifyBind checks a binding signature against the account key.
func VerifyBind(chainID, gnoAddr string, accountPK, payload []byte, revision int, sig []byte) error {
	if len(accountPK) != AccountPKLen {
		return ErrBadAccountPKLen
	}
	stmt := BindStatement(chainID, gnoAddr, accountPK, payload, revision)
	if !ed25519.Verify(accountPK, []byte(stmt), sig) {
		return ErrBadSignature
	}
	return nil
}

// VerifyDevice checks a sigchain entry's shape and its signature, and returns
// the digest the next entry must chain to.
func VerifyDevice(chainID string, accountPK []byte, seq int, prev []byte, op string, devicePK, sig []byte) ([]byte, error) {
	if len(accountPK) != AccountPKLen {
		return nil, ErrBadAccountPKLen
	}
	if len(devicePK) != DevicePKLen {
		return nil, ErrBadDevicePKLen
	}
	if seq < 0 {
		return nil, ErrBadSeq
	}
	if len(prev) != DigestLen {
		return nil, ErrBadPrevLen
	}
	if !ValidOp(op) {
		return nil, ErrBadOp
	}
	stmt := DeviceStatement(chainID, accountPK, seq, prev, op, devicePK)
	if !ed25519.Verify(accountPK, []byte(stmt), sig) {
		return nil, ErrBadSignature
	}
	return StatementDigest(stmt), nil
}
