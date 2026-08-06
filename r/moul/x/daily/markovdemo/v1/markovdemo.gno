// Package markovdemo is a small on-chain demo of the Markov-chain text
// generator provided by the [p/moul/x/daily/markov](/p/moul/x/daily/markov/v1)
// library.
//
// It holds a single package-level [markov.Chain] as the corpus and wires it to
// the chain: Feed appends words to that persistent chain (a crossing function,
// since it mutates on-chain state), while Generate and Render walk it with a
// seed derived from runtime.ChainHeight() — so babbling is a pure, reproducible
// query that still varies block to block. It contains no Markov logic of its
// own — build/walk math all lives in the library.
package markovdemo

import (
	"chain"
	"chain/runtime"
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/markov/v1"
)

// maxGen clamps Generate / Render so output stays bounded.
const maxGen = 200

// mc is the single on-chain corpus, seeded at deploy time.
var mc = markov.New()

func init() {
	// Two seed sentences with heavy two-word-prefix overlap, so a fresh deploy
	// already babbles something recognizably chain-like.
	mc.Build("it was the best of times it was the worst of times " +
		"it was the age of wisdom it was the age of foolishness")
	mc.Build("i am a free man i am not a number " +
		"i am the master of my fate i am the captain of my soul")
}

// seedFor derives a Generate seed from the current chain height so the babble
// changes block to block yet stays reproducible for anyone querying the same
// height.
func seedFor() uint64 {
	return uint64(runtime.ChainHeight())*2654435761 + 0x9e3779b97f4a7c15
}

// Feed appends text to the on-chain corpus, extending the Markov chain. Any
// caller may enrich the corpus — this is the open-membership demo model.
func Feed(cur realm, text string) string {
	if strings.TrimSpace(text) == "" {
		panic("markov: empty text")
	}
	added := mc.Build(text)
	words, prefixes := mc.Stats()
	chain.Emit("Feed", "words", strconv.Itoa(added), "total", strconv.Itoa(words))
	return "fed " + strconv.Itoa(added) + " words; corpus now " +
		strconv.Itoa(words) + " words across " +
		strconv.Itoa(prefixes) + " prefixes"
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
	return strings.Join(mc.Generate(nWords, seedFor()), " ")
}

// Stats returns (totalWords, prefixCount) for the current corpus.
func Stats() (int, int) {
	return mc.Stats()
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

	words, prefixes := mc.Stats()

	var b strings.Builder
	b.WriteString("# Markov Babbler\n\n")
	b.WriteString("A demo of the [`p/moul/x/daily/markov`](/p/moul/x/daily/markov/v1) " +
		"library — an on-chain port of Go's classic *\"Generating arbitrary text: " +
		"a Markov chain algorithm\"* codewalk. Every two-word **prefix** maps to " +
		"the words that followed it; `Generate` walks that chain, picking suffixes " +
		"with a PRNG seeded by the block height — deterministic, yet different each " +
		"block.\n\n")

	b.WriteString("## Fresh sample (" + strconv.Itoa(n) + " words, height " +
		strconv.FormatInt(runtime.ChainHeight(), 10) + ")\n\n")
	sample := strings.Join(mc.Generate(n, seedFor()), " ")
	if sample == "" {
		sample = "_(empty corpus)_"
	}
	b.WriteString("> " + sample + "\n\n")

	b.WriteString("## Corpus\n\n")
	b.WriteString("- **Words:** " + strconv.Itoa(words) + "\n")
	b.WriteString("- **Distinct prefixes:** " + strconv.Itoa(prefixes) + "\n")
	b.WriteString("- **Prefix length:** " + strconv.Itoa(markov.PrefixLen) + " words\n\n")

	b.WriteString("## Some prefixes → suffixes\n\n")
	b.WriteString("| prefix | can be followed by |\n|---|---|\n")
	shown := 0
	mc.Iterate(func(k string, suffixes []string) bool {
		disp := k
		if disp == " " || disp == "" {
			disp = "_(start)_"
		}
		b.WriteString("| `" + disp + "` | " + strings.Join(suffixes, ", ") + " |\n")
		shown++
		return shown >= 12 // cap the table
	})
	b.WriteString("\n_Call `Feed(\"your text here\")` to teach it new words, then " +
		"reload for a new sample._\n")

	return b.String()
}
