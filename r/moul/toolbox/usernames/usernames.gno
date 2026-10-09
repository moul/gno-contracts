// Package usernames is the toolbox tool for gno.land identities: it turns a
// username into an address, an address into a username, and tells you which
// of the two you are actually holding.
//
// It is the page form of
//
//	gnokey query vm/qeval --data 'gno.land/r/sys/users.ResolveName("akkadia")' -remote https://rpc.gno.land
//
// with the three things that query does not tell you: whether the name you
// asked about is the user's CURRENT name or an alias they renamed away from,
// what canonical key it collapses to, and whether a lookalike of it is already
// taken.
//
// # Why not r/sys/users.ResolveAny
//
// `ResolveAny` returns `(*UserData, bool)` and the bool does not mean "found".
// For an input that parses as an address it returns `(ResolveAddress(addr),
// true)` whatever the lookup produced, so an unregistered address comes back
// as `(nil, true)`. Every caller that reads the bool and dereferences the
// pointer panics on the first address nobody claimed. [lookup] branches on the
// input itself and checks the pointer instead.
//
// Part of [r/moul/toolbox](/r/moul/toolbox/v0).
package usernames

import "gno.land/r/sys/users"

// lookup resolves any input to a user record, or nil.
//
// An input that parses as a gno.land address is only ever looked up as an
// address, and anything else only as a name: a bech32 address is not a legal
// username, so trying both would only widen what a typo can hit.
func lookup(input string) *users.UserData {
	if input == "" {
		return nil
	}
	if addr := address(input); addr.IsValid() {
		return users.ResolveAddress(addr)
	}
	data, _ := users.ResolveName(input)
	return data
}

// Resolve returns the current username and the address behind any input, a
// username or a `g1` address.
//
// found is false when nobody holds it, which is also the answer for a deleted
// user: `r/sys/users` keeps the tombstone and resolves it to nothing.
//
//	gnokey query vm/qeval -data 'gno.land/r/moul/toolbox/usernames/v0.Resolve("moul")'
func Resolve(input string) (name string, addr string, found bool) {
	data := lookup(input)
	if data == nil {
		return "", "", false
	}
	return data.Name(), data.Addr().String(), true
}

// AddressOf returns the address behind a username or an address, or "" when
// nobody holds it.
//
// It is the call another realm would want, and the one it cannot have: this
// realm is `private = true`, so nothing can import it. Over `vm/qeval` it is
// the whole point.
//
//	gnokey query vm/qeval -data 'gno.land/r/moul/toolbox/usernames/v0.AddressOf("moul")'
func AddressOf(input string) string {
	_, addr, found := Resolve(input)
	if !found {
		return ""
	}
	return addr
}

// NameOf returns the current username behind a username or an address, or ""
// when nobody holds it.
func NameOf(input string) string {
	name, _, found := Resolve(input)
	if !found {
		return ""
	}
	return name
}

// Display returns what a page should print for an input: the username when
// there is one, and the input unchanged when there is not.
//
// It never returns "", which is what makes it usable inline: a caller that has
// to check for an empty string would have called [NameOf].
func Display(input string) string {
	if name := NameOf(input); name != "" {
		return "@" + name
	}
	return input
}

// CurrentName reports the user's current name when input is an alias they
// renamed away from, and "" otherwise.
//
// `r/sys/users` keeps old names resolving on purpose, so an address looked up
// by a name that is no longer current is not an error and nothing in the
// resolve result says so. This is the one call that does.
func CurrentName(input string) string {
	if input == "" {
		return ""
	}
	if addr := address(input); addr.IsValid() {
		return ""
	}
	data, isCurrent := users.ResolveName(input)
	if data == nil || isCurrent {
		return ""
	}
	return data.Name()
}

// Canonical returns the canonical key a name collapses to. Two names with the
// same canonical form cannot both be registered, which is how `r/sys/users`
// refuses a lookalike of an existing account.
//
//	gnokey query vm/qeval -data 'gno.land/r/moul/toolbox/usernames/v0.Canonical("M0ul")'
func Canonical(name string) string { return users.Canonicalize(name) }

// Taken reports whether the exact name is registered, including names that
// were deleted or renamed away from: it answers "would registering this
// fail", not "is somebody using this".
func Taken(name string) bool {
	if name == "" {
		return false
	}
	return users.IsNameTaken(name)
}

// CanonicalOwner returns the name that already holds this name's canonical
// key, or "" when the key is free. A non-empty answer that is not the name
// itself is a lookalike collision.
func CanonicalOwner(name string) string {
	if name == "" {
		return ""
	}
	existing, taken := users.IsCanonicalTaken(name)
	if !taken {
		return ""
	}
	return existing
}
