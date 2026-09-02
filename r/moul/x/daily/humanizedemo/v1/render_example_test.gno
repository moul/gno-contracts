package humanizedemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Humanize
	//
	// Integer-only formatting for people, demoing the [`p/moul/x/daily/humanize`](/p/moul/x/daily/humanize/v1) library.
	//
	// ## Bytes
	//
	// | n | rendered |
	// |---|---|
	// | `0` | 0 B |
	// | `999` | 999 B |
	// | `1024` | 1 KiB |
	// | `1536` | 1.5 KiB |
	// | `1048576` | 1 MiB |
	// | `1073741824` | 1 GiB |
	//
	// ## Thousands
	//
	// | n | rendered |
	// |---|---|
	// | `0` | 0 |
	// | `1000` | 1,000 |
	// | `1234567` | 1,234,567 |
	//
	// ## Ordinals
	//
	// `1st` · `2nd` · `3rd` · `11th` · `12th` · `13th` · `21st` · `101st`
	//
	// > 11th/12th/13th, not 11st/12nd/13rd — the teens are the trap.
	//
	// ## Block counts
	//
	// | blocks | rendered |
	// |---|---|
	// | `0` | now |
	// | `1` | 1 block |
	// | `15` | ~10 blocks |
	// | `1234` | ~1,200 blocks |
	//
	// > Deliberately vague, and in **blocks**: there is no wall clock on chain, so "about 2 hours" would be a lie dressed as precision.
}
