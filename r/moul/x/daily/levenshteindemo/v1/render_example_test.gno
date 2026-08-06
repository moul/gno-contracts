package levenshteindemo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Levenshtein edit distance
	//
	// Demo of the [`p/moul/x/daily/levenshtein`](/p/moul/x/daily/levenshtein/v1) library. The **Levenshtein distance** between two strings is the minimum number of single-character edits — *insertions*, *deletions*, or *substitutions* — needed to turn one string into the other. The library implements the classic dynamic-programming algorithm (à la Go's `agext/levenshtein`) fully rune-aware and on-chain.
	//
	// ## Try it
	//
	// Append two words as `/<a>/<b>`:
	//
	// - [`/kitten/sitting`](/r/moul/x/daily/levenshteindemo/v1:kitten/sitting) → distance **3**
	// - [`/flaw/lawn`](/r/moul/x/daily/levenshteindemo/v1:flaw/lawn) → distance **2**
	// - [`/sunday/saturday`](/r/moul/x/daily/levenshteindemo/v1:sunday/saturday) → distance **3**
	// - [`/gno/gnoland`](/r/moul/x/daily/levenshteindemo/v1:gno/gnoland) → distance **4**
	//
	// ## The classic example
	//
	// `kitten` → `sitting` = **3**:
	//
	// 1. `kitten` → `sitten` (substitute *k* → *s*)
	// 2. `sitten` → `sittin` (substitute *e* → *i*)
	// 3. `sittin` → `sitting` (insert *g* at the end)
	//
	// ## API
	//
	// - `Distance(a, b string) int` — the edit distance.
	// - `Matrix(a, b string) [][]int` — the full DP matrix.
	// - `Similarity(a, b string) int` — a 0..100 similarity percentage.
}
