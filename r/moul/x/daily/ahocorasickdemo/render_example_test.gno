package ahocorasickdemo

// ExampleRender pins the realm's root Render output as a testable example.
// The `ushers` rows are the textbook automaton's published answer, so this
// example doubles as a conformance test for the library.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Aho-Corasick
	//
	// One automaton for the whole dictionary, one pass over the text, demoing the [`p/moul/x/daily/ahocorasick`](/p/moul/x/daily/ahocorasick/v0) library.
	//
	// ## The 1975 example
	//
	// Patterns `he`, `she`, `his`, `hers` over `ushers`. Three of the four overlap, and `hers` ends where nothing else starts.
	//
	// | start | end | pattern |
	// | --- | --- | --- |
	// | `1` | `4` | `she` |
	// | `2` | `4` | `he` |
	// | `2` | `6` | `hers` |
	//
	// ## One pass over a sentence
	//
	// Patterns `the`, `he`, `fox`, `over`, `lazy` over `the quick brown fox jumps over the lazy dog`.
	//
	// | start | end | pattern |
	// | --- | --- | --- |
	// | `0` | `3` | `the` |
	// | `1` | `3` | `he` |
	// | `16` | `19` | `fox` |
	// | `26` | `30` | `over` |
	// | `31` | `34` | `the` |
	// | `32` | `34` | `he` |
	// | `35` | `39` | `lazy` |
	//
	// `5` patterns, `17` automaton nodes, `43` bytes read once, `7` matches. Running a single-pattern scan per word would read those bytes `5` times instead.
	//
	// > Scan your own text: append it to the path, for instance [`/thermos`](/r/moul/x/daily/ahocorasickdemo/v0:/thermos), where `the` and `he` overlap on the same three letters.
}

// ExampleRenderScan pins the argument path: the visitor's text is scanned with
// the same dictionary, and the table reports offsets and dictionary words only.
func ExampleRenderScan() {
	print(Render("/thermos"))
	// Output:
	// # Aho-Corasick
	//
	// One automaton for the whole dictionary, one pass over the text, demoing the [`p/moul/x/daily/ahocorasick`](/p/moul/x/daily/ahocorasick/v0) library.
	//
	// ## `thermos`
	//
	// Patterns `the`, `he`, `fox`, `over`, `lazy`.
	//
	// | start | end | pattern |
	// | --- | --- | --- |
	// | `0` | `3` | `the` |
	// | `1` | `3` | `he` |
	//
	// `5` patterns, `17` automaton nodes, `7` bytes read once, `2` matches. Running a single-pattern scan per word would read those bytes `5` times instead.
}
