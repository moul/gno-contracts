// Package toolbox is the directory model behind
// [r/moul/toolbox](/r/moul/toolbox): a list of small gno.land utilities,
// each one a realm of its own, rendered as a single index.
//
// A tool is a [Tool]: a slug, the realm path that serves it, a title and one
// line of description. A [Catalog] holds them sorted by slug and answers the
// three questions a directory gets asked: what is here, what is this one, and
// what is tagged X.
//
// # Why a package and not just a realm
//
// The hub realm is `private = true`, which buys redeploy-in-place at a stable
// path and costs the ability to be imported at all: the type checker refuses
// any realm importing a private one (`ImportPrivateError`). So the hub cannot
// share a single line of code with its tools by importing them, and they
// cannot import it either. Everything both sides must agree about (what a tool
// entry looks like, how the index is rendered, how a query form is spelled)
// has to live in a `p/`, which is this one.
//
// # Nesting is checked on the base path, not on the full one
//
// [p/moul/nestedpkg](/p/moul/nestedpkg/v0) decides "is the caller below me" by
// prefixing one package path with the other. That is exactly right when
// neither path carries a version, which is the case for a private hub: it is
// redeployable, so its version could never increment and it does not carry
// one. It breaks the moment either side does, because
// `gno.land/r/moul/toolbox/usernames/v0` does not begin with
// `gno.land/r/moul/toolbox/v0`.
//
// [BasePath] removes a trailing `/vN` so the comparison is about the family
// rather than the version, and [IsUnder] and [SlugOf] are built on it. A hub
// and a tool may each be versioned or not, independently, and all four
// combinations answer the same.
//
// Live: [r/moul/toolbox](/r/moul/toolbox).
package toolbox

import (
	"errors"
	"strings"
)

// Errors a [Tool] or a [Catalog] returns. A /p/ package returns errors and
// lets the realm decide whether they are fatal; all of these are a mistake in
// the realm's own source rather than a value a user chose, so panicking on
// them is the normal handling.
var (
	// ErrEmptySlug is returned for a tool with no slug. The slug is the key
	// and the URL segment, so there is nothing to list it under.
	ErrEmptySlug = errors.New("toolbox: the slug is empty")

	// ErrBadSlug is returned for a slug carrying anything but lowercase
	// letters, digits and dashes. A slug travels in a URL path and in a
	// markdown link, and those are the characters that need no escaping in
	// either.
	ErrBadSlug = errors.New("toolbox: the slug has a character outside [a-z0-9-]")

	// ErrEmptyPath is returned for a tool with no package path. A directory
	// entry nobody can open is worse than no entry.
	ErrEmptyPath = errors.New("toolbox: the path is empty")

	// ErrEmptyTitle is returned for a tool with no title.
	ErrEmptyTitle = errors.New("toolbox: the title is empty")

	// ErrUnknownSlug is returned by [Catalog.Remove] for a slug it does not
	// hold.
	ErrUnknownSlug = errors.New("toolbox: no tool with that slug")
)

// Tool is one entry of the directory.
//
// Every field is a string or a slice of strings on purpose. A tool realm that
// registers itself into a public hub hands these values across a realm
// boundary, and a struct allocated by the caller would be the caller's object:
// persisting it panics with `cannot persist object from the private realm`
// when the caller is private. Scalars are copied, so the hub owns everything
// it stores whichever side built the entry.
type Tool struct {
	// Slug is the key, the URL segment and the sort order: "usernames".
	Slug string

	// Path is the package path serving the tool, with its version if it has
	// one: "gno.land/r/moul/toolbox/usernames".
	Path string

	// Title is the human name: "Usernames".
	Title string

	// Desc is one line about what the tool does. It is rendered inside a
	// table cell, so [Index] escapes it rather than trusting it.
	Desc string

	// Tags group tools in the index. Order is preserved as written.
	Tags []string
}

// Validate reports the first thing wrong with t, or nil.
func (t Tool) Validate() error {
	switch {
	case t.Slug == "":
		return ErrEmptySlug
	case !ValidSlug(t.Slug):
		return ErrBadSlug
	case t.Path == "":
		return ErrEmptyPath
	case t.Title == "":
		return ErrEmptyTitle
	}
	return nil
}

// HasTag reports whether t carries tag, compared exactly.
func (t Tool) HasTag(tag string) bool {
	for _, got := range t.Tags {
		if got == tag {
			return true
		}
	}
	return false
}

// URL is the gnoweb path of the tool, the package path with the chain domain
// removed: "/r/moul/toolbox/usernames".
//
// It is derived rather than stored so an entry cannot carry a link that
// disagrees with its own path.
func (t Tool) URL() string {
	if i := strings.Index(t.Path, "/"); i >= 0 && !strings.HasPrefix(t.Path, "/") {
		return t.Path[i:]
	}
	return t.Path
}

// ValidSlug reports whether s is a usable slug: non-empty, and lowercase
// letters, digits and dashes only.
//
// It is deliberately narrower than what a package path allows. A slug ends up
// in a URL and in markdown link syntax, and this is the set that survives both
// untouched, so nothing downstream has to escape it.
func ValidSlug(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z':
		case c >= '0' && c <= '9':
		case c == '-':
		default:
			return false
		}
	}
	return true
}

// BasePath returns pkgPath with a trailing version element removed:
// "gno.land/p/moul/toolbox/v0" becomes "gno.land/p/moul/toolbox".
//
// A path with no version element is returned unchanged, so calling it twice is
// the same as calling it once.
func BasePath(pkgPath string) string {
	i := strings.LastIndex(pkgPath, "/")
	if i < 0 {
		return pkgPath
	}
	if !isVersion(pkgPath[i+1:]) {
		return pkgPath
	}
	return pkgPath[:i]
}

// isVersion reports whether elem is a "vN" path element: a 'v' followed by at
// least one digit and nothing else.
func isVersion(elem string) bool {
	if len(elem) < 2 || elem[0] != 'v' {
		return false
	}
	for i := 1; i < len(elem); i++ {
		if elem[i] < '0' || elem[i] > '9' {
			return false
		}
	}
	return true
}

// IsUnder reports whether pkgPath is a tool of the hub at hubPath, ignoring
// both paths' versions.
//
// The hub itself is not under itself, and neither is a sibling whose name
// merely starts with the hub's: "toolboxtwo" is not under "toolbox", because
// the comparison is against the base plus a slash.
func IsUnder(hubPath, pkgPath string) bool {
	base := BasePath(hubPath)
	if base == "" {
		return false
	}
	return strings.HasPrefix(BasePath(pkgPath), base+"/")
}

// SlugOf returns the slug a tool at pkgPath would have under the hub at
// hubPath, or "" when pkgPath is not under it.
//
// A tool nested deeper than one element has no slug: the directory is one
// level by design, so "toolbox/a/b" is reported as not a tool rather than
// silently listed as "a".
func SlugOf(hubPath, pkgPath string) string {
	if !IsUnder(hubPath, pkgPath) {
		return ""
	}
	rest := strings.TrimPrefix(BasePath(pkgPath), BasePath(hubPath)+"/")
	if strings.Contains(rest, "/") {
		return ""
	}
	return rest
}
