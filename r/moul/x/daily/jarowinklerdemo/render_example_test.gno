package jarowinklerdemo

// ExampleRender pins the realm's root Render output as a testable example.
// The scores in it are the ones the Jaro-Winkler literature publishes for
// these pairs, so this example doubles as a conformance test for the library
// running inside the VM.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Jaro-Winkler
	//
	// How much of two strings lines up, demoing the [`p/moul/x/daily/jarowinkler`](/p/moul/x/daily/jarowinkler/v0) library. Scores are integers out of 1000000, so no float ever reaches the chain.
	//
	// ## Vectors
	//
	// | a | b | Jaro | Jaro-Winkler | why this pair |
	// | --- | --- | --- | --- | --- |
	// | `MARTHA` | `MARHTA` | 94.44% | 96.11% | one transposition, three shared leading runes |
	// | `DWAYNE` | `DUANE` | 82.22% | 84.00% | different lengths, no transposition |
	// | `DIXON` | `DICKSONX` | 76.66% | 81.33% | half of DICKSONX never matches |
	// | `CRATE` | `TRACE` | 73.33% | 73.33% | under 0.7, so the prefix buys nothing |
	// | `JELLYFISH` | `SMELLYFISH` | 89.62% | 89.62% | eight matches and no prefix at all |
	// | `gno` | `gnoland` | 80.95% | 86.66% | a word against the word it starts |
	//
	// Jaro-Winkler only ever raises a Jaro score, and only once that score has reached 0.7. `CRATE`/`TRACE` share no leading rune and sits under the threshold anyway, so the two columns agree.
	//
	// ## Inside one score
	//
	// `MARTHA` against `MARHTA`:
	//
	// |  | value |  |
	// | --- | --- | --- |
	// | runes in a | 6 | MARTHA |
	// | runes in b | 6 | MARHTA |
	// | window | 2 | how far apart two runes may still match |
	// | matches | 6 | runes with a partner inside the window |
	// | transpositions | 1 | matched pairs that arrived in the wrong order |
	// | common prefix | 3 | leading runes, of which Winkler counts four |
	//
	// | # | a | b |  |
	// | --- | --- | --- | --- |
	// | 1 | M | M |  |
	// | 2 | A | A |  |
	// | 3 | R | R |  |
	// | 4 | T | H | out of order |
	// | 5 | H | T | out of order |
	// | 6 | A | A |  |
	//
	// Append two words to score your own pair: [`/martha/marhta`](/r/moul/x/daily/jarowinklerdemo/v0:martha/marhta)
	//
	// > ℹ️ **Built for names, not for sentences.** The matching window is half the longer string, so Jaro-Winkler compares short identifiers well and whole paragraphs badly. It is also not an edit distance: for "how many keystrokes apart are these", reach for [`levenshtein`](/r/moul/x/daily/levenshteindemo/v1).
}
