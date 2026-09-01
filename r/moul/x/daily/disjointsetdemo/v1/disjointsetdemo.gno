// Package disjointsetdemo is a small gnoweb demo of the union-find structure
// provided by the [p/moul/x/daily/disjointset](/p/moul/x/daily/disjointset/v1)
// library: it merges a fixed list of pairs and shows the resulting partition.
//
// It contains no union-find logic of its own. Stateless, so Render is
// deterministic — and the library's Partition is order-independent, which is
// what makes the output safe to pin.
package disjointsetdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/disjointset/v1"
)

// n is the universe size; pairs are the merges applied, in order.
const n = 10

var pairs = [][2]int{{0, 1}, {2, 3}, {1, 3}, {5, 6}, {7, 8}, {8, 9}}

func build() *disjointset.DisjointSet {
	d := disjointset.New(n)
	for _, p := range pairs {
		d.Union(p[0], p[1])
	}
	return d
}

// Render renders the demo for gnoweb.
func Render(path string) string {
	d := build()

	var b strings.Builder
	b.WriteString("# Union-Find\n\n")
	b.WriteString("Disjoint-set forest with path compression and union by rank, demoing the ")
	b.WriteString("[`p/moul/x/daily/disjointset`](/p/moul/x/daily/disjointset/v1) library.\n\n")

	b.WriteString("## Merges applied\n\n")
	for _, p := range pairs {
		b.WriteString("- `Union(")
		b.WriteString(strconv.Itoa(p[0]))
		b.WriteString(", ")
		b.WriteString(strconv.Itoa(p[1]))
		b.WriteString(")`\n")
	}

	b.WriteString("\n## Partition of [0, ")
	b.WriteString(strconv.Itoa(n))
	b.WriteString(")\n\n**")
	b.WriteString(strconv.Itoa(d.Groups()))
	b.WriteString("** groups:\n\n")
	for _, g := range d.Partition() {
		b.WriteString("- `{")
		nums := []string{}
		for _, x := range g {
			nums = append(nums, strconv.Itoa(x))
		}
		b.WriteString(strings.Join(nums, ", "))
		b.WriteString("}`\n")
	}

	b.WriteString("\n> Groups come out sorted, ordered by their smallest member, ")
	b.WriteString("so the partition is identical whatever order the merges arrive in.\n")
	return b.String()
}
