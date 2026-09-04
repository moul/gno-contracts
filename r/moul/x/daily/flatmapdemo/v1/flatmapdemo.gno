// Package flatmapdemo is a small gnoweb demo of the sorted-vector map provided
// by the [p/moul/x/daily/flatmap](/p/moul/x/daily/flatmap/v1) library: sorted
// storage, indexed access and range queries.
//
// It contains no map logic of its own. Stateless, so Render is deterministic —
// which is precisely what the library is for.
package flatmapdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/flatmap/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Flat Map\n\n")
	b.WriteString("A map backed by sorted slices, demoing the ")
	b.WriteString("[`p/moul/x/daily/flatmap`](/p/moul/x/daily/flatmap/v1) library.\n\n")

	f := flatmap.New()
	inserted := []string{"delta", "alpha", "echo", "bravo", "charlie"}
	for i, k := range inserted {
		f.Set(k, strconv.Itoa(i+1))
	}

	b.WriteString("## Sorted by construction\n\n")
	b.WriteString("Inserted as `" + strings.Join(inserted, ", ") + "` — stored sorted:\n\n")
	b.WriteString(table(f))
	b.WriteString("\nNo sort on read, and no dependence on map iteration order — which ")
	b.WriteString("gno leaves unspecified, and which would let two nodes render different ")
	b.WriteString("pages from the same state.\n\n")

	b.WriteString("## Indexed access\n\n")
	b.WriteString("Sorted storage gives positional lookup that a hash map cannot:\n\n")
	for _, i := range []int{0, 2, 4} {
		k, v, _ := f.At(i)
		b.WriteString("- `At(" + strconv.Itoa(i) + ")` → `" + k + "` = `" + v + "`\n")
	}

	b.WriteString("\n## Range queries\n\n")
	b.WriteString("Two binary searches and a walk — `lo` inclusive, `hi` exclusive:\n\n")
	b.WriteString("| range | keys |\n|---|---|\n")
	b.WriteString("| `[\"bravo\", \"delta\")` | " + rng(f, "bravo", "delta") + " |\n")
	b.WriteString("| `[\"charlie\", ∞)` | " + rng(f, "charlie", "") + " |\n")
	b.WriteString("| `[\"b\", \"d\")` | " + rng(f, "b", "d") + " |\n")
	b.WriteString("\nThe last one asks for bounds that are not keys at all — the search ")
	b.WriteString("still lands in the right place.\n\n")

	b.WriteString("## The trade\n\n")
	b.WriteString("| operation | cost |\n|---|---|\n")
	b.WriteString("| `Get` | O(log n) binary search over contiguous memory |\n")
	b.WriteString("| iteration | O(n), already ordered, nothing to sort |\n")
	b.WriteString("| `Set` in the middle | **O(n)** — the tail shifts |\n")
	b.WriteString("| `Set` at the end | O(1) amortised — the fast path |\n")
	b.WriteString("\nCheap reads and cheap ordered iteration, paid for at write time.\n")
	return b.String()
}

func table(f *flatmap.FlatMap) string {
	var b strings.Builder
	b.WriteString("| # | key | value |\n|---|---|---|\n")
	i := 0
	f.Iterate(func(k, v string) bool {
		b.WriteString("| " + strconv.Itoa(i) + " | `" + k + "` | `" + v + "` |\n")
		i++
		return false
	})
	return b.String()
}

func rng(f *flatmap.FlatMap, lo, hi string) string {
	var out []string
	f.Range(lo, hi, func(k, v string) bool {
		out = append(out, "`"+k+"`")
		return false
	})
	if len(out) == 0 {
		return "_none_"
	}
	return strings.Join(out, ", ")
}
