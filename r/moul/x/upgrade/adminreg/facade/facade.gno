// untrusted-render: every path Render echoes was read off a crossing frame in
// Propose (cur.Previous().PkgPath(), which a caller cannot forge or type), and
// Accept can only promote a key that is already in that tree.
//
// Package facade is the permanent entry point of the "propose and accept"
// upgrade pattern (pattern F of the exploration; see ../../README.md).
//
// Pattern E lets a deploy take the realm over on the spot. This one splits that
// into two steps that different people can hold: an implementation realm
// NOMINATES itself from its own init, and the owner ACCEPTS a package path in a
// separate transaction. Nothing serves until both have happened.
//
// The split exists because of a mechanical limit, not just a governance
// preference. An implementation is an interface value, and a wallet cannot put
// one in a `maketx call` argument: only strings and numbers travel. The
// original shape of this pattern (the owner hands the facade an object) is
// therefore reachable only from `maketx run` or from another realm. Proposing
// from init and accepting by PATH makes both halves ordinary transactions.
package facade

import (
	"strings"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ownable/v0"
	"gno.land/p/nt/ufmt/v0"
)

const owner address = "g1manfred47kzduec920z88wfr64ylksmdcedlf5" // @moul

// prefix bounds who may even nominate itself. Accepting is still a separate,
// owner-gated decision.
const prefix = "gno.land/r/moul/x/upgrade/adminreg/impl/"

// Impl is the contract an implementation realm must satisfy.
type Impl interface {
	Greet(name string) string
	Version() string
}

// The stage ladder, copied in shape from Sui's UpgradeCap: compatible, additive,
// dependency-only, immutable, where a policy can only ever become MORE
// restrictive and make_immutable discards the cap. CosmWasm (a contract with no
// admin) and Solana (an upgrade authority set to None) reach the same place with
// one bit; the ladder is better because the interesting states are between
// "anything may take this over" and "nothing may ever change again".
//
// This pattern has an owner and a candidate list, so it has a middle rung the
// owner-less selfreg cannot express: no new code, but still free to roll back
// among what is already deployed.
//
// What the top rung does NOT do on its own: freezing this realm ends changes to
// the POINTER, not to the code behind it. A private implementation realm can be
// re-added at its own path, which would swap behaviour under a frozen facade.
// It holds here only because every implementation is public by construction:
// handing the facade its own object is exactly what forbids private (see
// ../../README.md).
const (
	StageOpen   = 0 // anything under the prefix may propose, the owner may accept any candidate
	StageClosed = 1 // no new candidates; the owner may still accept among those already proposed
	StageFrozen = 2 // nothing may be accepted again, whatever is live is final
)

var (
	Ownable = ownable.NewWithAddress(owner)

	stage = StageOpen

	candidates = avl.NewTree() // pkgpath -> Impl
	live       Impl
	livePath   string
)

// Propose nominates the calling realm. Called from the implementation's init,
// so deploying makes a candidate and nothing more.
func Propose(cur realm, impl Impl) {
	if stage != StageOpen {
		panic("adminreg/facade/v0 is " + StageName() + ", no new candidate may be proposed")
	}
	caller := cur.Previous().PkgPath()
	if !strings.HasPrefix(caller, prefix) {
		panic("unauthorized: " + caller + " is not under " + prefix)
	}
	if impl == nil {
		panic("implementation must not be nil")
	}
	candidates.Set(caller, impl)
}

// Accept promotes a proposed path to live. Owner-gated, and it takes a STRING,
// so it is callable straight from a wallet.
func Accept(cur realm, pkgPath string) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	if stage == StageFrozen {
		panic("adminreg/facade/v0 is frozen, " + livePath + " is final")
	}
	v := candidates.Get(pkgPath)
	if v == nil {
		panic("no candidate at " + pkgPath)
	}
	live, livePath = v.(Impl), pkgPath
}

// Close stops new candidates. The owner may still accept among those already
// proposed, so a rollback stays possible while new code does not.
func Close(cur realm) {
	tighten(cur, StageClosed)
}

// Freeze ends this realm's upgradeability, forever. There is no rung above it
// and nothing takes it back: that is the whole point, and it is the only way out
// of every caller trusting the owner rather than the code.
func Freeze(cur realm) {
	tighten(cur, StageFrozen)
}

// tighten is the ratchet. Owner-gated, and it refuses to loosen: the stage is
// the one piece of state here that a later owner cannot undo.
func tighten(cur realm, to int) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	if to <= stage {
		panic("the stage ladder only tightens, and this realm is already " + StageName())
	}
	stage = to
}

// Stage is the rung this realm is on. It only ever goes up.
func Stage() int {
	return stage
}

// StageName is Stage as the word a caller reads in Render.
func StageName() string {
	switch stage {
	case StageFrozen:
		return "frozen"
	case StageClosed:
		return "closed"
	default:
		return "open"
	}
}

// Live is the package path currently serving, or "" before the first Accept.
func Live() string {
	return livePath
}

// Candidates lists every path that has nominated itself, in order.
func Candidates() []string {
	out := []string{}
	candidates.Iterate("", "", func(k string, _ any) bool {
		out = append(out, k)
		return false
	})
	return out
}

// Greet forwards to the accepted implementation.
func Greet(name string) string {
	assertLive()
	return live.Greet(name)
}

// Version reports the accepted implementation's own version string.
func Version() string {
	assertLive()
	return live.Version()
}

func assertLive() {
	if live == nil {
		panic("no implementation accepted")
	}
}

func Render(_ string) string {
	out := ufmt.Sprintf("adminreg/facade/v0 [%s]\n", StageName())
	if live == nil {
		out += "live: none accepted\n"
	} else {
		out += ufmt.Sprintf("live: %s (%s)\n%s\n", live.Version(), livePath, live.Greet("world"))
	}
	out += ufmt.Sprintf("candidates: %d\n", candidates.Size())
	for _, p := range Candidates() {
		out += "- " + p + "\n"
	}
	return out
}
