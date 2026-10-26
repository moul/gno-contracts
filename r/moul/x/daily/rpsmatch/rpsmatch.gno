// Package rpsmatch is a best-of-three rock-paper-scissors arena against the
// house. Unlike a single stateless throw, a match persists across calls:
// the first player to win two rounds takes the match, and every player's
// match record accumulates on-chain.
package rpsmatch

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/rps/v0"
	"gno.land/p/nt/avl/v0"
)

// winsNeeded is the number of round wins required to take a match.
const winsNeeded = 2

// match tracks an in-progress best-of-three series for one player.
type match struct {
	PlayerWins int
	HouseWins  int
	Rounds     int
}

// playerState is the persisted record for one address.
type playerState struct {
	Active        *match
	MatchWins     int
	MatchLosses   int
	MatchesPlayed int
	RoundsPlayed  int
}

var (
	players avl.Tree // address string -> *playerState

	nonce       int
	totalRounds int

	champion     address
	championWins int
)

// pickHouseMove derives a deterministic pseudo-random move from the current
// chain height, a monotonic per-realm nonce, and the caller's address, so
// repeated throws in the same block still diverge.
func pickHouseMove(caller address, n int) rps.Move {
	seed := runtime.ChainHeight() + int64(n)
	s := caller.String()
	for i := 0; i < len(s); i++ {
		seed += int64(s[i])
	}
	if seed < 0 {
		seed = -seed
	}
	return rps.Move(seed % 3)
}

func getOrCreate(addr address) *playerState {
	key := addr.String()
	if v := players.Get(key); v != nil {
		return v.(*playerState)
	}
	ps := &playerState{}
	players.Set(key, ps)
	return ps
}

// Throw plays one round of the caller's current match, starting a fresh
// match if none is in progress. Accepts "rock"/"paper"/"scissors" or the
// single-letter shorthand "r"/"p"/"s".
func Throw(cur realm, moveStr string) string {
	if !cur.IsCurrent() {
		panic("invalid realm")
	}
	caller := cur.Previous().Address()

	playerMove, ok := rps.Parse(moveStr)
	if !ok {
		panic("invalid move: use rock, paper, or scissors (r/p/s)")
	}

	ps := getOrCreate(caller)
	if ps.Active == nil {
		ps.Active = &match{}
	}
	m := ps.Active

	nonce++
	houseMove := pickHouseMove(caller, nonce)
	round := rps.Beats(playerMove, houseMove)

	m.Rounds++
	totalRounds++
	ps.RoundsPlayed++

	var roundMsg string
	switch round {
	case 1:
		m.PlayerWins++
		roundMsg = "you win the round"
	case 2:
		m.HouseWins++
		roundMsg = "house wins the round"
	default:
		roundMsg = "round tied"
	}

	out := "round " + strconv.Itoa(m.Rounds) + ": you played " + playerMove.String() +
		", house played " + houseMove.String() + " -> " + roundMsg +
		" (score " + strconv.Itoa(m.PlayerWins) + "-" + strconv.Itoa(m.HouseWins) + ")"

	if m.PlayerWins >= winsNeeded || m.HouseWins >= winsNeeded {
		ps.Active = nil
		ps.MatchesPlayed++
		playerTookMatch := m.PlayerWins > m.HouseWins
		if playerTookMatch {
			ps.MatchWins++
			if ps.MatchWins > championWins {
				championWins = ps.MatchWins
				champion = caller
			}
			out += ". MATCH WON!"
		} else {
			ps.MatchLosses++
			out += ". match lost."
		}
		chain.Emit("MatchFinished",
			"player", caller.String(),
			"playerWins", strconv.Itoa(m.PlayerWins),
			"houseWins", strconv.Itoa(m.HouseWins),
		)
	}

	chain.Emit("RoundPlayed",
		"player", caller.String(),
		"playerMove", playerMove.String(),
		"houseMove", houseMove.String(),
		"result", strconv.Itoa(round),
	)

	return out
}

func renderHome() string {
	var b strings.Builder
	b.WriteString("# Rock-Paper-Scissors Arena\n\n")
	b.WriteString("Best-of-three matches against the house. First to " +
		strconv.Itoa(winsNeeded) + " round wins takes the match.\n\n")
	b.WriteString("- Total rounds played: " + strconv.Itoa(totalRounds) + "\n")

	if champion.IsValid() {
		b.WriteString("- Reigning champion: `" + champion.String() +
			"` (" + strconv.Itoa(championWins) + " match wins)\n")
	} else {
		b.WriteString("- No champion yet — be the first to win a match.\n")
	}

	b.WriteString("\n## How to play\n\n")
	b.WriteString("Call `Throw(\"rock\"|\"paper\"|\"scissors\")` (or `r`/`p`/`s`). " +
		"Your throw starts a new match if you don't have one in progress, " +
		"and each call plays one round of it.\n\n")
	b.WriteString("View your own record at this realm's path plus your address, " +
		"e.g. `.../rpsmatch:g1youraddress...`\n")
	return b.String()
}

func renderPlayer(rawAddr string) string {
	addr := strings.TrimSpace(rawAddr)
	safe := ui.Inline(addr)

	v := players.Get(addr)
	if v == nil {
		return "# Player " + safe + "\n\nNo recorded throws yet.\n"
	}
	ps := v.(*playerState)

	var b strings.Builder
	b.WriteString("# Player " + safe + "\n\n")
	b.WriteString("- Matches won: " + strconv.Itoa(ps.MatchWins) + "\n")
	b.WriteString("- Matches lost: " + strconv.Itoa(ps.MatchLosses) + "\n")
	b.WriteString("- Matches played: " + strconv.Itoa(ps.MatchesPlayed) + "\n")
	b.WriteString("- Rounds played: " + strconv.Itoa(ps.RoundsPlayed) + "\n")

	if ps.Active != nil {
		b.WriteString("\n**Match in progress:** " + strconv.Itoa(ps.Active.PlayerWins) +
			"-" + strconv.Itoa(ps.Active.HouseWins) + " through " +
			strconv.Itoa(ps.Active.Rounds) + " round(s).\n")
	}
	return b.String()
}

// Render shows the arena dashboard at "", or one player's record when path
// is their bech32 address.
func Render(path string) string {
	path = strings.TrimPrefix(strings.TrimSpace(path), "/")
	if path == "" {
		return renderHome()
	}
	return renderPlayer(path)
}
