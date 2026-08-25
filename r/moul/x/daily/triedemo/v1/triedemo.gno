// Package triedemo is a small gnoweb demo of the prefix tree provided by the
// [p/moul/x/daily/trie](/p/moul/x/daily/trie/v1) library: type a prefix in the
// URL and it lists every dictionary word that completes it.
//
// It contains no trie logic of its own — the tree, the ordering and the limit
// all come from the library. The dictionary is a fixed, sorted word list so the
// realm has no mutable state and Render is fully deterministic.
package triedemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/trie/v1"
)

// maxResults caps how many completions a single Render lists.
const maxResults = 25

// dictionary is the demo corpus: gno/Go vocabulary, deliberately clustered on
// a few prefixes ("co", "gn", "re", "tr") so completions are fun to explore.
var dictionary = []string{
	"chain", "coin", "collection", "commit", "compile", "complete", "concurrent",
	"consensus", "constant", "contract", "counter", "crossing", "deploy", "gas",
	"genesis", "gno", "gnodev", "gnokey", "gnoland", "gnoweb", "goroutine",
	"grc20", "hash", "interface", "keeper", "ledger", "mempool", "merkle",
	"module", "namespace", "package", "panic", "pointer", "prefix", "prove",
	"realm", "receiver", "recover", "reflect", "render", "replay", "rollback",
	"slice", "stdlib", "struct", "transaction", "transfer", "traverse", "tree",
	"trie", "type", "validator", "vault", "vm", "wallet",
}

// dict is built once at init; the library keeps it sorted internally.
var dict = trie.FromWords(dictionary)

// Render renders the autocomplete for gnoweb.
//
//	Render("")          / Render("/") -> the whole dictionary + usage
//	Render("/<prefix>")               -> every word completing <prefix>
func Render(path string) string {
	prefix := parsePrefix(path)

	var b strings.Builder
	b.WriteString("# Trie Autocomplete\n\n")
	b.WriteString("A prefix tree over a ")
	b.WriteString(strconv.Itoa(dict.Len()))
	b.WriteString("-word dictionary, demoing the ")
	b.WriteString("[`p/moul/x/daily/trie`](/p/moul/x/daily/trie/v1) library.\n\n")

	if prefix == "" {
		b.WriteString("Append a prefix to the path to complete it.\n\n")
		b.WriteString("## Try one\n\n")
		// Listing all 55 words here would bury the page (and the example test
		// that pins it); the interesting part is the prefix walk, so show a few
		// live counts and let /<prefix> do the listing.
		for _, p := range []string{"co", "gno", "re", "tr"} {
			b.WriteString("- [`/")
			b.WriteString(p)
			b.WriteString("`](/r/moul/x/daily/triedemo/v1:")
			b.WriteString(p)
			b.WriteString(") — ")
			b.WriteString(strconv.Itoa(len(dict.Complete(p, 0))))
			b.WriteString(" words\n")
		}
		return b.String()
	}

	b.WriteString("## Completions for `")
	b.WriteString(prefix)
	b.WriteString("`\n\n")

	if !dict.HasPrefix(prefix) {
		b.WriteString("_No word starts with `")
		b.WriteString(prefix)
		b.WriteString("`._\n\n> Try `/co`, `/gno`, `/tr` or `/re`.\n")
		return b.String()
	}

	words := dict.Complete(prefix, maxResults)
	b.WriteString("**")
	b.WriteString(strconv.Itoa(len(words)))
	b.WriteString("** match")
	if len(words) != 1 {
		b.WriteString("es")
	}
	if len(words) == maxResults {
		b.WriteString(" (capped at ")
		b.WriteString(strconv.Itoa(maxResults))
		b.WriteString(")")
	}
	b.WriteString("\n\n")
	b.WriteString(list(words))

	if dict.Contains(prefix) {
		b.WriteString("\n> `")
		b.WriteString(prefix)
		b.WriteString("` is itself a word in the dictionary.\n")
	}
	return b.String()
}

// parsePrefix extracts the prefix from a Render path like "/gno", keeping only
// the first segment. Returns "" for the empty/root path.
func parsePrefix(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}

// list renders words as a Markdown bullet list.
func list(words []string) string {
	if len(words) == 0 {
		return "_none_\n"
	}
	var b strings.Builder
	for _, w := range words {
		b.WriteString("- `")
		b.WriteString(w)
		b.WriteString("`\n")
	}
	return b.String()
}
