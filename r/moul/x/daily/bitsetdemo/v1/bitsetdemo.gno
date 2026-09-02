// Package bitsetdemo is a small gnoweb demo of the dense bit vector provided by
// the [p/moul/x/daily/bitset](/p/moul/x/daily/bitset/v1) library: it sieves the
// primes under 100 into a bit set and shows the set algebra on two small sets.
//
// It contains no bit-twiddling of its own — storage, popcount and the set
// operations all come from the library. Stateless, so Render is deterministic.
package bitsetdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/bitset/v1"
)

// limit bounds the sieve shown on the page.
const limit = 100

// primes returns a bit set of the primes below limit, sieved with the bit set
// itself as the composite marker.
func primes() *bitset.BitSet {
	composite := bitset.New(limit)
	out := bitset.New(limit)
	for p := 2; p < limit; p++ {
		if composite.Has(p) {
			continue
		}
		out.Set(p)
		for m := p * p; m < limit; m += p {
			composite.Set(m)
		}
	}
	return out
}

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# BitSet\n\n")
	b.WriteString("A dense bit vector, demoing the ")
	b.WriteString("[`p/moul/x/daily/bitset`](/p/moul/x/daily/bitset/v1) library.\n\n")

	p := primes()
	b.WriteString("## Primes under ")
	b.WriteString(strconv.Itoa(limit))
	b.WriteString("\n\n**")
	b.WriteString(strconv.Itoa(p.Count()))
	b.WriteString("** set bits in ")
	b.WriteString(strconv.Itoa(p.Cap()))
	b.WriteString(" bits of capacity:\n\n")
	b.WriteString(list(p.Slice()))

	small := bitset.FromSlice(16, []int{1, 2, 3, 5, 8})
	even := bitset.FromSlice(16, []int{2, 4, 6, 8, 10})
	b.WriteString("\n## Set algebra\n\n")
	b.WriteString("| set | bits |\n|---|---|\n")
	row(&b, "a", small)
	row(&b, "b", even)
	row(&b, "a ∪ b", bitset.Union(small, even))
	row(&b, "a ∩ b", bitset.Intersect(small, even))
	row(&b, "a \\ b", bitset.Difference(small, even))
	row(&b, "a △ b", bitset.SymmetricDifference(small, even))
	return b.String()
}

func row(b *strings.Builder, name string, s *bitset.BitSet) {
	b.WriteString("| ")
	b.WriteString(name)
	b.WriteString(" | `")
	b.WriteString(list1(s.Slice()))
	b.WriteString("` |\n")
}

func list(xs []int) string {
	if len(xs) == 0 {
		return "_none_\n"
	}
	return "`" + list1(xs) + "`\n"
}

func list1(xs []int) string {
	parts := []string{}
	for _, x := range xs {
		parts = append(parts, strconv.Itoa(x))
	}
	return strings.Join(parts, " ")
}
