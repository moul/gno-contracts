package romannumdemo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Roman numeral converter
	//
	// A tiny demo of the [`p/moul/x/daily/romannum`](/p/moul/x/daily/romannum/v1) library — the classic `ToRoman` / `FromRoman` kata. Pure and deterministic.
	//
	// ## Examples
	//
	// | decimal | roman |
	// |---:|:---|
	// | [1](/r/moul/x/daily/romannumdemo/v1:1) | I |
	// | [4](/r/moul/x/daily/romannumdemo/v1:4) | IV |
	// | [9](/r/moul/x/daily/romannumdemo/v1:9) | IX |
	// | [14](/r/moul/x/daily/romannumdemo/v1:14) | XIV |
	// | [40](/r/moul/x/daily/romannumdemo/v1:40) | XL |
	// | [49](/r/moul/x/daily/romannumdemo/v1:49) | XLIX |
	// | [90](/r/moul/x/daily/romannumdemo/v1:90) | XC |
	// | [400](/r/moul/x/daily/romannumdemo/v1:400) | CD |
	// | [900](/r/moul/x/daily/romannumdemo/v1:900) | CM |
	// | [1994](/r/moul/x/daily/romannumdemo/v1:1994) | MCMXCIV |
	// | [2024](/r/moul/x/daily/romannumdemo/v1:2024) | MMXXIV |
	// | [3888](/r/moul/x/daily/romannumdemo/v1:3888) | MMMDCCCLXXXVIII |
	// | [3999](/r/moul/x/daily/romannumdemo/v1:3999) | MMMCMXCIX |
	//
	// ## Try it
	//
	// - `:/<n>` — integer → Roman, e.g. `:/2024` → MMXXIV
	// - `:/r/<roman>` — Roman → integer, e.g. `:/r/MMXXIV` → 2024
}
