// Package wordle is a daily five-letter word puzzle realm for gno.land.
//
// The day's secret word is picked deterministically from the current block
// height (a "day index"), so every player faces the same word for the same
// span of blocks. Players submit guesses with Guess; each guess is scored
// letter-by-letter with emoji feedback (🟩 correct spot, 🟨 wrong spot,
// ⬜ absent). Render shows the caller's board, attempts left, and rules.
package wordle

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strings"
)

// maxAttempts is the number of guesses a player gets per day.
const maxAttempts = 6

// wordLen is the fixed length of every word / guess.
const wordLen = 5

// blocksPerDay controls how many blocks share the same secret word. Testnet
// blocks are fast, so this is a pragmatic "day" for a demo puzzle rather than
// a wall-clock day. Deterministic: derived only from block height.
const blocksPerDay = 17280

// words is the built-in dictionary of candidate secret words. All entries are
// exactly wordLen lowercase letters.
var words = []string{
	"crane",
	"slate",
	"pride",
	"ghost",
	"lunar",
	"mango",
	"vivid",
	"quilt",
	"brave",
	"flame",
	"storm",
	"pearl",
	"trout",
	"zebra",
	"cabin",
}

// board holds one player's guesses for a given day.
type board struct {
	day     int64
	guesses []string // raw lowercase guessed words, in order
	won     bool
}

// players maps a caller address string to that player's current board.
// A plain map is fine here: keys are addresses, iteration order is never
// used for rendering (we only ever look up the caller's own board).
var players = map[string]*board{}

// dayIndex returns the deterministic day index for a given block height.
func dayIndex(height int64) int64 {
	if height < 0 {
		height = 0
	}
	return height / blocksPerDay
}

// wordForDay returns the secret word for the given day index. Deterministic:
// a pure function of the day index and the built-in dictionary.
func wordForDay(day int64) string {
	n := int64(len(words))
	idx := day % n
	if idx < 0 {
		idx += n
	}
	return words[idx]
}

// currentDay returns today's day index from the chain height.
func currentDay() int64 {
	return dayIndex(runtime.ChainHeight())
}

// score compares a guess against the secret and returns wordLen emoji tiles:
// 🟩 right letter right spot, 🟨 right letter wrong spot, ⬜ letter absent.
// Standard Wordle two-pass scoring so duplicate letters are handled correctly.
func score(guess, secret string) string {
	g := []rune(guess)
	s := []rune(secret)

	tiles := make([]string, wordLen)
	// counts of each secret letter still available to match as 🟨.
	counts := map[rune]int{}

	// First pass: greens.
	for i := 0; i < wordLen; i++ {
		if g[i] == s[i] {
			tiles[i] = "🟩"
		} else {
			counts[s[i]]++
		}
	}
	// Second pass: yellows / greys.
	for i := 0; i < wordLen; i++ {
		if tiles[i] == "🟩" {
			continue
		}
		if counts[g[i]] > 0 {
			tiles[i] = "🟨"
			counts[g[i]]--
		} else {
			tiles[i] = "⬜"
		}
	}
	return strings.Join(tiles, "")
}

// isFiveLetters reports whether w is exactly wordLen ASCII lowercase letters.
func isFiveLetters(w string) bool {
	if len(w) != wordLen {
		return false
	}
	for i := 0; i < len(w); i++ {
		c := w[i]
		if c < 'a' || c > 'z' {
			return false
		}
	}
	return true
}

// Guess records a five-letter guess for the caller against today's word.
//
// It is a crossing (state-mutating) function: callers invoke it as
// Guess(cross(cur), "crane"). Identity is taken from the live crossing frame
// after the IsCurrent authentication check.
func Guess(cur realm, word string) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	caller := cur.Previous().Address().String()

	word = strings.ToLower(strings.TrimSpace(word))
	if !isFiveLetters(word) {
		panic("guess must be exactly 5 lowercase letters a-z")
	}

	day := currentDay()
	b := players[caller]
	if b == nil || b.day != day {
		// New player, or a new day rolled over: reset the board.
		b = &board{day: day}
		players[caller] = b
	}

	if b.won {
		panic("you already solved today's word")
	}
	if len(b.guesses) >= maxAttempts {
		panic("no attempts left today")
	}

	b.guesses = append(b.guesses, word)
	if word == wordForDay(day) {
		b.won = true
	}
}

// Render returns the caller's board as Markdown. It is NOT a crossing function
// (no cur realm parameter). It reads the viewer via the stack-walking
// unsafe.PreviousRealm(); an unknown viewer simply sees an empty board.
func Render(path string) string {
	viewer := unsafe.PreviousRealm().Address().String()
	day := currentDay()

	var sb strings.Builder
	sb.WriteString("# 🟩 Daily Word Puzzle\n\n")
	sb.WriteString("A Wordle-like game. Everyone gets the same secret 5-letter word each ")
	sb.WriteString("\"day\" (a span of blocks). You have ")
	sb.WriteString(itoa(maxAttempts))
	sb.WriteString(" attempts.\n\n")

	sb.WriteString("**Day #")
	sb.WriteString(i64toa(day))
	sb.WriteString("**\n\n")

	b := players[viewer]
	if b == nil || b.day != day {
		sb.WriteString("_No guesses yet today._\n\n")
		writeRules(&sb)
		return sb.String()
	}

	secret := wordForDay(day)
	sb.WriteString("## Your board\n\n")
	for _, g := range b.guesses {
		sb.WriteString(score(g, secret))
		sb.WriteString("  `")
		sb.WriteString(strings.ToUpper(g))
		sb.WriteString("`\n\n")
	}

	left := maxAttempts - len(b.guesses)
	switch {
	case b.won:
		sb.WriteString("🎉 **You solved it!** Come back next day for a new word.\n\n")
	case left <= 0:
		sb.WriteString("💀 **Out of attempts.** The word was `")
		sb.WriteString(strings.ToUpper(secret))
		sb.WriteString("`. Try again next day.\n\n")
	default:
		sb.WriteString("**Attempts left:** ")
		sb.WriteString(itoa(left))
		sb.WriteString("\n\n")
	}

	writeRules(&sb)
	return sb.String()
}

// writeRules appends the legend / how-to-play block.
func writeRules(sb *strings.Builder) {
	sb.WriteString("## Rules\n\n")
	sb.WriteString("- Guess the 5-letter word in ")
	sb.WriteString(itoa(maxAttempts))
	sb.WriteString(" tries: `Guess(\"crane\")`.\n")
	sb.WriteString("- 🟩 correct letter, correct spot.\n")
	sb.WriteString("- 🟨 correct letter, wrong spot.\n")
	sb.WriteString("- ⬜ letter not in the word.\n")
	sb.WriteString("- The word changes every day (deterministic from block height).\n")
}

// itoa formats a small non-negative int (attempt counts) without importing
// strconv, keeping the dependency surface minimal.
func itoa(n int) string {
	return i64toa(int64(n))
}

// i64toa formats an int64 as decimal.
func i64toa(n int64) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var digits []byte
	for n > 0 {
		digits = append(digits, byte('0'+n%10))
		n /= 10
	}
	// reverse
	for i, j := 0, len(digits)-1; i < j; i, j = i+1, j-1 {
		digits[i], digits[j] = digits[j], digits[i]
	}
	if neg {
		return "-" + string(digits)
	}
	return string(digits)
}
