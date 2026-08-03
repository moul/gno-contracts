package markovdemo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Markov Babbler
	//
	// A demo of the [`p/moul/x/daily/markov`](/p/moul/x/daily/markov/v1) library — an on-chain port of Go's classic *"Generating arbitrary text: a Markov chain algorithm"* codewalk. Every two-word **prefix** maps to the words that followed it; `Generate` walks that chain, picking suffixes with a PRNG seeded by the block height — deterministic, yet different each block.
	//
	// ## Fresh sample (40 words, height 123)
	//
	// > it was the age of foolishness i am the master of my soul
	//
	// ## Corpus
	//
	// - **Words:** 48
	// - **Distinct prefixes:** 33
	// - **Prefix length:** 2 words
	//
	// ## Some prefixes → suffixes
	//
	// | prefix | can be followed by |
	// |---|---|
	// | `_(start)_` | it |
	// | ` it` | was |
	// | `a free` | man |
	// | `a number` | i |
	// | `age of` | wisdom, foolishness |
	// | `am a` | free |
	// | `am not` | a |
	// | `am the` | master, captain |
	// | `best of` | times |
	// | `captain of` | my |
	// | `fate i` | am |
	// | `foolishness i` | am |
	//
	// _Call `Feed("your text here")` to teach it new words, then reload for a new sample._
}
