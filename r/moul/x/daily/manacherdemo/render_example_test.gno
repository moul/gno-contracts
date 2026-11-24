package manacherdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Manacher's algorithm
	//
	// Every palindromic substring of a string, in one linear pass. Demoing the [`p/moul/x/daily/manacher`](/p/moul/x/daily/manacher/v0) library.
	//
	// ## Odd and even are one problem
	//
	// `aba` has a middle byte and `abba` does not, so a routine that expands around centres has two cases to get right and two places to get them wrong. Interleaving a separator removes the distinction: every palindrome of the original becomes an odd-length palindrome of the transform, around exactly one index.
	//
	// ```
	// banana
	// #b#a#n#a#n#a#
	// ```
	//
	// The separator needs no reserved value, which is the part that looks unsafe and is not. Separators land on even indices and the original bytes on odd ones, and the two positions the scan compares always sum to twice the centre, so they share a parity. A separator is only ever compared against another separator, and an input of nothing but `#` comes out right.
	//
	// ## Every centre of `banana`
	//
	// One row per centre, 13 of them. The length is what the library returns; the span is `s[(i-len)/2 : (i+len)/2]`, which is the only arithmetic a caller ever needs.
	//
	// | centre | sits on | length | palindrome |
	// | --- | --- | --- | --- |
	// | 0 | between bytes | 0 | _empty_ |
	// | 1 | byte `b` | 1 | `b` |
	// | 2 | between bytes | 0 | _empty_ |
	// | 3 | byte `a` | 1 | `a` |
	// | 4 | between bytes | 0 | _empty_ |
	// | 5 | byte `n` | 3 | `ana` |
	// | 6 | between bytes | 0 | _empty_ |
	// | 7 | byte `a` | 5 | `anana` |
	// | 8 | between bytes | 0 | _empty_ |
	// | 9 | byte `n` | 3 | `ana` |
	// | 10 | between bytes | 0 | _empty_ |
	// | 11 | byte `a` | 1 | `a` |
	// | 12 | between bytes | 0 | _empty_ |
	//
	// Between-byte centres are 0 everywhere here because `banana` has no two adjacent bytes alike. That is the even case costing nothing rather than being skipped.
	//
	// ## The longest palindromic substring
	//
	// | input | longest | at | length | palindromes |
	// | --- | --- | --- | --- | --- |
	// | `banana` | `anana` | 1 | 5 | 10 |
	// | `babad` | `bab` | 0 | 3 | 7 |
	// | `cbbd` | `bb` | 1 | 2 | 5 |
	// | `forgeeksskeegfor` | `geeksskeeg` | 3 | 10 | 23 |
	// | `abcde` | `a` | 0 | 1 | 5 |
	// | `aaaaaaaa` | `aaaaaaaa` | 0 | 8 | 36 |
	// | `#####` | `#####` | 0 | 5 | 15 |
	// | _empty_ | _none_ | 0 | 0 | 0 |
	//
	// Ties go to the leftmost, which is what makes the answer a function of the input and not of the scan order. A realm whose page depended on which equal-length match the loop happened to keep would render differently on two nodes running the same code.
	//
	// ## Counting counts positions
	//
	// `Count` asks how many palindromic substrings there are, by position: `aaa` is 6, not 3, because the three single bytes and the two pairs are distinct substrings that happen to read alike. A centre of length `r` holds `(r+1)/2` of them, one per length sharing its parity, so the total falls out of the same single pass.
	//
	// A constant run is the extreme: every substring of `aaaaaaaa` is a palindrome, all 36 of them, and listing them would cost quadratic output where counting them costs none.
	//
	// ## Maximal spans
	//
	// `Spans` returns the longest palindrome at each centre, skipping the empty ones. One per centre is what keeps the result small: the shorter palindromes nested inside each are implied by its length and parity.
	//
	// | start | length | substring |
	// | --- | --- | --- |
	// | 1 | 3 | `ana` |
	// | 1 | 5 | `anana` |
	// | 3 | 3 | `ana` |
	//
	// ## Why it belongs on chain
	//
	// Expanding around every centre is quadratic, and the input that triggers the worst case is a run of one byte: the cheapest string in the world to send. Manacher reads each new centre off its mirror inside the rightmost palindrome found so far, so no byte is compared twice and the worst case equals the best one. A scan over caller-supplied text whose cost the caller chooses is an attack, not bad luck.
	//
	// Offsets are **byte** offsets. gno strings are UTF-8 and a reversed multi-byte rune is a different byte sequence, so an accented word that reads as a palindrome is usually not one by bytes. Bytes are the right unit for slicing, and a caller doing rune arithmetic converts.
}
