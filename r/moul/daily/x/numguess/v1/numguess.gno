// Package numguess is a Number Guessing Game realm.
//
// A hidden target in 1..100 is derived deterministically from the block height
// at which the round started. Players call Guess(n) to receive "higher",
// "lower" or "correct". When a round is solved the winner is recorded on the
// leaderboard (ranked by fewest guesses) and anyone can start a fresh round.
package numguess

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// round holds the mutable state of the active game round.
type round struct {
	number      int    // 1-based round counter
	startHeight int64  // block height the round began at (entropy source)
	target      int    // hidden value in 1..100
	solved      bool   // set once someone guesses correctly
	lastHint    string // "higher" / "lower" / "correct" / "" for none yet
	winner      string // address of the solver, once solved
	winnerTries int    // attempts the winner needed
}

// winRecord is one leaderboard entry.
type winRecord struct {
	addr   string
	round  int
	tries  int
	target int
}

var (
	current *round
	// attempts counts guesses per address for the CURRENT round only.
	attempts = avl.NewTree() // addr(string) -> *int
	// leaderboard is append-only across all rounds; sorted on render.
	leaderboard []winRecord
)

func init() {
	current = newRound(1, runtime.ChainHeight())
}

// newRound builds a fresh round whose target derives deterministically from
// the start height. Gno has no runtime RNG, so height is the only entropy.
func newRound(number int, height int64) *round {
	return &round{
		number:      number,
		startHeight: height,
		target:      targetFromHeight(height),
		solved:      false,
		lastHint:    "",
	}
}

// targetFromHeight maps a block height to a hidden number in 1..100.
// Deterministic and cheap: a small integer mix so consecutive rounds don't
// land on obviously adjacent targets.
func targetFromHeight(h int64) int {
	if h < 0 {
		h = -h
	}
	mixed := (h*2654435761 + 12345)
	if mixed < 0 {
		mixed = -mixed
	}
	return int(mixed%100) + 1
}

// Guess submits a guess for the current round. It records the caller's attempt
// count and returns "higher", "lower" or "correct". Crossing function: caller
// invokes as Guess(cross(cur), n).
func Guess(cur realm, n int) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	if n < 1 || n > 100 {
		panic("guess must be in 1..100")
	}
	if current.solved {
		panic("round already solved; call NewRound to start a fresh one")
	}

	caller := cur.Previous().Address().String()
	incAttempt(caller)

	var hint string
	switch {
	case n < current.target:
		hint = "higher"
	case n > current.target:
		hint = "lower"
	default:
		hint = "correct"
		current.solved = true
		current.winner = caller
		current.winnerTries = attemptsOf(caller)
		leaderboard = append(leaderboard, winRecord{
			addr:   caller,
			round:  current.number,
			tries:  current.winnerTries,
			target: current.target,
		})
		chain.Emit("RoundSolved",
			"round", strconv.Itoa(current.number),
			"winner", caller,
			"tries", strconv.Itoa(current.winnerTries),
		)
	}

	current.lastHint = hint
	return hint
}

// NewRound resets the game with a fresh target when the current round is
// solved. Panics if the current round is still open. Crossing function.
func NewRound(cur realm) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	if !current.solved {
		panic("current round is not solved yet")
	}

	next := current.number + 1
	current = newRound(next, runtime.ChainHeight())
	attempts = avl.NewTree() // per-round attempt counters reset
	chain.Emit("NewRound", "round", strconv.Itoa(next))
	return "round " + strconv.Itoa(next) + " started"
}

// incAttempt bumps the caller's attempt counter for the current round.
func incAttempt(addr string) {
	if v, ok := attempts.Get(addr); ok {
		p := v.(*int)
		*p++
		return
	}
	one := 1
	attempts.Set(addr, &one)
}

// attemptsOf returns how many guesses addr has made this round.
func attemptsOf(addr string) int {
	if v, ok := attempts.Get(addr); ok {
		return *(v.(*int))
	}
	return 0
}

// totalAttempts sums all attempts made in the current round.
func totalAttempts() int {
	total := 0
	attempts.Iterate("", "", func(_ string, v any) bool {
		total += *(v.(*int))
		return false
	})
	return total
}

// Render produces the gnoweb Markdown view of the current game state.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Number Guessing Game\n\n")
	b.WriteString("Guess the hidden number between **1** and **100**. ")
	b.WriteString("Each round's target is derived deterministically from the block height at which it started.\n\n")

	b.WriteString("## Current round\n\n")
	b.WriteString("- Round: **" + strconv.Itoa(current.number) + "**\n")
	b.WriteString("- Started at block height: " + strconv.FormatInt(current.startHeight, 10) + "\n")
	b.WriteString("- Attempts so far (this round): " + strconv.Itoa(totalAttempts()) + "\n")

	hint := current.lastHint
	if hint == "" {
		hint = "_no guesses yet_"
	} else {
		hint = "`" + hint + "`"
	}
	b.WriteString("- Last hint: " + hint + "\n")

	if current.solved {
		b.WriteString("- Status: **solved** by `" + current.winner + "` in " +
			strconv.Itoa(current.winnerTries) + " guess(es). ")
		b.WriteString("Call `NewRound()` to play again.\n")
	} else {
		b.WriteString("- Status: **open** — call `Guess(n)` to play.\n")
	}
	b.WriteString("\n")

	b.WriteString("## Leaderboard\n\n")
	b.WriteString(renderLeaderboard())

	b.WriteString("\n## How to play\n\n")
	b.WriteString("```\n")
	b.WriteString("Guess(n)     // n in 1..100 -> \"higher\" | \"lower\" | \"correct\"\n")
	b.WriteString("NewRound()   // start a fresh round once the current one is solved\n")
	b.WriteString("```\n")

	return b.String()
}

// renderLeaderboard formats winners ranked by fewest guesses (ties: earlier
// round first). Sorted on a copy so state is untouched.
func renderLeaderboard() string {
	if len(leaderboard) == 0 {
		return "_No winners yet — be the first!_\n"
	}

	ranked := make([]winRecord, len(leaderboard))
	copy(ranked, leaderboard)
	sortByFewestTries(ranked)

	var b strings.Builder
	b.WriteString("| Rank | Player | Round | Guesses | Target |\n")
	b.WriteString("|---|---|---|---|---|\n")
	for i, w := range ranked {
		b.WriteString("| " + strconv.Itoa(i+1) + " | `" + w.addr + "` | " +
			strconv.Itoa(w.round) + " | " + strconv.Itoa(w.tries) + " | " +
			strconv.Itoa(w.target) + " |\n")
	}
	return b.String()
}

// sortByFewestTries does an in-place insertion sort: fewer tries first, then
// earlier round first on ties. Small n; insertion sort keeps it deterministic
// and dependency-free.
func sortByFewestTries(rs []winRecord) {
	for i := 1; i < len(rs); i++ {
		j := i
		for j > 0 && less(rs[j], rs[j-1]) {
			rs[j], rs[j-1] = rs[j-1], rs[j]
			j--
		}
	}
}

func less(a, b winRecord) bool {
	if a.tries != b.tries {
		return a.tries < b.tries
	}
	return a.round < b.round
}
