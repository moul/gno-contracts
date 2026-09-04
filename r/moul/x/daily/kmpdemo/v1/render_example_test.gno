package kmpdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Knuth–Morris–Pratt
	//
	// Linear-time substring search, demoing the [`p/moul/x/daily/kmp`](/p/moul/x/daily/kmp/v1) library.
	//
	// ## Failure table
	//
	// For each prefix of `issi`, the length of the longest proper prefix that is also a suffix. This is what lets the scan slide the pattern without ever rewinding the text.
	//
	// | i | prefix | table |
	// |---|---|---|
	// | 0 | `i` | 0 |
	// | 1 | `is` | 0 |
	// | 2 | `iss` | 0 |
	// | 3 | `issi` | 1 |
	//
	// ## Searching
	//
	// `issi` in `mississippi`:
	//
	// ```
	// mississippi
	//  ^^^^
	//     ^^^^
	// ```
	//
	// Matches at `1`, `4` — **overlapping**, and `Count` agrees: 2.
	//
	// ## Overlap is deliberate
	//
	// `FindAll("aaaa", "aa")` returns `0`, `1`, `2`, not just the disjoint ones — "every occurrence" read honestly. A caller wanting disjoint matches can filter; one wanting overlap could not recover it.
	//
	// ## Why it belongs on chain
	//
	// The naive scan is O(n·m): `aaaaaaaab` inside `aaaaaaaaaaaaaaaab` re-compares everything it already matched. KMP is O(n+m) with no bad case, so a pathological input is not an attack.
}
