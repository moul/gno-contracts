package config

import (
	"strings"

	"chain"

	"gno.land/p/nt/avl/v0"
)

// Version chaining: how v2 and v3 get built without splitting the state.
//
// # The shape, and why it is this way round
//
// This realm is public, so its path is permanent and a new API means a new
// version at a new path. Left alone, that fragments everything: a realm
// importing v1 and a realm importing v2 would read two different member lists
// and two different pause switches, and the second one to be written would win
// for half the callers.
//
// Delegation fixes it, and it can only run one way. A version can import the
// versions that already existed when it was written; it can never import one
// that does not exist yet. So the STATE STAYS IN THE OLDEST version that has
// it, and every later version is a thin relay in front:
//
//	v3  ->  v2  ->  v1        (this one: the root, and where everything lives)
//
// A realm importing v1, v2 or v3 is then reading the same settings, the same
// pause and the same managers, whichever door it came through. That is the
// property worth all of this.
//
// v0 cannot take part: it is already on chain and has no settings store at
// all. It keeps answering for its own member list and nothing else.
//
// # Writing v2
//
// v2 imports this package, holds no state of its own, and for each write it
// exposes, calls SetAs or UnsetAs with the address it was called by:
//
//	func Set(cur realm, key, value string) {
//		config.SetAs(cross(cur), cur.Previous().Address(), key, value)
//	}
//
// Reads need none of this. They are plain borrowed calls, so v2 just forwards:
//
//	func Get(key string) string { return config.Get(key) }
//
// Then, once, from a manager's address:
//
//	AllowProxy gno.land/r/moul/config/v2
//
// # What a proxy is trusted with, exactly
//
// A registered proxy is trusted to say WHO is asking, not to decide whether
// they may. SetAs still puts the principal through the Authorizer, so the
// member list stays the single answer to "who may change config" for every
// version at once, and adding a manager here works through v2 and v3 with no
// further deploys.
//
// It is not a security boundary against the proxy's own code: a proxy that
// lies about its principal writes whatever it likes. It does not have to be,
// because the same person deploys both and registering one is a deliberate,
// revocable act. What it buys is that v2 never carries a copy of the member
// list, so the two can never disagree.

// proxies holds the package paths allowed to relay, keyed by path, valued by
// the address that path resolves to. The address is what an incoming call is
// actually compared against; the path is stored so Render and ListProxies can
// show something a human recognises.
var proxies = avl.NewTree() // pkgPath -> address

// AllowProxy registers a newer version of this realm as a relay. Manager only.
//
// It takes a package path rather than an address because a path is what a
// manager can check by eye; the address is derived here with the same function
// the chain uses, so the two cannot drift.
func AllowProxy(cur realm, pkgPath string) {
	assertProxyPath(pkgPath)
	assertAuthorized(cur, "config.AllowProxy:"+pkgPath)

	proxies.Set(pkgPath, chain.PackageAddress(pkgPath))
	settingsRev++
	chain.Emit("ConfigAllowProxy", "path", pkgPath,
		"address", chain.PackageAddress(pkgPath).String())
}

// RevokeProxy withdraws a relay. Manager only.
//
// Revoking one that was never registered aborts rather than passing quietly:
// at this point in an incident, "done" and "you misspelled it" must not look
// the same.
func RevokeProxy(cur realm, pkgPath string) {
	assertProxyPath(pkgPath)
	assertAuthorized(cur, "config.RevokeProxy:"+pkgPath)

	if _, removed := proxies.Remove(pkgPath); !removed {
		panic("no such proxy: " + pkgPath)
	}
	settingsRev++
	chain.Emit("ConfigRevokeProxy", "path", pkgPath)
}

// IsProxy reports whether addr is a registered relay.
func IsProxy(addr address) bool {
	if addr == "" {
		return false
	}
	found := false
	proxies.Iterate("", "", func(_ string, value any) bool {
		if value.(address) == addr {
			found = true
			return true // stop
		}
		return false
	})
	return found
}

// ListProxies returns the registered relay paths, in sorted order.
func ListProxies() []string {
	out := []string{}
	proxies.Iterate("", "", func(key string, _ any) bool {
		out = append(out, key)
		return false
	})
	return out
}

// SetAs is Set, performed by a registered proxy on behalf of principal.
//
// Two checks, and both have to hold: the caller is a registered relay, and the
// principal it names is authorized. Neither is redundant. Dropping the first
// would let any realm claim any principal; dropping the second would make a
// registered proxy an unconditional bypass of the member list.
func SetAs(cur realm, principal address, key, value string) {
	assertRelay(cur)
	assertWritableKey(key)
	assertValue(key, value)
	assertPrincipal(principal, "config.Set:"+key)
	writeSetting(key, value)
}

// UnsetAs is Unset, performed by a registered proxy on behalf of principal.
func UnsetAs(cur realm, principal address, key string) {
	assertRelay(cur)
	assertWritableKey(key)
	assertPrincipal(principal, "config.Unset:"+key)
	removeSetting(key)
}

// assertRelay aborts unless the immediate caller is a registered proxy.
func assertRelay(cur realm) {
	from := cur.Previous().Address()
	if !IsProxy(from) {
		panic("not a registered proxy: " + from.String())
	}
}

// assertPrincipal puts an address through the Authorizer without it being the
// caller, which is what a relay needs and what DoByPrevious cannot express.
//
// With the default MemberAuthority this is a membership test. With an
// authority that inspects the caller instead (a ContractAuthority), the
// relayed path asks that authority about the principal, so check what it does
// before transferring management while a proxy is registered.
func assertPrincipal(principal address, title string) {
	if principal == "" {
		panic("unauthorized: no principal")
	}
	allowed := false
	err := Authorizer.Authority().Authorize(principal, title, func() error {
		allowed = true
		return nil
	})
	if err != nil {
		panic("unauthorized: " + err.Error())
	}
	if !allowed {
		panic("unauthorized")
	}
}

// assertProxyPath refuses anything that is not a realm path under this
// namespace. A proxy is by definition a later version of this realm, so
// nothing else should ever be registered, and the narrow check turns a
// fat-fingered AllowProxy into an abort rather than a standing grant to an
// unrelated realm.
func assertProxyPath(pkgPath string) {
	const want = "gno.land/r/moul/config/v"
	if !strings.HasPrefix(pkgPath, want) {
		panic("a proxy must be a later version of this realm, got " + pkgPath)
	}
	rest := strings.TrimPrefix(pkgPath, want)
	if rest == "" || !isDigits(rest) {
		panic("a proxy must be a later version of this realm, got " + pkgPath)
	}
}

func isDigits(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return len(s) > 0
}
