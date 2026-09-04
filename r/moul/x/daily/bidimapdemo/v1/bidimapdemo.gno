// Package bidimapdemo is a small gnoweb demo of the bidirectional map provided
// by the [p/moul/x/daily/bidimap](/p/moul/x/daily/bidimap/v1) library: it shows
// the reverse lookup and what happens when a binding is displaced.
//
// It contains no map logic of its own. Stateless, so Render is deterministic —
// which is precisely what the library is for.
package bidimapdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/bidimap/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Bidirectional Map\n\n")
	b.WriteString("Unique in both directions, demoing the ")
	b.WriteString("[`p/moul/x/daily/bidimap`](/p/moul/x/daily/bidimap/v1) library.\n\n")

	m := bidimap.New()
	m.Put("alice", "admin")
	m.Put("bob", "auditor")
	m.Put("carol", "treasurer")

	b.WriteString("## Roles\n\n")
	b.WriteString(table(m))

	b.WriteString("\n## Both directions are O(1)\n\n")
	v, _ := m.Get("bob")
	k, _ := m.GetKey("treasurer")
	b.WriteString("- `Get(\"bob\")` → `" + v + "`\n")
	b.WriteString("- `GetKey(\"treasurer\")` → `" + k + "` — the reverse index, not a scan\n\n")

	b.WriteString("## Displacing a binding\n\n")
	b.WriteString("Both sides are unique, so giving `alice` the `auditor` role cannot ")
	b.WriteString("simply be written — `bob` already holds it, and `alice` already holds ")
	b.WriteString("`admin`. `Put` **replaces**, and reports what it displaced:\n\n")
	evicted, _ := m.Put("alice", "auditor")
	b.WriteString("| displaced key | displaced value |\n|---|---|\n")
	for _, p := range evicted {
		b.WriteString("| `" + p[0] + "` | `" + p[1] + "` |\n")
	}
	b.WriteString("\n" + table(m))
	b.WriteString("\n`bob` is now unassigned and the `admin` role is vacant — one call, ")
	b.WriteString("both indexes still agreeing.\n\n")

	b.WriteString("## Refusing instead\n\n")
	b.WriteString("`PutUnique` makes the other choice: it declines rather than displace.\n\n")
	ok := m.PutUnique("dave", "auditor")
	b.WriteString("- `PutUnique(\"dave\", \"auditor\")` → `" + strconv.FormatBool(ok) + "` — the role is taken\n")
	ok = m.PutUnique("dave", "secretary")
	b.WriteString("- `PutUnique(\"dave\", \"secretary\")` → `" + strconv.FormatBool(ok) + "` — both sides free\n\n")
	b.WriteString(table(m))

	b.WriteString("\n> Keys come back **sorted**, never in map order: gno map iteration ")
	b.WriteString("order is unspecified, and a page built from one can differ between ")
	b.WriteString("nodes — a consensus bug, not a cosmetic one.\n")
	return b.String()
}

func table(m *bidimap.BiMap) string {
	var b strings.Builder
	b.WriteString("| person | role |\n|---|---|\n")
	m.Iterate(func(k, v string) bool {
		b.WriteString("| `" + k + "` | `" + v + "` |\n")
		return false
	})
	return b.String()
}
