// Package hangman is a classic hangman game for gno.land.
//
// The secret word rotates every ~"day" (a fixed span of blocks) and is chosen
// deterministically from a built-in word list using runtime.ChainHeight(). All
// players share a single game per day: guesses and the wrong-count are common
// state. Guess a letter to reveal every matching position, or lose a life. Six
// wrong guesses ends the game.
package hangman

import (
	"chain"
	"chain/runtime"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// blocksPerDay is the number of blocks that constitutes one "day" / one round.
// The secret word is fixed for the whole span, then rotates.
const blocksPerDay = 7200

// maxWrong is the number of wrong guesses allowed before the game is lost.
const maxWrong = 6

// words is the built-in dictionary. Kept lowercase, letters only.
var words = []string{
	"gnoland",
	"blockchain",
	"realm",
	"crossing",
	"deterministic",
	"contract",
	"validator",
	"consensus",
	"package",
	"namespace",
	"immutable",
	"transaction",
	"signature",
	"gopher",
	"hangman",
}

// round holds the shared state for a single day's game.
type round struct {
	word    string   // the secret word for this round (lowercase)
	guessed *avl.Tree // letter (string) -> struct{}; ordered set of guesses
	wrong   int      // number of wrong guesses so far
}

// rounds maps a day index (decimal string) to its round. Persisted across calls.
var rounds = avl.NewTree()

// dayIndex returns the current day index derived from block height.
func dayIndex() int64 {
	return runtime.ChainHeight() / blocksPerDay
}

// wordForDay picks a word deterministically from the list for the given day.
func wordForDay(day int64) string {
	n := int64(len(words))
	idx := day % n
	if idx < 0 {
		idx += n
	}
	return words[idx]
}

// dayKey formats a day index as a stable decimal string key.
func dayKey(day int64) string {
	neg := day < 0
	if neg {
		day = -day
	}
	if day == 0 {
		return "0"
	}
	var b []byte
	for day > 0 {
		b = append([]byte{byte('0' + day%10)}, b...)
		day /= 10
	}
	if neg {
		b = append([]byte{'-'}, b...)
	}
	return string(b)
}

// current returns (creating if needed) the round for the current day.
func current() *round {
	day := dayIndex()
	key := dayKey(day)
	if v, ok := rounds.Get(key); ok {
		return v.(*round)
	}
	r := &round{
		word:    wordForDay(day),
		guessed: avl.NewTree(),
		wrong:   0,
	}
	rounds.Set(key, r)
	return r
}

// normalizeLetter lowercases and validates a single a-z letter, returning it
// and true on success.
func normalizeLetter(letter string) (string, bool) {
	if len(letter) != 1 {
		return "", false
	}
	c := letter[0]
	if c >= 'A' && c <= 'Z' {
		c = c - 'A' + 'a'
	}
	if c < 'a' || c > 'z' {
		return "", false
	}
	return string(c), true
}

// isWon reports whether every letter of the word has been guessed.
func (r *round) isWon() bool {
	for i := 0; i < len(r.word); i++ {
		if !r.guessed.Has(string(r.word[i])) {
			return false
		}
	}
	return true
}

// isLost reports whether the wrong-count has reached the limit.
func (r *round) isLost() bool {
	return r.wrong >= maxWrong
}

// over reports whether the round is finished either way.
func (r *round) over() bool {
	return r.isWon() || r.isLost()
}

// Guess submits a single letter for the current day's shared game. It reveals
// matching letters or costs a life. Aborts on bad input or when the game is
// already over.
func Guess(cur realm, letter string) {
	c, ok := normalizeLetter(letter)
	if !ok {
		panic("guess must be a single letter a-z")
	}

	r := current()
	if r.over() {
		panic("today's game is already over")
	}
	if r.guessed.Has(c) {
		panic("letter already guessed: " + c)
	}

	r.guessed.Set(c, struct{}{})

	hit := strings.Contains(r.word, c)
	if !hit {
		r.wrong++
	}

	caller := unsafeCaller(cur)
	chain.Emit(
		"Guess",
		"letter", c,
		"hit", boolStr(hit),
		"wrong", itoa(int64(r.wrong)),
		"by", caller,
	)

	if r.isWon() {
		chain.Emit("Win", "day", dayKey(dayIndex()), "word", r.word)
	} else if r.isLost() {
		chain.Emit("Lose", "day", dayKey(dayIndex()), "word", r.word)
	}
}

// unsafeCaller returns the caller address as a string, preferring the crossing
// convention when available.
func unsafeCaller(cur realm) string {
	if cur.IsCurrent() {
		return cur.Previous().Address().String()
	}
	return ""
}

// boolStr renders a bool compactly.
func boolStr(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

// itoa renders an int64 as decimal (avl-free tiny helper reused by Render).
func itoa(n int64) string {
	return dayKey(n)
}

// masked returns the word with un-guessed letters shown as underscores.
func (r *round) masked() string {
	var sb strings.Builder
	for i := 0; i < len(r.word); i++ {
		ch := string(r.word[i])
		if r.guessed.Has(ch) {
			sb.WriteString(ch)
		} else {
			sb.WriteString("_")
		}
		if i != len(r.word)-1 {
			sb.WriteString(" ")
		}
	}
	return sb.String()
}

// guessedList returns the guessed letters in sorted order, space-joined.
func (r *round) guessedList() string {
	var out []string
	r.guessed.Iterate("", "", func(key string, _ interface{}) bool {
		out = append(out, key)
		return false
	})
	return strings.Join(out, " ")
}

// gallows renders the ASCII stage for the given wrong-count (0..6).
func gallows(wrong int) string {
	stages := []string{
		// 0
		"  +---+\n  |   |\n      |\n      |\n      |\n      |\n=========",
		// 1
		"  +---+\n  |   |\n  O   |\n      |\n      |\n      |\n=========",
		// 2
		"  +---+\n  |   |\n  O   |\n  |   |\n      |\n      |\n=========",
		// 3
		"  +---+\n  |   |\n  O   |\n /|   |\n      |\n      |\n=========",
		// 4
		"  +---+\n  |   |\n  O   |\n /|\\  |\n      |\n      |\n=========",
		// 5
		"  +---+\n  |   |\n  O   |\n /|\\  |\n /    |\n      |\n=========",
		// 6
		"  +---+\n  |   |\n  O   |\n /|\\  |\n / \\  |\n      |\n=========",
	}
	if wrong < 0 {
		wrong = 0
	}
	if wrong >= len(stages) {
		wrong = len(stages) - 1
	}
	return stages[wrong]
}

// Render shows the current day's game: gallows, masked word, guesses, status.
func Render(path string) string {
	r := current()

	var sb strings.Builder
	sb.WriteString("# 🪢 Hangman\n\n")
	sb.WriteString("A new secret word every day. Everyone shares the same game — guess a letter and see it revealed for all.\n\n")
	sb.WriteString("Day: `" + dayKey(dayIndex()) + "` · Block: `" + itoa(runtime.ChainHeight()) + "`\n\n")

	sb.WriteString("```\n")
	sb.WriteString(gallows(r.wrong))
	sb.WriteString("\n```\n\n")

	sb.WriteString("## Word\n\n")
	sb.WriteString("`" + r.masked() + "`\n\n")

	sb.WriteString("Wrong: **" + itoa(int64(r.wrong)) + " / " + itoa(int64(maxWrong)) + "**  ·  Lives left: **" + itoa(int64(maxWrong-r.wrong)) + "**\n\n")

	guesses := r.guessedList()
	if guesses == "" {
		guesses = "_(none yet)_"
	}
	sb.WriteString("Guessed letters: " + guesses + "\n\n")

	sb.WriteString("## Status\n\n")
	switch {
	case r.isWon():
		sb.WriteString("🎉 **Solved!** The word was **" + r.word + "**.\n\n")
	case r.isLost():
		sb.WriteString("💀 **Game over.** The word was **" + r.word + "**. Try again next day.\n\n")
	default:
		sb.WriteString("Game in progress. Call `Guess(\"a\")` with a letter.\n\n")
	}

	sb.WriteString("---\n\n")
	sb.WriteString("### How to play\n\n")
	sb.WriteString("- `Guess(cur, \"e\")` — guess a single letter `a`–`z`.\n")
	sb.WriteString("- A hit reveals every matching position; a miss costs one of 6 lives.\n")
	sb.WriteString("- The word rotates every ~" + itoa(int64(blocksPerDay)) + " blocks.\n")
	return sb.String()
}
