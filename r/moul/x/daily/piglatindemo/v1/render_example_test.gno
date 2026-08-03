package piglatindemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Pig Latin
	//
	// Demo of the [`p/moul/x/daily/piglatin`](/p/moul/x/daily/piglatin/v1) library — a tiny port of the classic **Pig Latin** translator (the go-to beginner exercise). Pure `strings`/`unicode`, fully deterministic.
	//
	// ## Rules
	//
	// 1. Word starts with a **vowel** → append `way`. `apple` → `appleway`
	// 2. Word starts with **consonant(s)** → move the leading consonant cluster to the end, then add `ay`. `string` → `ingstray`
	// 3. `y` is a consonant only as the first letter (`yellow` → `ellowyay`); otherwise a vowel (`myth` → `ythmay`).
	// 4. **Capitalization** is preserved: `Hello` → `Ellohay`, `NASA` → `ASANAY`.
	// 5. **Punctuation** glued to a word stays put: `Hello,` → `Ellohay,`.
	//
	// ## Try it
	//
	// Append a sentence to the path — spaces are fine:
	//
	// - [`/hello world`](/r/moul/x/daily/piglatindemo/v1:/hello world) → `ellohay orldway`
	// - [`/The quick brown fox`](/r/moul/x/daily/piglatindemo/v1:/The quick brown fox) → `Ethay uickqay ownbray oxfay`
	// - [`/I love Gno!`](/r/moul/x/daily/piglatindemo/v1:/I love Gno!) → `Iway ovelay Ognay!`
	//
	// ## Examples
	//
	// | Input | Pig Latin |
	// |---|---|
	// | `pig` | `igpay` |
	// | `banana` | `ananabay` |
	// | `smile` | `ilesmay` |
	// | `eat` | `eatway` |
	// | `yellow` | `ellowyay` |
	// | `myth` | `ythmay` |
	// | `Hello,` | `Ellohay,` |
	// | `GNO` | `OGNAY` |
}
