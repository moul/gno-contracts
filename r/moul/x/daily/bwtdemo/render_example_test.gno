package bwtdemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Burrows-Wheeler transform
	//
	// A reversible permutation that groups equal bytes together, demoing the [`p/moul/x/daily/bwt`](/p/moul/x/daily/bwt/v0) library. It compresses nothing on its own: the output holds the same bytes as the input in a different order, and the clustering is what a run-length or entropy coder downstream gets paid by.
	//
	// ## The matrix, for `banana`
	//
	// Every rotation of the input, sorted. The transform is the **last column** read downwards, and the second value is the row the input itself landed on.
	//
	// | row | rotation | last byte |
	// | --- | --- | --- |
	// | 0 | `abanan` | `n` |
	// | 1 | `anaban` | `n` |
	// | 2 | `ananab` | `b` |
	// | **3** | `banana` | `a` |
	// | 4 | `nabana` | `a` |
	// | 5 | `nanaba` | `a` |
	//
	// So `banana` transforms to `nnbaaa`, row **3**.
	//
	// ## Getting it back
	//
	// `Inverse` never rebuilds that matrix. The first column is the last one sorted, and the *i*-th occurrence of a byte in the last column is the *i*-th occurrence of it in the first, which is enough to walk the original backwards one byte at a time:
	//
	// ```
	// Inverse("nnbaaa", 3) = "banana"
	// ```
	//
	// Same bytes, original order. ✅
	//
	// The index is what lets the transform avoid a sentinel byte. A sentinel has to be a byte the input can never contain, and in an arbitrary string there is no such byte.
	//
	// ## What the clustering is worth
	//
	// | input | runs | transformed | runs |
	// | --- | --- | --- | --- |
	// | `abracadabra abracadabra` | 23 | `arrdda rrccaaaaaaaabbbb` | 9 ✅ |
	// | `banana bandana bandanna` | 22 | `aannnndbbbda  nnaanaaaa` | 11 ✅ |
	// | `the quick brown fox jumps over the lazy dog` | 43 | `kynxeserl i hhv ottu c uwd rfm ebp gqjoooza` | 39 ✅ |
	// | `mississippi` | 8 | `pssmipissii` | 8 = |
	//
	// Fewer runs over the same length means longer runs, and a run-length coder is paid by run length. `mississippi` is the honest counter-example: it repeats letters but no substring long enough to group, so the transform buys nothing at all. The clustering is a tendency, never a guarantee, which is why `Runs` is exported: measure it instead of assuming it.
	//
	// ## Try your own
	//
	// ```
	// /r/moul/x/daily/bwtdemo/v0:banana bandana
	// ```
}

// probe is a payload that closes a one-backtick code span, opens an image and
// then opens a new table column. Written raw it renders as markup the realm
// appears to have authored.
const probe = "a`|![p](h)"

// ExampleRender_escapesCallerInput pins that every place the caller's bytes
// reach the page is escaped, including the transformed string, which is a
// permutation of those same bytes and carries each pipe and backtick through.
//
// The pipes are the ones that bite: a code span is not an escape, so an
// md.InlineCode cell with a pipe in it opens a column and shifts every value
// after it. v0 of this file did exactly that.
func ExampleRender_escapesCallerInput() {
	print(Render("/" + probe))
	// Output:
	// # Burrows-Wheeler transform
	//
	// Input: ``a`|![p](h)``
	//
	// | field | value |
	// | --- | --- |
	// | transformed | \|\]h\!pa\)\(\[\` |
	// | index | 6 |
	// | runs | 10 → 10 = |
	// | round-trips | ✅ |
	//
	// ### The matrix
	//
	// | row | rotation | last byte |
	// | --- | --- | --- |
	// | 0 | \!\[p\]\(h\)a\`\| | \| |
	// | 1 | \(h\)a\`\|\!\[p\] | \] |
	// | 2 | \)a\`\|\!\[p\]\(h | h |
	// | 3 | \[p\]\(h\)a\`\|\! | \! |
	// | 4 | \]\(h\)a\`\|\!\[p | p |
	// | 5 | \`\|\!\[p\]\(h\)a | a |
	// | **6** | a\`\|\!\[p\]\(h\) | \) |
	// | 7 | h\)a\`\|\!\[p\]\( | \( |
	// | 8 | p\]\(h\)a\`\|\!\[ | \[ |
	// | 9 | \|\!\[p\]\(h\)a\` | \` |
	//
	// [back](/r/moul/x/daily/bwtdemo/v0)
}
