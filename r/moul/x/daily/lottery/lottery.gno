// Package lottery is an idiomatic gno.land port of the classic Solidity
// Lottery contract. Players Enter the current round (one entry per address per
// round). Once a round has at least two entrants, anyone may DrawWinner: a
// winner is picked deterministically from the block height (ChainHeight() %
// len(entrants), over the deterministically-sorted entrant set), recorded in
// the winners history, and a fresh round is opened.
//
// There is no real randomness on-chain, so "random" selection is derived from
// the block height — the same source Solidity ports use via block.number.
package lottery

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// round is the current (open) round number, 1-based.
var round int = 1

// entrants holds the current round's players: key = address string, value =
// the address. Iteration is deterministic (sorted by key), which makes winner
// selection reproducible.
var entrants avl.Tree

// winners records past rounds: key = zero-padded round number (for ordered
// iteration), value = *winnerRecord.
var winners avl.Tree

type winnerRecord struct {
	Round       int
	Winner      address
	NumEntrants int
	Height      int64
}

// winnerKey zero-pads the round number so avl iteration yields chronological
// order for up to 10^9 rounds.
func winnerKey(r int) string {
	s := strconv.Itoa(r)
	for len(s) < 9 {
		s = "0" + s
	}
	return s
}

// pickIndex derives the winning entrant index from the block height. Panics if
// there are no entrants. Pure helper (deterministic, no state) — safe to test.
func pickIndex(height int64, n int) int {
	if n <= 0 {
		panic("lottery: no entrants to draw from")
	}
	i := height % int64(n)
	if i < 0 {
		i += int64(n)
	}
	return int(i)
}

// Enter adds the caller to the current round's entrants. Each address may only
// enter a given round once; a duplicate entry panics.
func Enter(cur realm) {
	player := unsafe.PreviousRealm().Address()
	key := player.String()
	if entrants.Has(key) {
		panic("lottery: already entered this round")
	}
	entrants.Set(key, player)

	chain.Emit("Enter",
		"round", strconv.Itoa(round),
		"player", key,
		"entrants", strconv.Itoa(entrants.Size()),
	)
}

// DrawWinner closes the current round, provided it has at least two entrants,
// picks the winner deterministically from the block height, records it, and
// opens a new empty round.
func DrawWinner(cur realm) address {
	n := entrants.Size()
	if n < 2 {
		panic("lottery: need at least 2 entrants to draw")
	}

	height := runtime.ChainHeight()
	idx := pickIndex(height, n)

	var winner address
	i := 0
	entrants.Iterate("", "", func(_ string, value interface{}) bool {
		if i == idx {
			winner = value.(address)
			return true // stop
		}
		i++
		return false
	})

	rec := &winnerRecord{
		Round:       round,
		Winner:      winner,
		NumEntrants: n,
		Height:      height,
	}
	winners.Set(winnerKey(round), rec)

	chain.Emit("DrawWinner",
		"round", strconv.Itoa(round),
		"winner", winner.String(),
		"entrants", strconv.Itoa(n),
		"height", strconv.FormatInt(height, 10),
	)

	// Open a fresh round.
	round++
	entrants = avl.Tree{}

	return winner
}

// CurrentRound returns the currently open round number.
func CurrentRound() int {
	return round
}

// NumEntrants returns how many players have entered the current round.
func NumEntrants() int {
	return entrants.Size()
}

// HasEntered reports whether addr is in the current round.
func HasEntered(addr address) bool {
	return entrants.Has(addr.String())
}

// Render shows the current round, its entrants, and the winners history.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Lottery\n\n")
	b.WriteString("Enter the open round, then anyone can draw once it has ")
	b.WriteString("at least two players. The winner is picked from the block ")
	b.WriteString("height and a new round opens automatically.\n\n")

	b.WriteString("## Round " + strconv.Itoa(round) + " (open)\n\n")
	if entrants.Size() == 0 {
		b.WriteString("_No entrants yet. Call `Enter` to join._\n\n")
	} else {
		b.WriteString(strconv.Itoa(entrants.Size()) + " entrant(s):\n\n")
		entrants.Iterate("", "", func(key string, _ interface{}) bool {
			b.WriteString("- `" + key + "`\n")
			return false
		})
		b.WriteString("\n")
		if entrants.Size() < 2 {
			b.WriteString("_Need at least 2 entrants before a draw._\n\n")
		} else {
			b.WriteString("_Ready to draw: call `DrawWinner`._\n\n")
		}
	}

	b.WriteString("## Past winners\n\n")
	if winners.Size() == 0 {
		b.WriteString("_No rounds drawn yet._\n")
	} else {
		b.WriteString("| Round | Winner | Entrants | Block Height |\n")
		b.WriteString("|---|---|---|---|\n")
		winners.Iterate("", "", func(_ string, value interface{}) bool {
			r := value.(*winnerRecord)
			b.WriteString("| " + strconv.Itoa(r.Round) +
				" | `" + r.Winner.String() + "`" +
				" | " + strconv.Itoa(r.NumEntrants) +
				" | " + strconv.FormatInt(r.Height, 10) + " |\n")
			return false
		})
	}

	return b.String()
}
