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
// one in a `maketx call` argument — only strings and numbers travel. The
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

var (
	Ownable = ownable.NewWithAddress(owner)

	candidates = avl.NewTree() // pkgpath -> Impl
	live       Impl
	livePath   string
)

// Propose nominates the calling realm. Called from the implementation's init,
// so deploying makes a candidate and nothing more.
func Propose(cur realm, impl Impl) {
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
	v := candidates.Get(pkgPath)
	if v == nil {
		panic("no candidate at " + pkgPath)
	}
	live, livePath = v.(Impl), pkgPath
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
	out := "adminreg/facade/v0\n"
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
