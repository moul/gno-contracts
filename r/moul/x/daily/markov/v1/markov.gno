// Package markov ports the canonical Go example
// "Generating arbitrary text: a Markov chain algorithm"
// (https://go.dev/doc/codewalk/markov/) to a gno.land realm.
//
// The original reads words from an io.Reader, builds a map from each
// two-word prefix to the list of words that followed it, then walks that
// chain picking random suffixes to babble new text. Here the corpus lives
// on-chain: Feed appends words to a persistent avl.Tree-backed chain, and
// Generate walks it. The only change needed for on-chain determinism is the
// source of randomness: instead of math/rand we seed a small LCG with
// runtime.ChainHeight(), so Generate is a pure, reproducible query that still
// varies block to block.
//
// Feed is a crossing function (takes `cur realm` first) because it mutates
// on-chain state; Generate and Render are read-only.
package markov

import (
	"chain"
	"chain/runtime"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// prefixLen is the number of words in a prefix. Two is the classic choice
// from the Go codewalk: long enough to sound plausible, short enough to keep
// the chain well-connected.
const prefixLen = 2

const maxGen = 200 // clamp for Generate / Render so output stays bounded

// Prefix is a sliding window of the last prefixLen words seen. It mirrors the
// Prefix type in the original program.
type Prefix []string

// key joins the prefix into the string used as the chain's map key. Two empty
// strings (the initial prefix) join to a single space " ", which is exactly
// the start-of-text key both Feed and Generate begin from.
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

// Chain is the on-chain Markov chain. table maps prefix key -> *suffixList;
// prefix is the rolling build window so successive Feed calls extend one
// continuous corpus rather than restarting; words is the running word count.
type Chain struct {
	table  avl.Tree
	prefix Prefix
	words  int
}

func newChain() *Chain {
	return &Chain{prefix: make(Prefix, prefixLen)}
}

// build tokenizes text on whitespace and folds each word into the chain,
// recording it as a suffix of the current prefix and then shifting. This is
// the on-chain analogue of Chain.Build from the codewalk.
func (c *Chain) build(text string) int {
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

// generate walks the chain from the start prefix, picking one suffix per step
// via the seeded LCG, and returns up to n words. It stops early if it reaches a
// prefix with no recorded suffixes (a dead end). Pure: no global state touched.
func (c *Chain) generate(n int, seed uint64) []string {
	if n <= 0 {
		return nil
	}
	p := make(Prefix, prefixLen)
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

// nextRand is a 64-bit linear congruential generator (the PCG/Knuth
// multiplier + increment). Deterministic and dependency-free — all the
// entropy comes from the caller's seed.
func nextRand(s uint64) uint64 {
	return s*6364136223846793005 + 1442695040888963407
}

// seedFor derives a Generate seed from the current chain height so the babble
// changes block to block yet stays reproducible for anyone querying the same
// height.
func seedFor() uint64 {
	return uint64(runtime.ChainHeight())*2654435761 + 0x9e3779b97f4a7c15
}

// mc is the single on-chain corpus, seeded at deploy time.
var mc = newChain()

func init() {
	// Two seed sentences with heavy two-word-prefix overlap, so a fresh deploy
	// already babbles something recognizably chain-like.
	mc.build("it was the best of times it was the worst of times " +
		"it was the age of wisdom it was the age of foolishness")
	mc.build("i am a free man i am not a number " +
		"i am the master of my fate i am the captain of my soul")
}

// Feed appends text to the on-chain corpus, extending the Markov chain. Any
// caller may enrich the corpus — this is the open-membership demo model.
func Feed(cur realm, text string) string {
	if strings.TrimSpace(text) == "" {
		panic("markov: empty text")
	}
	added := mc.build(text)
	chain.Emit("Feed", "words", strconv.Itoa(added), "total", strconv.Itoa(mc.words))
	return "fed " + strconv.Itoa(added) + " words; corpus now " +
		strconv.Itoa(mc.words) + " words across " +
		strconv.Itoa(mc.table.Size()) + " prefixes"
}

// Generate babbles up to nWords of Markov text from the current corpus, seeded
// deterministically by the chain height. Read-only.
func Generate(nWords int) string {
	if nWords <= 0 {
		nWords = 20
	}
	if nWords > maxGen {
		nWords = maxGen
	}
	return strings.Join(mc.generate(nWords, seedFor()), " ")
}

// Stats returns (totalWords, prefixCount) for the current corpus.
func Stats() (int, int) {
	return mc.words, mc.table.Size()
}

// parseN pulls a trailing positive integer out of a Render path such as
// "/40" or "gen/40"; it returns 0 when there is none.
func parseN(path string) int {
	p := strings.Trim(path, "/")
	if i := strings.LastIndex(p, "/"); i >= 0 {
		p = p[i+1:]
	}
	n, err := strconv.Atoi(p)
	if err != nil || n < 0 {
		return 0
	}
	return n
}

// Render shows a freshly generated sample plus corpus stats. The path may
// carry a word count, e.g. Render("/60").
func Render(path string) string {
	n := parseN(path)
	if n == 0 {
		n = 40
	}
	if n > maxGen {
		n = maxGen
	}

	var b strings.Builder
	b.WriteString("# Markov Babbler\n\n")
	b.WriteString("An on-chain port of Go's classic *\"Generating arbitrary text: " +
		"a Markov chain algorithm\"* codewalk. Every two-word **prefix** maps to " +
		"the words that followed it; `Generate` walks that chain, picking suffixes " +
		"with a PRNG seeded by the block height — deterministic, yet different each " +
		"block.\n\n")

	b.WriteString("## Fresh sample (" + strconv.Itoa(n) + " words, height " +
		strconv.FormatInt(runtime.ChainHeight(), 10) + ")\n\n")
	sample := strings.Join(mc.generate(n, seedFor()), " ")
	if sample == "" {
		sample = "_(empty corpus)_"
	}
	b.WriteString("> " + sample + "\n\n")

	b.WriteString("## Corpus\n\n")
	b.WriteString("- **Words:** " + strconv.Itoa(mc.words) + "\n")
	b.WriteString("- **Distinct prefixes:** " + strconv.Itoa(mc.table.Size()) + "\n")
	b.WriteString("- **Prefix length:** " + strconv.Itoa(prefixLen) + " words\n\n")

	b.WriteString("## Some prefixes → suffixes\n\n")
	b.WriteString("| prefix | can be followed by |\n|---|---|\n")
	shown := 0
	mc.table.Iterate("", "", func(k string, v interface{}) bool {
		sl := v.(*suffixList)
		disp := k
		if disp == " " || disp == "" {
			disp = "_(start)_"
		}
		b.WriteString("| `" + disp + "` | " + strings.Join(sl.words, ", ") + " |\n")
		shown++
		return shown >= 12 // cap the table
	})
	b.WriteString("\n_Call `Feed(\"your text here\")` to teach it new words, then " +
		"reload for a new sample._\n")

	return b.String()
}
