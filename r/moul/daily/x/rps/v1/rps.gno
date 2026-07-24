package rps

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// Moves.
const (
	rock     = 0
	paper    = 1
	scissors = 2
)

var moveNames = [3]string{"rock", "paper", "scissors"}

// Outcomes.
const (
	outLose = 0 // player loses
	outDraw = 1
	outWin  = 2 // player wins
)

// tally holds a single player's cumulative record.
type tally struct {
	wins   int
	losses int
	draws  int
	plays  int // total rounds this player has played (drives entropy)
}

// round is one recorded game (for the recent-rounds table).
type round struct {
	player   address
	height   int64
	player_m int // player move
	house_m  int // house move
	outcome  int
}

// State.
var (
	players = avl.NewTree() // address string -> *tally
	rounds  []round         // append-only history; Render shows the tail

	// Global tally (caller-agnostic).
	totalWins   int // player wins
	totalLosses int // player losses
	totalDraws  int
	totalRounds int
)

const maxRecent = 8

// parseChoice maps a choice string to a move index; ok=false if invalid.
func parseChoice(choice string) (int, bool) {
	switch strings.ToLower(strings.TrimSpace(choice)) {
	case "rock", "r":
		return rock, true
	case "paper", "p":
		return paper, true
	case "scissors", "s":
		return scissors, true
	}
	return 0, false
}

// houseMove derives the house move deterministically from the chain height
// and the caller's play count (so repeated calls in the same block differ).
func houseMove(height int64, playCount int) int {
	x := height + int64(playCount)*7
	m := x % 3
	if m < 0 {
		m += 3
	}
	return int(m)
}

// decide returns the outcome from the player's perspective.
func decide(playerMove, houseM int) int {
	if playerMove == houseM {
		return outDraw
	}
	// player beats (player+1)%3 ... rock(0) beats scissors(2), etc.
	if (playerMove+2)%3 == houseM {
		return outWin
	}
	return outLose
}

func getTally(key string) *tally {
	if v, ok := players.Get(key); ok {
		return v.(*tally)
	}
	return nil
}

// Play plays one round against the chain. choice is "rock"|"paper"|"scissors"
// (single-letter shortcuts accepted). It panics on an invalid choice.
func Play(cur realm, choice string) {
	mv, ok := parseChoice(choice)
	if !ok {
		panic("invalid choice: use rock, paper, or scissors")
	}

	caller := unsafe.PreviousRealm().Address()
	key := caller.String()

	t := getTally(key)
	if t == nil {
		t = &tally{}
		players.Set(key, t)
	}

	height := runtime.ChainHeight()
	hm := houseMove(height, t.plays)
	outcome := decide(mv, hm)

	t.plays++
	switch outcome {
	case outWin:
		t.wins++
		totalWins++
	case outLose:
		t.losses++
		totalLosses++
	default:
		t.draws++
		totalDraws++
	}
	totalRounds++

	rounds = append(rounds, round{
		player:   caller,
		height:   height,
		player_m: mv,
		house_m:  hm,
		outcome:  outcome,
	})

	chain.Emit(
		"RoundPlayed",
		"player", key,
		"choice", moveNames[mv],
		"house", moveNames[hm],
		"outcome", outcomeName(outcome),
	)
}

func outcomeName(o int) string {
	switch o {
	case outWin:
		return "win"
	case outLose:
		return "lose"
	default:
		return "draw"
	}
}

func winRate(wins, plays int) string {
	if plays == 0 {
		return "0%"
	}
	return strconv.Itoa(wins*100/plays) + "%"
}

// Render returns a Markdown dashboard: global tally, per-player table, and the
// last few rounds. It is caller-agnostic (no cur).
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Rock-Paper-Scissors — play vs the chain\n\n")
	b.WriteString("Call `Play(cur, \"rock\"|\"paper\"|\"scissors\")`. ")
	b.WriteString("The house move is derived deterministically from the current block height ")
	b.WriteString("and your personal play count.\n\n")

	// Global tally.
	b.WriteString("## Global tally\n\n")
	b.WriteString("| Rounds | Player wins | Player losses | Draws | Player win rate |\n")
	b.WriteString("|---|---|---|---|---|\n")
	b.WriteString("| " + strconv.Itoa(totalRounds))
	b.WriteString(" | " + strconv.Itoa(totalWins))
	b.WriteString(" | " + strconv.Itoa(totalLosses))
	b.WriteString(" | " + strconv.Itoa(totalDraws))
	b.WriteString(" | " + winRate(totalWins, totalRounds) + " |\n\n")

	// Per-player table (deterministic order via avl iteration).
	b.WriteString("## Players\n\n")
	if players.Size() == 0 {
		b.WriteString("_No games played yet. Be the first!_\n\n")
	} else {
		b.WriteString("| Player | W | L | D | Rounds | Win rate |\n")
		b.WriteString("|---|---|---|---|---|---|\n")
		players.Iterate("", "", func(key string, v interface{}) bool {
			t := v.(*tally)
			b.WriteString("| " + shortAddr(key))
			b.WriteString(" | " + strconv.Itoa(t.wins))
			b.WriteString(" | " + strconv.Itoa(t.losses))
			b.WriteString(" | " + strconv.Itoa(t.draws))
			b.WriteString(" | " + strconv.Itoa(t.plays))
			b.WriteString(" | " + winRate(t.wins, t.plays) + " |\n")
			return false
		})
		b.WriteString("\n")
	}

	// Recent rounds (tail).
	b.WriteString("## Recent rounds\n\n")
	if len(rounds) == 0 {
		b.WriteString("_None yet._\n")
	} else {
		b.WriteString("| Height | Player | Choice | House | Result |\n")
		b.WriteString("|---|---|---|---|---|\n")
		start := len(rounds) - maxRecent
		if start < 0 {
			start = 0
		}
		// Show newest first.
		for i := len(rounds) - 1; i >= start; i-- {
			r := rounds[i]
			b.WriteString("| " + strconv.FormatInt(r.height, 10))
			b.WriteString(" | " + shortAddr(r.player.String()))
			b.WriteString(" | " + moveNames[r.player_m])
			b.WriteString(" | " + moveNames[r.house_m])
			b.WriteString(" | " + outcomeName(r.outcome) + " |\n")
		}
	}

	return b.String()
}

// shortAddr abbreviates an address string for display.
func shortAddr(a string) string {
	if len(a) <= 12 {
		return a
	}
	return a[:8] + "…" + a[len(a)-4:]
}
