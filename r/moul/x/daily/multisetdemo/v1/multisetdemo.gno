// Package multisetdemo is a small gnoweb demo of the bag / frequency counter
// provided by the [p/moul/x/daily/multiset](/p/moul/x/daily/multiset/v1)
// library: word frequencies, ranking, and multiset algebra.
//
// It contains no counting logic of its own. Stateless, so Render is
// deterministic — which is precisely what the library is for.
package multisetdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/multiset/v1"
)

const sample = "the quick brown fox jumps over the lazy dog the fox barks and the dog barks"

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Multiset\n\n")
	b.WriteString("A bag that counts duplicates, demoing the ")
	b.WriteString("[`p/moul/x/daily/multiset`](/p/moul/x/daily/multiset/v1) library.\n\n")

	m := multiset.FromSlice(strings.Split(sample, " "))

	b.WriteString("## Word frequencies\n\n")
	b.WriteString("> " + sample + "\n\n")
	b.WriteString("`" + strconv.Itoa(m.Total()) + "` words, `")
	b.WriteString(strconv.Itoa(m.Distinct()) + "` distinct.\n\n")

	b.WriteString("## `MostCommon(5)`\n\n")
	b.WriteString("| rank | word | count |\n|---|---|---|\n")
	for i, e := range m.MostCommon(5) {
		b.WriteString("| " + strconv.Itoa(i+1) + " | `" + e.Elem + "` | " +
			strconv.Itoa(e.Count) + " |\n")
	}
	b.WriteString("\nNote the ties. `barks`, `dog` and `fox` all occur twice and are ")
	b.WriteString("ranked **alphabetically** — the order is count descending, then ")
	b.WriteString("element ascending. That second key is not decoration: without it the ")
	b.WriteString("ranking would fall back on map iteration order, which gno leaves ")
	b.WriteString("unspecified, and two nodes could render different tables.\n\n")

	b.WriteString("## Algebra\n\n")
	a := multiset.FromSlice([]string{"x", "x", "x", "y"})
	c := multiset.FromSlice([]string{"x", "x", "z"})
	b.WriteString("With `A = {x:3, y:1}` and `B = {x:2, z:1}`:\n\n")
	b.WriteString("| op | meaning | result |\n|---|---|---|\n")
	b.WriteString("| `Union` | max of each count | " + brief(a.Union(c)) + " |\n")
	b.WriteString("| `Intersect` | min, common only | " + brief(a.Intersect(c)) + " |\n")
	b.WriteString("| `Sum` | counts added | " + brief(a.Sum(c)) + " |\n")

	b.WriteString("\n## Removal\n\n")
	d := multiset.FromSlice([]string{"a", "a", "a"})
	b.WriteString("Starting from " + brief(d) + ":\n\n")
	d.Remove("a")
	b.WriteString("- after `Remove(\"a\")` → " + brief(d) + "\n")
	d.RemoveN("a", 100)
	b.WriteString("- after `RemoveN(\"a\", 100)` → " + brief(d) +
		" — over-removing clears the element instead of going negative\n")
	return b.String()
}

func brief(m *multiset.MultiSet) string {
	if m.IsEmpty() {
		return "`{}`"
	}
	parts := []string{}
	for _, e := range m.Elements() {
		parts = append(parts, e+":"+strconv.Itoa(m.Count(e)))
	}
	return "`{" + strings.Join(parts, ", ") + "}`"
}
