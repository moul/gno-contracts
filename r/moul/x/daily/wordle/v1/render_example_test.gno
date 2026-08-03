package wordle

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # 🟩 Daily Word Puzzle
	//
	// A Wordle-like game. Everyone gets the same secret 5-letter word each "day" (a span of blocks). You have 6 attempts.
	//
	// **Day #0**
	//
	// _No guesses yet today._
	//
	// ## Rules
	//
	// - Guess the 5-letter word in 6 tries: `Guess("crane")`.
	// - 🟩 correct letter, correct spot.
	// - 🟨 correct letter, wrong spot.
	// - ⬜ letter not in the word.
	// - The word changes every day (deterministic from block height).
}
