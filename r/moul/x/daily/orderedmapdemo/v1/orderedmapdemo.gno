// Package orderedmapdemo is a small gnoweb demo of the insertion-ordered map
// provided by the [p/moul/x/daily/orderedmap](/p/moul/x/daily/orderedmap/v1)
// library: it shows that order survives updates and deletes.
//
// It contains no map logic of its own. Stateless, so Render is deterministic —
// which is precisely what the library is for.
package orderedmapdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/orderedmap/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Ordered Map\n\n")
	b.WriteString("A map that remembers insertion order, demoing the ")
	b.WriteString("[`p/moul/x/daily/orderedmap`](/p/moul/x/daily/orderedmap/v1) library.\n\n")

	o := orderedmap.New()
	for _, kv := range [][2]string{{"delta", "4"}, {"alpha", "1"}, {"charlie", "3"}, {"bravo", "2"}} {
		o.Set(kv[0], kv[1])
	}

	b.WriteString("## Inserted\n\n")
	b.WriteString("`delta, alpha, charlie, bravo` → order kept as inserted, **not** sorted:\n\n")
	b.WriteString(table(o))

	o.Set("alpha", "99")
	b.WriteString("\n## After `Set(\"alpha\", \"99\")`\n\n")
	b.WriteString("Updating keeps the original position — insertion order means *first* insertion:\n\n")
	b.WriteString(table(o))

	o.Delete("charlie")
	o.Set("charlie", "new")
	b.WriteString("\n## After deleting and re-adding `charlie`\n\n")
	b.WriteString("Re-inserting is a **new** insertion, so it goes last:\n\n")
	b.WriteString(table(o))

	b.WriteString("\n> gno map iteration order is unspecified. A realm that ranges over a ")
	b.WriteString("built-in map to build its page can emit a different page every call — ")
	b.WriteString("a consensus bug, not a cosmetic one. This is the fix.\n")
	return b.String()
}

func table(o *orderedmap.OrderedMap) string {
	var b strings.Builder
	b.WriteString("| # | key | value |\n|---|---|---|\n")
	i := 0
	o.Iterate(func(k, v string) bool {
		i++
		b.WriteString("| ")
		b.WriteString(strconv.Itoa(i))
		b.WriteString(" | `")
		b.WriteString(k)
		b.WriteString("` | `")
		b.WriteString(v)
		b.WriteString("` |\n")
		return false
	})
	return b.String()
}
