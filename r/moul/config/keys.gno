package config

import (
	"strings"

	"chain/runtime"
	"chain/runtime/unsafe"
)

// The key grammar.
//
// A key is a NAME, optionally followed by "@" and a SCOPE:
//
//	pause                  applies to every realm that asks
//	pause@r/moul/home      applies to that realm only
//
// The scope is a package path with the chain domain stripped, because the
// domain is the same for every realm reading this one and repeating it in a
// few dozen keys buys nothing but storage.
//
// Two settings therefore answer every scoped question, and each reader decides
// how they combine: pause takes the stricter of the two (pausable.Strictest),
// while the notice blocks show both. That choice belongs to the reader and not
// here, because "stricter wins" and "show both" are both right, for different
// settings.
const (
	// ScopeSep separates a name from the realm it applies to. "@" and not "."
	// so a scope can never be mistaken for a longer name, and not ":" because
	// gno realm render paths already use that.
	ScopeSep = "@"

	maxNameLen  = 64
	maxScopeLen = 128
)

// realmPath is this realm's own path, including its version. Stated once so
// the page can link to itself and the proxy check can recognise a sibling
// version without either restating the string.
const realmPath = "gno.land/r/moul/config/v1"

// validName reports whether name is a legal setting name: 1..maxNameLen bytes
// of [a-z0-9._-]. The dot is the namespace separator ("block.top"), lowercase
// only so a setting has exactly one name, and no whitespace so a name
// round-trips through Manifest's tab-separated lines.
func validName(name string) bool {
	if len(name) == 0 || len(name) > maxNameLen {
		return false
	}
	for i := 0; i < len(name); i++ {
		c := name[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		case c == '-', c == '_', c == '.':
		default:
			return false
		}
	}
	return true
}

// validScope reports whether scope is shaped like a package path with the
// domain stripped: 1..maxScopeLen bytes of [a-z0-9._/-], no empty segment.
func validScope(scope string) bool {
	if len(scope) == 0 || len(scope) > maxScopeLen {
		return false
	}
	lastSlash := true // a leading slash would be an empty first segment
	for i := 0; i < len(scope); i++ {
		c := scope[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
			lastSlash = false
		case c == '-', c == '_', c == '.':
			lastSlash = false
		case c == '/':
			if lastSlash {
				return false
			}
			lastSlash = true
		default:
			return false
		}
	}
	return !lastSlash
}

// validKey reports whether key is a legal name, or a legal name and scope
// joined by ScopeSep.
func validKey(key string) bool {
	name, scope := SplitKey(key)
	if scope == "" {
		return !strings.Contains(key, ScopeSep) && validName(name)
	}
	return validName(name) && validScope(scope)
}

// SplitKey takes a key apart. An unscoped key returns an empty scope, and so
// does a malformed one: callers pair this with validKey rather than trusting
// the split.
func SplitKey(key string) (name, scope string) {
	i := strings.Index(key, ScopeSep)
	if i < 0 {
		return key, ""
	}
	return key[:i], key[i+1:]
}

// Scope turns a package path into the scope half of a key, stripping the chain
// domain: "gno.land/r/moul/home" and "r/moul/home" both give "r/moul/home".
//
// A path that is not shaped like one comes back empty, and every caller here
// treats that as "no scope", falling back to the global setting rather than
// inventing a key nobody can type.
//
// The chain domain is tried first and the literal "gno.land/" second, so a key
// written on one chain still resolves on another whose domain differs. Twin of
// mygnoscan.TrimDomain, which answers the same question for a URL and is
// stricter about the characters, because its output lands inside a link.
func Scope(pkgPath string) string {
	s := strings.TrimPrefix(pkgPath, runtime.ChainDomain()+"/")
	s = strings.TrimPrefix(s, "gno.land/")
	s = strings.Trim(s, "/")
	if !validScope(s) {
		return ""
	}
	return s
}

// KeyFor builds the scoped key for a setting on one realm, and returns the
// bare name when pkgPath names no realm this can scope to.
//
// This is what a realm should render when it wants to tell a manager which
// setting to change, so the command in the page is the command that works.
func KeyFor(name, pkgPath string) string {
	scope := Scope(pkgPath)
	if scope == "" {
		return name
	}
	return name + ScopeSep + scope
}

// caller is the package path of the realm that called into this one.
//
// Every exported function here that uses it is a plain read with no `cur realm`
// parameter, so it can only ever be BORROWED: gno runs it without opening a
// realm frame, and unsafe.CurrentRealm() therefore reports the borrower. That
// is what makes the zero-argument helpers (TopBlock, IsPaused, …) able to name
// their caller at all.
//
// Measured in the test harness on 2026-09-22: a call from a code realm at
// gno.land/r/test/caller reports CurrentRealm=gno.land/r/test/caller and
// PreviousRealm=gno.land/r/moul/config/v1.
//
// The moment one of these grows a `cur realm` parameter this stops being true
// and starts reporting this realm instead. Do not add one. Anything that needs
// a realm frame takes the path explicitly, which is what the …For variants are.
func caller() string { return unsafe.CurrentRealm().PkgPath() }

// scopedPair reads both halves of a scoped setting: the global one and the one
// for pkgPath, either of which may be empty.
func scopedPair(name, pkgPath string) (global, scoped string) {
	global = Get(name)
	if scope := Scope(pkgPath); scope != "" {
		scoped = Get(name + ScopeSep + scope)
	}
	return global, scoped
}
