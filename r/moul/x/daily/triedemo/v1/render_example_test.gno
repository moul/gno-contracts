package triedemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Trie Autocomplete
	//
	// A prefix tree over a 55-word dictionary, demoing the [`p/moul/x/daily/trie`](/p/moul/x/daily/trie/v1) library.
	//
	// Append a prefix to the path to complete it.
	//
	// ## Try one
	//
	// - [`/co`](/r/moul/x/daily/triedemo/v1:co) — 10 words
	// - [`/gno`](/r/moul/x/daily/triedemo/v1:gno) — 5 words
	// - [`/re`](/r/moul/x/daily/triedemo/v1:re) — 6 words
	// - [`/tr`](/r/moul/x/daily/triedemo/v1:tr) — 5 words
}

// ExampleRender_prefix pins a prefix walk: the completions come out in
// lexicographic order, and `trie` is flagged as a word in its own right.
func ExampleRender_prefix() {
	print(Render("/tr"))
	// Output:
	// # Trie Autocomplete
	//
	// A prefix tree over a 55-word dictionary, demoing the [`p/moul/x/daily/trie`](/p/moul/x/daily/trie/v1) library.
	//
	// ## Completions for `tr`
	//
	// **5** matches
	//
	// - `transaction`
	// - `transfer`
	// - `traverse`
	// - `tree`
	// - `trie`
}

// ExampleRender_unknown pins the miss path.
func ExampleRender_unknown() {
	print(Render("/zzz"))
	// Output:
	// # Trie Autocomplete
	//
	// A prefix tree over a 55-word dictionary, demoing the [`p/moul/x/daily/trie`](/p/moul/x/daily/trie/v1) library.
	//
	// ## Completions for `zzz`
	//
	// _No word starts with `zzz`._
	//
	// > Try `/co`, `/gno`, `/tr` or `/re`.
}
