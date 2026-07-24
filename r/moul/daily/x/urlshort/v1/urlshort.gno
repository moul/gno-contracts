// Package urlshort is a simple on-chain URL alias registry.
//
// Callers register an `alias -> url` mapping they own. An alias can only be
// claimed once; the owner may later update the target URL, but nobody else can
// overwrite an alias they do not own. A per-alias click counter is bumped every
// time the alias is resolved through Render("/<alias>").
package urlshort

import (
	"strings"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// entry is the persisted record for a single alias.
type entry struct {
	url    string
	owner  address
	note   string
	clicks int
}

// aliases maps alias (string) -> *entry, kept in an avl.Tree for deterministic
// iteration order in Render.
var aliases avl.Tree

// isAlphanumeric reports whether s is non-empty and made only of [0-9A-Za-z].
func isAlphanumeric(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		switch {
		case c >= '0' && c <= '9':
		case c >= 'a' && c <= 'z':
		case c >= 'A' && c <= 'Z':
		default:
			return false
		}
	}
	return true
}

// Shorten registers `alias -> url` owned by the caller.
//
// Rules:
//   - alias must be non-empty and alphanumeric;
//   - url must be non-empty;
//   - if the alias is unclaimed, it is created owned by the caller;
//   - if it is already claimed by the caller, the url/note are updated;
//   - if it is claimed by someone else, the call aborts.
func Shorten(cur realm, alias string, url string, note string) {
	if !isAlphanumeric(alias) {
		panic("alias must be non-empty and alphanumeric")
	}
	if url == "" {
		panic("url must be non-empty")
	}

	caller := unsafe.PreviousRealm().Address()

	if v, ok := aliases.Get(alias); ok {
		e := v.(*entry)
		if e.owner != caller {
			panic("alias already taken by another owner")
		}
		e.url = url
		e.note = note
		chain.Emit("AliasUpdated", "alias", alias, "owner", caller.String())
		return
	}

	e := &entry{url: url, owner: caller, note: note, clicks: 0}
	aliases.Set(alias, e)
	chain.Emit("AliasCreated", "alias", alias, "owner", caller.String())
}

// Remove deletes an alias owned by the caller. Aborts if the alias does not
// exist or the caller is not the owner.
func Remove(cur realm, alias string) {
	v, ok := aliases.Get(alias)
	if !ok {
		panic("alias not found")
	}
	e := v.(*entry)
	caller := unsafe.PreviousRealm().Address()
	if e.owner != caller {
		panic("only the owner can remove an alias")
	}
	aliases.Remove(alias)
	chain.Emit("AliasRemoved", "alias", alias, "owner", caller.String())
}

// Lookup returns the target url for an alias and whether it exists. It is a
// read-only helper and does NOT increment the click counter.
func Lookup(alias string) (string, bool) {
	v, ok := aliases.Get(alias)
	if !ok {
		return "", false
	}
	return v.(*entry).url, true
}

// Render renders Markdown. The root path lists every alias; "/<alias>" shows a
// single alias detail and bumps its click counter.
func Render(path string) string {
	if path == "" || path == "/" {
		return renderIndex()
	}

	alias := strings.TrimPrefix(path, "/")
	v, ok := aliases.Get(alias)
	if !ok {
		return "# URL Shortener\n\nNo alias named `" + alias + "`.\n\n[← all aliases](/)\n"
	}

	e := v.(*entry)
	e.clicks++

	var b strings.Builder
	b.WriteString("# 🔗 " + alias + "\n\n")
	b.WriteString("**Target:** <" + e.url + ">\n\n")
	b.WriteString("**Owner:** " + e.owner.String() + "\n\n")
	if e.note != "" {
		b.WriteString("**Note:** " + e.note + "\n\n")
	}
	b.WriteString("**Clicks:** " + itoa(e.clicks) + "\n\n")
	b.WriteString("[← all aliases](/)\n")
	return b.String()
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# 🔗 URL Shortener\n\n")

	if aliases.Size() == 0 {
		b.WriteString("_No aliases registered yet._\n\n")
		b.WriteString("Call `Shorten(alias, url, note)` to register one.\n")
		return b.String()
	}

	b.WriteString("| Alias | Target | Owner | Clicks |\n")
	b.WriteString("|-------|--------|-------|--------|\n")
	aliases.Iterate("", "", func(key string, value interface{}) bool {
		e := value.(*entry)
		b.WriteString("| [" + key + "](/" + key + ") | <" + e.url + "> | " +
			short(e.owner.String()) + " | " + itoa(e.clicks) + " |\n")
		return false
	})
	b.WriteString("\nTotal aliases: " + itoa(aliases.Size()) + "\n")
	return b.String()
}

// short truncates a long address for the index table.
func short(s string) string {
	if len(s) <= 12 {
		return s
	}
	return s[:6] + "…" + s[len(s)-4:]
}

// itoa converts a non-negative int to its decimal string without importing
// strconv (kept minimal & deterministic).
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
