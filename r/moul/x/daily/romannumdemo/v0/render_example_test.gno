package romannumdemo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Roman numeral converter
	//
	// A tiny demo of the [`p/moul/x/daily/romannum`](/p/moul/x/daily/romannum/v0) library — the classic `ToRoman` / `FromRoman` kata. Pure and deterministic.
	//
	// ## Examples
	//
	// | decimal | roman |
	// |---:|:---|
	// | [1](/r/moul/x/daily/romannumdemo/v0:1) | I |
	// | [4](/r/moul/x/daily/romannumdemo/v0:4) | IV |
	// | [9](/r/moul/x/daily/romannumdemo/v0:9) | IX |
	// | [14](/r/moul/x/daily/romannumdemo/v0:14) | XIV |
	// | [40](/r/moul/x/daily/romannumdemo/v0:40) | XL |
	// | [49](/r/moul/x/daily/romannumdemo/v0:49) | XLIX |
	// | [90](/r/moul/x/daily/romannumdemo/v0:90) | XC |
	// | [400](/r/moul/x/daily/romannumdemo/v0:400) | CD |
	// | [900](/r/moul/x/daily/romannumdemo/v0:900) | CM |
	// | [1994](/r/moul/x/daily/romannumdemo/v0:1994) | MCMXCIV |
	// | [2024](/r/moul/x/daily/romannumdemo/v0:2024) | MMXXIV |
	// | [3888](/r/moul/x/daily/romannumdemo/v0:3888) | MMMDCCCLXXXVIII |
	// | [3999](/r/moul/x/daily/romannumdemo/v0:3999) | MMMCMXCIX |
	//
	// ## Try it
	//
	// - `:/<n>` — integer → Roman, e.g. `:/2024` → MMXXIV
	// - `:/r/<roman>` — Roman → integer, e.g. `:/r/MMXXIV` → 2024
}
