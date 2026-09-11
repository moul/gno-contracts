// Package closestguess is a blind, multiplayer number-guessing puzzle.
//
// Unlike a classic higher/lower guessing game, closestguess gives NO feedback
// per guess. Each round hides a target in 1..1000 (derived deterministically
// from the block height the round started at); every address may submit
// exactly one blind Guess for the round. Whenever someone calls Reveal, the
// round closes: the target is disclosed, the guess with the smallest absolute
// distance wins (ties go to whoever guessed first), the winner is recorded on
// the leaderboard, and a fresh round starts immediately.
package closestguess

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"
)

const (
	minTarget = 1
	maxTarget = 1000
)

// roundT holds the mutable state of the open round. The target stays hidden
// (never rendered, never returned) until Reveal closes the round.
type roundT struct {
	number      int
	startHeight int64
	target      int
}

// winRecord is one closed-round result, kept for the leaderboard.
type winRecord struct {
	round    int
	winner   string
	target   int
	guess    int
	distance int
	players  int
}

// guessEntry is one address's blind guess for the current round.
type guessEntry struct {
	addr string
	n    int
}

var (
	current *roundT
	// entries holds one guessEntry per address for the CURRENT round only, in
	// submission order (so Reveal can break distance ties in favor of
	// whoever guessed first). Reset on every Reveal. A plain slice is fine
	// here: rounds are player-scoped and small, unlike long-lived global
	// state where avl.Tree would matter.
	entries []guessEntry
	// leaderboard is append-only across all rounds; sorted on render.
	leaderboard []winRecord
)

func init() {
	current = newRound(1, runtime.ChainHeight())
}

// newRound builds a fresh round whose hidden target derives deterministically
// from the start height and round number. Gno has no runtime RNG, so mixing
// height with the round number is the only available entropy, and it also
// keeps consecutive rounds at the same height from repeating a target.
func newRound(number int, height int64) *roundT {
	return &roundT{
		number:      number,
		startHeight: height,
		target:      targetFromHeight(height, number),
	}
}

func targetFromHeight(h int64, round int) int {
	if h < 0 {
		h = -h
	}
	span := int64(maxTarget - minTarget + 1)
	mixed := h*2654435761 + int64(round)*40503 + 12345
	if mixed < 0 {
		mixed = -mixed
	}
	return int(mixed%span) + minTarget
}

// Guess records the caller's single blind guess for the current round. It
// returns no hint about correctness — that is the whole point of the puzzle.
// Crossing function: caller invokes as Guess(cross(cur), n).
func Guess(cur realm, n int) string {
	if n < minTarget || n > maxTarget {
		panic("guess must be in " + strconv.Itoa(minTarget) + ".." + strconv.Itoa(maxTarget))
	}

	caller := cur.Previous().Address().String()
	if hasGuessed(caller) {
		panic("you already guessed this round; wait for Reveal()")
	}

	entries = append(entries, guessEntry{addr: caller, n: n})

	chain.Emit("GuessSubmitted",
		"round", strconv.Itoa(current.number),
		"player", caller,
	)

	return "guess recorded for round " + strconv.Itoa(current.number) + " (" +
		strconv.Itoa(len(entries)) + " player(s) so far) — call Reveal() to see who's closest"
}

func hasGuessed(addr string) bool {
	for _, e := range entries {
		if e.addr == addr {
			return true
		}
	}
	return false
}

// Reveal closes the current round: discloses the target, crowns whoever
// landed closest (ties favor the earliest guesser), records a leaderboard
// entry, and opens a fresh round. Panics if nobody has guessed yet.
// Crossing function.
func Reveal(cur realm) string {
	if len(entries) == 0 {
		panic("no guesses submitted yet this round")
	}

	target := current.target
	winner := entries[0]
	best := distance(winner.n, target)
	for _, e := range entries[1:] {
		if d := distance(e.n, target); d < best {
			best = d
			winner = e
		}
	}

	rec := winRecord{
		round:    current.number,
		winner:   winner.addr,
		target:   target,
		guess:    winner.n,
		distance: best,
		players:  len(entries),
	}
	leaderboard = append(leaderboard, rec)

	chain.Emit("RoundRevealed",
		"round", strconv.Itoa(rec.round),
		"winner", winner.addr,
		"target", strconv.Itoa(target),
		"distance", strconv.Itoa(best),
	)

	closedRound := current.number
	current = newRound(closedRound+1, runtime.ChainHeight())
	entries = nil

	return "round " + strconv.Itoa(closedRound) + " revealed: target was " + strconv.Itoa(target) +
		" — " + shortAddr(winner.addr) + " wins, guessed " + strconv.Itoa(winner.n) +
		" (distance " + strconv.Itoa(best) + ") among " + strconv.Itoa(rec.players) +
		" player(s). Round " + strconv.Itoa(current.number) + " is now open."
}

func distance(guess, target int) int {
	d := guess - target
	if d < 0 {
		d = -d
	}
	return d
}

// Render produces the gnoweb Markdown view. The current round's target and
// individual guess values are never shown — only the player count — so
// rendering the page can't leak the puzzle.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Closest Guess\n\n")
	b.WriteString("A blind, multiplayer number-guessing puzzle. Each round hides a target in ")
	b.WriteString("**" + strconv.Itoa(minTarget) + ".." + strconv.Itoa(maxTarget) + "**. ")
	b.WriteString("Call `Guess(n)` once per round — you get no feedback. ")
	b.WriteString("Anyone can call `Reveal()` to close the round: the target is disclosed and ")
	b.WriteString("whoever landed closest wins.\n\n")

	b.WriteString("## Current round\n\n")
	b.WriteString("- Round: **" + strconv.Itoa(current.number) + "**\n")
	b.WriteString("- Started at block height: " + strconv.FormatInt(current.startHeight, 10) + "\n")
	b.WriteString("- Players guessed so far: " + strconv.Itoa(len(entries)) + "\n")
	b.WriteString("- Status: **open** — target hidden until `Reveal()` is called.\n\n")

	b.WriteString("## Leaderboard (closest-ever wins)\n\n")
	b.WriteString(renderLeaderboard())

	b.WriteString("\n## How to play\n\n")
	b.WriteString("```\n")
	b.WriteString("Guess(n)   // n in 1..1000, one shot per address per round, no feedback\n")
	b.WriteString("Reveal()   // closes the round: reveals target, crowns the closest guess\n")
	b.WriteString("```\n")

	return b.String()
}

// renderLeaderboard formats closed rounds ranked by smallest distance (ties:
// earlier round first). Sorted on a copy so state is untouched.
func renderLeaderboard() string {
	if len(leaderboard) == 0 {
		return "_No round has been revealed yet — be the first to call `Reveal()`!_\n"
	}

	ranked := make([]winRecord, len(leaderboard))
	copy(ranked, leaderboard)
	sortByClosest(ranked)

	var b strings.Builder
	b.WriteString("| Rank | Player | Round | Target | Guess | Distance | Players |\n")
	b.WriteString("|---|---|---|---|---|---|---|\n")
	for i, w := range ranked {
		b.WriteString("| " + strconv.Itoa(i+1) + " | `" + shortAddr(w.winner) + "` | " +
			strconv.Itoa(w.round) + " | " + strconv.Itoa(w.target) + " | " +
			strconv.Itoa(w.guess) + " | " + strconv.Itoa(w.distance) + " | " +
			strconv.Itoa(w.players) + " |\n")
	}
	return b.String()
}

// sortByClosest does an in-place insertion sort: smallest distance first,
// then earlier round first on ties. Small n; insertion sort keeps it
// deterministic and dependency-free.
func sortByClosest(rs []winRecord) {
	for i := 1; i < len(rs); i++ {
		j := i
		for j > 0 && closer(rs[j], rs[j-1]) {
			rs[j], rs[j-1] = rs[j-1], rs[j]
			j--
		}
	}
}

func closer(a, b winRecord) bool {
	if a.distance != b.distance {
		return a.distance < b.distance
	}
	return a.round < b.round
}

func shortAddr(a string) string {
	if len(a) <= 12 {
		return a
	}
	return a[:6] + "…" + a[len(a)-4:]
}
