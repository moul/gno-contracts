// Package rps is the rock-paper-scissors move: parsing it, naming it, and
// deciding a throw. It holds no state, so every realm that plays the game
// agrees on what "r" means and who wins.
//
// Imported by [r/moul/x/daily/rps](/r/moul/x/daily/rps/v1),
// [r/moul/x/daily/rpsmatch](/r/moul/x/daily/rpsmatch/v1),
// [r/moul/x/daily/rpsoracle](/r/moul/x/daily/rpsoracle/v1) and
// [r/moul/x/daily/rpsduel](/r/moul/x/daily/rpsduel/v1).
package rps

import "strings"

// Move is one of rock, paper, or scissors, ordered so that
// (winner - loser + 3) % 3 == 1 for every winning pair.
type Move int

const (
	Rock Move = iota
	Paper
	Scissors
)

// String returns "rock", "paper" or "scissors", and "?" for anything else.
func (m Move) String() string {
	switch m {
	case Rock:
		return "rock"
	case Paper:
		return "paper"
	case Scissors:
		return "scissors"
	default:
		return "?"
	}
}

// Parse reads a move, case-insensitively and ignoring surrounding spaces.
// The full name and its first letter are both accepted.
func Parse(s string) (Move, bool) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "rock", "r":
		return Rock, true
	case "paper", "p":
		return Paper, true
	case "scissors", "s":
		return Scissors, true
	default:
		return 0, false
	}
}

// Beats decides a throw: 0 for a tie, 1 if a beats b, 2 if b beats a.
// The three values are (a - b) mod 3, which is why Move is ordered as it is.
func Beats(a, b Move) int {
	return (int(a) - int(b) + 3) % 3
}
