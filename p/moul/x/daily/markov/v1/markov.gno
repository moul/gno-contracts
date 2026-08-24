// Package markov is a deterministic Markov-chain text generator — a port of
// Go's canonical example "Generating arbitrary text: a Markov chain algorithm"
// (https://go.dev/doc/codewalk/markov/) with math/rand replaced by a
// caller-supplied seed.
//
// It is a pure library: it imports no chain APIs and reads no ambient state.
// A [Chain] maps every PrefixLen-word prefix to the list of words observed to
// follow it (duplicates kept, so frequency biases the walk), storing that map
// in a persistent avl.Tree. Build folds text into the chain; Generate walks it
// from the start prefix, picking one suffix per step from a small LCG seeded by
// the uint64 the caller passes — so generation is deterministic and replayable,
// and the caller decides where entropy comes from (on-chain, the block height).
//
// A realm wires it up by holding a *Chain in a package-level var, calling Build
// to grow the corpus and Generate with a height-derived seed. For a complete,
// live example see the demo realm
// [r/moul/x/daily/markovdemo](/r/moul/x/daily/markovdemo/v1).
package markov

import (
	"strings"

	"gno.land/p/nt/avl/v0"
)

// PrefixLen is the number of words in a prefix. Two is the classic choice from
// the Go codewalk: long enough to sound plausible, short enough to keep the
// chain well-connected.
const PrefixLen = 2

// Prefix is a sliding window of the last PrefixLen words seen. It mirrors the
// Prefix type in the original program.
type Prefix []string

// key joins the prefix into the string used as the chain's map key. Two empty
// strings (the initial prefix) join to a single space " ", which is exactly
// the start-of-text key both Build and Generate begin from.
func (p Prefix) key() string { return strings.Join(p, " ") }

// shift drops the oldest word and appends word, advancing the window by one.
func (p Prefix) shift(word string) {
	copy(p, p[1:])
	p[len(p)-1] = word
}

// suffixList is the value stored per prefix: every word observed to follow it,
// in order (duplicates kept so frequency biases the random walk, just like the
// original []string in the chain map).
type suffixList struct {
	words []string
}

// Chain is a Markov chain over a persistent avl.Tree. table maps prefix key ->
// *suffixList; prefix is the rolling build window so successive Build calls
// extend one continuous corpus rather than restarting; words is the running
// word count.
type Chain struct {
	table  avl.Tree
	prefix Prefix
	words  int
}

// New returns an empty Chain ready to Build into.
func New() *Chain {
	return &Chain{prefix: make(Prefix, PrefixLen)}
}

// Build tokenizes text on whitespace and folds each word into the chain,
// recording it as a suffix of the current prefix and then shifting. It returns
// the number of words added. This is the analogue of Chain.Build from the
// codewalk.
func (c *Chain) Build(text string) int {
	added := 0
	for _, w := range strings.Fields(text) {
		k := c.prefix.key()
		var sl *suffixList
		if c.table.Has(k) {
			sl = c.table.Get(k).(*suffixList)
		} else {
			sl = &suffixList{}
		}
		sl.words = append(sl.words, w)
		c.table.Set(k, sl)
		c.prefix.shift(w)
		c.words++
		added++
	}
	return added
}

// Generate walks the chain from the start prefix, picking one suffix per step
// via an LCG seeded by seed, and returns up to n words. It stops early if it
// reaches a prefix with no recorded suffixes (a dead end). Pure: the same
// (n, seed) always yields the same words for a given chain.
func (c *Chain) Generate(n int, seed uint64) []string {
	if n <= 0 {
		return nil
	}
	p := make(Prefix, PrefixLen)
	rng := seed
	out := make([]string, 0, n)
	for i := 0; i < n; i++ {
		k := p.key()
		if !c.table.Has(k) {
			break
		}
		choices := c.table.Get(k).(*suffixList).words
		if len(choices) == 0 {
			break
		}
		rng = nextRand(rng)
		// use high bits of the LCG state — its low bits have short periods
		idx := int((rng >> 33) % uint64(len(choices)))
		next := choices[idx]
		out = append(out, next)
		p.shift(next)
	}
	return out
}

// Stats returns (totalWords, prefixCount) for the current chain.
func (c *Chain) Stats() (int, int) {
	return c.words, c.table.Size()
}

// Iterate calls fn for each prefix in ascending key order, passing the prefix
// key and the list of words recorded to follow it. Returning true from fn stops
// the iteration early; Iterate reports whether it was stopped that way.
func (c *Chain) Iterate(fn func(prefix string, suffixes []string) bool) bool {
	return c.table.Iterate("", "", func(k string, v interface{}) bool {
		return fn(k, v.(*suffixList).words)
	})
}

// nextRand is a 64-bit linear congruential generator (the PCG/Knuth
// multiplier + increment). Deterministic and dependency-free — all the
// entropy comes from the caller's seed.
func nextRand(s uint64) uint64 {
	return s*6364136223846793005 + 1442695040888963407
}
