package bullscows

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// clear restores the globals to their init() state so assertions do not depend
// on which tests ran first. Realm globals live for the whole test binary.
func clear() {
	round = 1
	attempts = 0
	history = nil
	records = nil
	secret = newSecret(seedFor(round))
}

// ExampleRender pins the fresh-round view: no guesses, empty leaderboard.
func ExampleRender() {
	clear()
	print(Render(""))
	// Output:
	// # Bulls & Cows
	//
	// One shared secret 4-digit code (no repeated digits). Call `Guess("1972")` to get **bulls** (right digit, right spot) and **cows** (right digit, wrong spot). First to 4 bulls wins the round; `GiveUp()` reveals the code and starts over.
	//
	// ## Round 1
	//
	// Attempts so far: **0**
	//
	// _No guesses yet this round — be the first._
	//
	// ## Leaderboard (fastest solves)
	//
	// _Nobody has cracked a code yet._
}

// TestRenderHistoryNewestFirst checks the guess table is reverse-chronological.
func TestRenderHistoryNewestFirst(t *testing.T) {
	clear()
	addHistory(guessLog{player: "alice", guess: "1234", bulls: 1, cows: 2})
	addHistory(guessLog{player: "bob", guess: "5678", bulls: 0, cows: 1})

	out := Render("")
	uassert.True(t, strings.Contains(out, "### Recent guesses"), "history section should appear")
	uassert.True(t, strings.Contains(out, "| bob | 5678 | 0 | 1 |\n| alice | 1234 | 1 | 2 |\n"),
		"newest guess should be listed first")
	uassert.False(t, strings.Contains(out, "_No guesses yet"), "empty-history notice should be gone")
}

// TestRenderLeaderboard checks solved records render in rank order.
func TestRenderLeaderboard(t *testing.T) {
	clear()
	addRecord(record{player: "carol", attempts: 3, round: 1})
	addRecord(record{player: "dave", attempts: 7, round: 2})

	out := Render("")
	uassert.True(t, strings.Contains(out, "| 1 | carol | 3 | 1 |\n| 2 | dave | 7 | 2 |\n"),
		"leaderboard should rank fastest first")
	uassert.False(t, strings.Contains(out, "_Nobody has cracked a code yet._"),
		"empty-leaderboard notice should be gone")
}

// TestRenderShortensLongAddresses checks the bech32 addresses players actually
// have get elided rather than blowing out the table.
func TestRenderShortensLongAddresses(t *testing.T) {
	clear()
	long := "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
	addHistory(guessLog{player: long, guess: "1234", bulls: 0, cows: 0})

	out := Render("")
	uassert.False(t, strings.Contains(out, long), "full address should not be rendered")
	uassert.True(t, strings.Contains(out, "| "+long[:6]+"…"+long[len(long)-4:]+" | 1234 |"),
		"address should be shortened to prefix…suffix")
}

// TestRenderTracksRoundAndAttempts checks the counters reach the page.
func TestRenderTracksRoundAndAttempts(t *testing.T) {
	clear()
	round = 4
	attempts = 11

	out := Render("")
	uassert.True(t, strings.Contains(out, "## Round 4\n"), "round should be shown")
	uassert.True(t, strings.Contains(out, "Attempts so far: **11**"), "attempts should be shown")
}

// TestRenderIgnoresPath documents that Render has no sub-routes.
func TestRenderIgnoresPath(t *testing.T) {
	clear()
	uassert.Equal(t, Render(""), Render("/anything"))
}
