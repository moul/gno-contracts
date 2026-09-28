// Package facade is the permanent entry point of the "self-registering
// implementation" upgrade pattern (pattern E of the exploration; see
// ../../README.md).
//
// The path callers import never changes and holds no business logic: it holds
// an interface value. A new implementation realm takes over simply by being
// deployed, because it registers itself from its own init. Nobody has to send
// a transaction to switch, which is the pattern's whole appeal and also its
// whole risk: whoever can deploy under the guarded prefix can take the realm.
package facade

import (
	"strings"

	"gno.land/p/nt/ufmt/v0"
)

// Impl is the contract an implementation realm must satisfy. This interface is
// the one thing here that can never change: it is compiled into every caller.
type Impl interface {
	Greet(name string) string
	Version() string
}

// prefix is the only gate. An implementation must live under it.
//
// gno ships p/nt/nestedpkg/v0 for exactly this check, but its AssertCallerIsSubPath
// wants the implementation nested UNDER the facade's own path, and with the
// version segment last (facade/v0, impl/v0) no sibling is a sub-path of another.
// IsSameNamespace is the other shipped option and is far too loose: it would let
// any realm in the whole namespace seize this one. Hence an explicit prefix.
const prefix = "gno.land/r/moul/x/upgrade/selfreg/impl/"

// The stage ladder. Sui gates package upgrades with an UpgradeCap whose policy
// runs compatible, additive, dependency-only, immutable, and the rule that makes
// it worth copying is that a policy can only ever become MORE restrictive.
// CosmWasm and Solana land on the same primitive from different directions: a
// contract with no admin, a program whose upgrade authority is None. All three
// say the same thing, that the way out of "you are trusting the owner rather
// than the code" is an authority you can drop, permanently.
//
// This pattern has no owner, so its ladder has two rungs rather than four: the
// only actor the facade already trusts is whichever implementation is live.
const (
	StageOpen   = 0 // any realm under the prefix takes over by deploying
	StageSealed = 1 // nothing may register again, the live implementation is final
)

var (
	live     Impl
	livePath string
	stage    = StageOpen
)

// Register makes the calling realm the live implementation. Called from the
// implementation's own init, so deploying IS the upgrade.
func Register(cur realm, impl Impl) {
	if stage != StageOpen {
		panic("selfreg/facade/v0 is sealed, " + livePath + " is final")
	}
	caller := cur.Previous().PkgPath()
	if !strings.HasPrefix(caller, prefix) {
		panic("unauthorized: " + caller + " is not under " + prefix)
	}
	if impl == nil {
		panic("implementation must not be nil")
	}
	live, livePath = impl, caller
}

// Seal ends this realm's upgradeability, forever. Callable only by the
// implementation currently serving, because with no owner that is the only
// actor the facade already trusts. It grants nothing new: whoever could deploy
// under the prefix could already take the realm over, and this only lets them
// make that the last word.
//
// One-way, and there is no rung above it.
func Seal(cur realm) {
	caller := cur.Previous().PkgPath()
	if livePath == "" || caller != livePath {
		panic("unauthorized: only the live implementation may seal, and that is " + livePath)
	}
	stage = StageSealed
}

// Stage is the rung this realm is on. It only ever goes up.
func Stage() int {
	return stage
}

// StageName is Stage as the word a caller reads in Render.
func StageName() string {
	if stage == StageSealed {
		return "sealed"
	}
	return "open"
}

// Live is the package path currently serving, or "" before the first deploy.
func Live() string {
	return livePath
}

// Greet forwards to the live implementation.
func Greet(name string) string {
	assertLive()
	return live.Greet(name)
}

// Version reports the live implementation's own version string.
func Version() string {
	assertLive()
	return live.Version()
}

func assertLive() {
	if live == nil {
		panic("no implementation registered")
	}
}

func Render(_ string) string {
	if live == nil {
		return ufmt.Sprintf("selfreg/facade/v0 [%s]: no implementation registered\n", StageName())
	}
	return ufmt.Sprintf("selfreg/facade/v0 [%s]: %s (%s)\n%s\n", StageName(), live.Version(), livePath, live.Greet("world"))
}
