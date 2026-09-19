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
// wants the implementation nested UNDER the facade's own path — and with the
// version segment last (facade/v0, impl/v0) no sibling is a sub-path of another.
// IsSameNamespace is the other shipped option and is far too loose: it would let
// any realm in the whole namespace seize this one. Hence an explicit prefix.
const prefix = "gno.land/r/moul/x/upgrade/selfreg/impl/"

var (
	live     Impl
	livePath string
)

// Register makes the calling realm the live implementation. Called from the
// implementation's own init, so deploying IS the upgrade.
func Register(cur realm, impl Impl) {
	caller := cur.Previous().PkgPath()
	if !strings.HasPrefix(caller, prefix) {
		panic("unauthorized: " + caller + " is not under " + prefix)
	}
	if impl == nil {
		panic("implementation must not be nil")
	}
	live, livePath = impl, caller
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
		return "selfreg/facade/v0: no implementation registered\n"
	}
	return ufmt.Sprintf("selfreg/facade/v0: %s (%s)\n%s\n", live.Version(), livePath, live.Greet("world"))
}
