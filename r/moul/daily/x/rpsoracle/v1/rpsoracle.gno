// Package rpsoracle is a rock-paper-scissors opponent that doesn't roll
// dice: it studies each player's move history and always throws the
// counter to whichever move that player has favored most. Play a fixed
// pattern and the oracle punishes it; play close to a uniform 1/3-1/3-1/3
// mix and it can't out-guess you better than chance.
package rpsoracle

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// Move is one of rock, paper, or scissors, ordered so that
// (winner - loser + 3) % 3 == 1 for every winning pair.
type Move int

const (
	Rock Move = iota
	Paper
	Scissors
)

func moveName(m Move) string {
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

func parseMove(s string) (Move, bool) {
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

// judge returns 0 for a tie, 1 if p beats h, 2 if h beats p.
func judge(p, h Move) int {
	return (int(p) - int(h) + 3) % 3
}

// beats returns the move that defeats m.
func beats(m Move) Move {
	return Move((int(m) + 1) % 3)
}

// playerState is the persisted record for one address.
type playerState struct {
	Counts     [3]int // history tally per move, what the oracle predicts from
	Rounds     int
	Wins       int // player beat the oracle
	Losses     int // oracle beat the player
	Draws      int
	BestStreak int
	streak     int // current player win streak against the oracle
}

var (
	players avl.Tree // address string -> *playerState

	nonce         int
	totalRounds   int
	oracleCorrect int // rounds the oracle won by successfully countering

	topOutwitter     address
	topOutwitterWins int
)

func getOrCreate(addr address) *playerState {
	key := addr.String()
	if v, ok := players.Get(key); ok {
		return v.(*playerState)
	}
	ps := &playerState{}
	players.Set(key, ps)
	return ps
}

// predict guesses the player's next move as the most-played move in their
// history so far. Ties (including a fresh player's all-zero history) fall
// back to a chain-height-derived seed so the oracle doesn't always break
// ties the same way.
func predict(ps *playerState, seed int64) Move {
	best := Rock
	bestCount := ps.Counts[Rock]
	tied := []Move{Rock}
	for _, m := range []Move{Paper, Scissors} {
		switch {
		case ps.Counts[m] > bestCount:
			bestCount = ps.Counts[m]
			best = m
			tied = []Move{m}
		case ps.Counts[m] == bestCount:
			tied = append(tied, m)
		}
	}
	if len(tied) > 1 {
		if seed < 0 {
			seed = -seed
		}
		best = tied[int(seed)%len(tied)]
	}
	return best
}

// Play pits the caller against the oracle: it predicts your next move from
// your own move history and throws the counter. Accepts
// "rock"/"paper"/"scissors" or the single-letter shorthand "r"/"p"/"s".
func Play(cur realm, moveStr string) string {
	if !cur.IsCurrent() {
		panic("invalid realm")
	}
	caller := cur.Previous().Address()

	playerMove, ok := parseMove(moveStr)
	if !ok {
		panic("invalid move: use rock, paper, or scissors (r/p/s)")
	}

	ps := getOrCreate(caller)

	nonce++
	seed := runtime.ChainHeight() + int64(nonce)
	predicted := predict(ps, seed)
	oracleMove := beats(predicted)

	result := judge(playerMove, oracleMove)

	ps.Counts[playerMove]++
	ps.Rounds++
	totalRounds++

	var msg string
	switch result {
	case 1:
		ps.Wins++
		ps.streak++
		if ps.streak > ps.BestStreak {
			ps.BestStreak = ps.streak
		}
		if ps.Wins > topOutwitterWins {
			topOutwitterWins = ps.Wins
			topOutwitter = caller
		}
		msg = "you outwitted the oracle!"
	case 2:
		ps.Losses++
		ps.streak = 0
		oracleCorrect++
		msg = "the oracle read you like a book."
	default:
		ps.Draws++
		ps.streak = 0
		msg = "a draw — you and the oracle picked the same move."
	}

	chain.Emit("RoundPlayed",
		"player", caller.String(),
		"playerMove", moveName(playerMove),
		"oraclePredicted", moveName(predicted),
		"oracleMove", moveName(oracleMove),
		"result", strconv.Itoa(result),
	)

	return "you played " + moveName(playerMove) + ", the oracle predicted " +
		moveName(predicted) + " and threw " + moveName(oracleMove) + " -> " + msg
}

func renderHome() string {
	var b strings.Builder
	b.WriteString("# Rock-Paper-Scissors Oracle\n\n")
	b.WriteString("An adaptive opponent: it doesn't roll dice, it studies you. ")
	b.WriteString("Every throw is logged, and the oracle always counters whichever ")
	b.WriteString("move you've played most often. Play a uniform mixed strategy and ")
	b.WriteString("it can't out-guess you; fall into a habit and it will.\n\n")

	b.WriteString("- Total rounds played: " + strconv.Itoa(totalRounds) + "\n")
	if totalRounds > 0 {
		pct := oracleCorrect * 100 / totalRounds
		b.WriteString("- Oracle win rate: " + strconv.Itoa(pct) + "%\n")
	}
	if topOutwitter.IsValid() {
		b.WriteString("- Top outwitter: `" + topOutwitter.String() + "` (" +
			strconv.Itoa(topOutwitterWins) + " wins against the oracle)\n")
	} else {
		b.WriteString("- No one has beaten the oracle yet.\n")
	}

	b.WriteString("\n## How to play\n\n")
	b.WriteString("Call `Play(\"rock\"|\"paper\"|\"scissors\")` (or `r`/`p`/`s`). ")
	b.WriteString("View your own record at this realm's path plus your address, ")
	b.WriteString("e.g. `.../rpsoracle:g1youraddress...`\n")
	return b.String()
}

// escapeInline neutralizes markdown-active characters in untrusted text
// before it's embedded inline in Render output.
func escapeInline(s string) string {
	r := strings.NewReplacer(
		"\\", "\\\\",
		"`", "\\`",
		"*", "\\*",
		"_", "\\_",
		"[", "\\[",
		"]", "\\]",
		"|", "\\|",
	)
	return r.Replace(s)
}

func renderPlayer(rawAddr string) string {
	addr := strings.TrimSpace(rawAddr)
	safe := escapeInline(addr)

	v, ok := players.Get(addr)
	if !ok {
		return "# Player " + safe + "\n\nNo recorded rounds yet.\n"
	}
	ps := v.(*playerState)

	var b strings.Builder
	b.WriteString("# Player " + safe + "\n\n")
	b.WriteString("- Rounds played: " + strconv.Itoa(ps.Rounds) + "\n")
	b.WriteString("- Beat the oracle: " + strconv.Itoa(ps.Wins) + "\n")
	b.WriteString("- Lost to the oracle: " + strconv.Itoa(ps.Losses) + "\n")
	b.WriteString("- Draws: " + strconv.Itoa(ps.Draws) + "\n")
	b.WriteString("- Best win streak vs oracle: " + strconv.Itoa(ps.BestStreak) + "\n")
	b.WriteString("- Move history — rock: " + strconv.Itoa(ps.Counts[Rock]) +
		", paper: " + strconv.Itoa(ps.Counts[Paper]) +
		", scissors: " + strconv.Itoa(ps.Counts[Scissors]) + "\n")

	if ps.Rounds > 0 {
		maxCount := ps.Counts[Rock]
		for _, c := range ps.Counts[1:] {
			if c > maxCount {
				maxCount = c
			}
		}
		predictability := maxCount * 100 / ps.Rounds
		b.WriteString("- Predictability score: " + strconv.Itoa(predictability) +
			"% (lower is harder for the oracle to read)\n")
	}
	return b.String()
}

// Render shows the oracle's dashboard at "", or one player's record when
// path is their bech32 address.
func Render(path string) string {
	path = strings.TrimPrefix(strings.TrimSpace(path), "/")
	if path == "" {
		return renderHome()
	}
	return renderPlayer(path)
}
