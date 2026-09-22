// Package provable is an honest demonstration of what gno.land can and cannot
// prove about itself.
//
// It keeps a small append-only log in a Merkle mountain range and hands out
// inclusion proofs against the log's root. That part works, and it is the
// useful half: a realm can commit to a set and let anyone verify membership
// cheaply, with one native call.
//
// The other half is the point of the realm. A proof here says "this entry is
// consistent with the root this realm published". It cannot say "this root is
// the chain's own", because:
//
//  1. gno.land mounts two stores (gno.land/pkg/gnoland/app.go). The IAVL one
//     is merkleized and holds package source and account balances. The other
//     is a plain dbadapter whose Commit is documented as
//     "Always returns a zero commitID, as dbadapter store doesn't merkleize",
//     and THAT is where every realm's objects live. So no realm's state,
//     including this log, contributes anything to the app hash. There is no
//     state proof to produce.
//  2. chain/runtime exposes ChainID, ChainDomain, ChainHeight and
//     GetSessionInfo, and nothing else. No app hash, no block hash, no header.
//     So even given a Tendermint proof, a realm has no trusted root to check
//     it against.
//
// The one crack in the wall: an ESCAPED object, one referenced across realm
// boundaries, does get its hash written into the IAVL store
// (gnovm/pkg/gnolang/store.go). Cross-realm objects are therefore partially
// provable already. Nothing else is.
//
// Demo of gno.land/p/moul/x/merkle/v0 and gno.land/p/moul/x/mmr/v0.
package provable

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/merkle/v0"
	"gno.land/p/moul/x/mmr/v0"
)

const (
	// MaxEntries bounds the log. Unbounded append from an untrusted caller is
	// a storage-growth hazard even when the caller pays the deposit, and an
	// unbounded Render is a permanently unreadable page: the chain caps a
	// query at maxGasQuery, and a reader cannot raise it.
	MaxEntries = 512

	// MaxEntryLen bounds one entry.
	MaxEntryLen = 256

	// renderEntries is how many of the most recent entries Render lists, so
	// the page stays a fixed size no matter how full the log is.
	renderEntries = 10
)

var (
	log     = mmr.New()
	entries []string
)

func init() { seed() }

// Append adds an entry to the log and returns its index. The root moves, so
// every previously issued proof stops verifying against the new root: that is
// the nature of an append-only commitment, not a bug.
func Append(cur realm, entry string) int { return appendEntry(entry) }

func appendEntry(entry string) int {
	entry = strings.TrimSpace(entry)
	if entry == "" {
		panic("provable: empty entry")
	}
	if len(entry) > MaxEntryLen {
		panic("provable: entry longer than " + strconv.Itoa(MaxEntryLen) + " bytes")
	}
	if len(entries) >= MaxEntries {
		panic("provable: log is full at " + strconv.Itoa(MaxEntries) + " entries")
	}
	entries = append(entries, entry)
	return log.Append([]byte(entry))
}

// Size returns the number of entries.
func Size() int { return log.Size() }

// Root returns the current log root, hex-encoded. It is also the Tendermint
// simple-tree root over the same entries, so any Tendermint verifier accepts
// it.
func Root() string { return log.RootHex() }

// Entry returns the entry at index.
func Entry(index int) string {
	mustRange(index)
	return entries[index]
}

// ProofOf returns the inclusion proof for index, as the three comma-separated
// hex lists Verify expects.
func ProofOf(index int) (path, before, after string) {
	mustRange(index)
	p, err := log.Proof(index)
	if err != nil {
		panic("provable: " + err.Error())
	}
	return p.Hex()
}

// Verify checks a proof against a root the caller supplies, which is the
// honest signature: the realm is a verifier, not an oracle. Pass Root() to
// check against the live log.
func Verify(root string, index, total int, entry, path, before, after string) bool {
	rb, err := hexHash(root)
	if err != nil {
		return false
	}
	p, err := mmr.ParseProof(index, total, path, before, after)
	if err != nil {
		return false
	}
	return mmr.Verify(rb, []byte(entry), p)
}

// VerifyFixed checks a Tendermint simple-tree proof, the fixed-leaf-set
// encoding, against a root the caller supplies. Same tree as the log, a
// different proof shape: siblings are one flat list, leaf first.
//
// Both encodings verify against the same root, because the Tendermint tree and
// a right-bagged mountain range are the same structure.
func VerifyFixed(root string, index, total int, leaf, siblings string) bool {
	rb, err := hexHash(root)
	if err != nil {
		return false
	}
	p, err := merkle.ParseProof(index, total, siblings)
	if err != nil {
		return false
	}
	return p.Verify(rb, []byte(leaf))
}

func mustRange(index int) {
	if index < 0 || index >= len(entries) {
		panic("provable: index out of range")
	}
}

func hexHash(s string) ([]byte, error) {
	p, err := merkle.ParseProof(0, 1, strings.TrimSpace(s))
	if err != nil {
		return nil, err
	}
	if len(p.Siblings) != 1 {
		return nil, merkle.ErrBadHashSize
	}
	return p.Siblings[0], nil
}

// seed returns the realm to its deployed state: an empty log plus the three
// demo entries, so a fresh deployment renders something and so the example
// tests have a fixed starting point.
//
// Realm globals persist across a whole test binary and examples run after
// every Test, so a pinned Render must call this first.
func seed() {
	log = mmr.New()
	entries = nil
	appendEntry("genesis of this log")
	appendEntry("a second commitment")
	appendEntry("a third commitment")
}
