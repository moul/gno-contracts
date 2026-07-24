// Package coinflipduel is a one-on-one coin-flip duel: challenge another
// address, they call heads or tails, and the block settles it. No stakes,
// just bragging rights tracked in an on-chain win/loss record.
package coinflipduel

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// duelStatus tracks the lifecycle of a duel.
type duelStatus int

const (
	statusPending duelStatus = iota
	statusResolved
	statusCancelled
)

func (s duelStatus) String() string {
	switch s {
	case statusPending:
		return "pending"
	case statusResolved:
		return "resolved"
	case statusCancelled:
		return "cancelled"
	default:
		return "?"
	}
}

// duel is one challenge from Challenger to Opponent over a single coin flip.
// The Challenger calls a side up front; the Opponent's only move is to
// accept, which triggers the flip.
type duel struct {
	ID         string
	Challenger address
	Opponent   address
	Call       string // "heads" or "tails" — the challenger's pick
	Status     duelStatus
	Result     string // "heads" or "tails" once resolved
	Winner     address
	CreatedAt  int64
	ResolvedAt int64
}

// playerState is the persisted win/loss record for one address.
type playerState struct {
	Wins   int
	Losses int
	Duels  int
}

var (
	duels   avl.Tree // duel ID -> *duel
	players avl.Tree // address string -> *playerState

	nextID    int
	flipNonce int
	totalDone int

	champion     address
	championWins int
)

func parseCall(s string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "heads", "h":
		return "heads", true
	case "tails", "t":
		return "tails", true
	default:
		return "", false
	}
}

// flipCoin derives a deterministic pseudo-random side from the current chain
// height, a monotonic per-realm nonce, and both duelists' addresses, so two
// duels resolved in the same block still diverge.
func flipCoin(d *duel) string {
	flipNonce++
	seed := runtime.ChainHeight() + int64(flipNonce)
	s := d.Challenger.String() + d.Opponent.String() + d.ID
	for i := 0; i < len(s); i++ {
		seed += int64(s[i])
	}
	if seed < 0 {
		seed = -seed
	}
	if seed%2 == 0 {
		return "heads"
	}
	return "tails"
}

func getOrCreate(addr address) *playerState {
	key := addr.String()
	if v, ok := players.Get(key); ok {
		return v.(*playerState)
	}
	ps := &playerState{}
	players.Set(key, ps)
	return ps
}

func recordResult(winner, loser address) {
	w := getOrCreate(winner)
	w.Wins++
	w.Duels++
	l := getOrCreate(loser)
	l.Losses++
	l.Duels++

	if w.Wins > championWins {
		championWins = w.Wins
		champion = winner
	}
}

// Challenge opens a new duel against opponentAddr, locking in the
// challenger's call of "heads"/"tails" ("h"/"t" also accepted). The
// opponent settles it by calling Accept with the returned duel ID.
func Challenge(cur realm, opponentAddr string, call string) string {
	challenger := cur.Previous().Address()

	opponent := address(strings.TrimSpace(opponentAddr))
	if !opponent.IsValid() {
		panic("invalid opponent address")
	}
	if opponent == challenger {
		panic("cannot duel yourself")
	}

	pick, ok := parseCall(call)
	if !ok {
		panic("call must be heads or tails (h/t)")
	}

	nextID++
	id := strconv.Itoa(nextID)
	d := &duel{
		ID:         id,
		Challenger: challenger,
		Opponent:   opponent,
		Call:       pick,
		Status:     statusPending,
		CreatedAt:  runtime.ChainHeight(),
	}
	duels.Set(id, d)

	chain.Emit("DuelChallenged",
		"id", id,
		"challenger", challenger.String(),
		"opponent", opponent.String(),
		"call", pick,
	)

	return "duel #" + id + " created: you called " + pick +
		", waiting for " + opponent.String() + " to accept"
}

// Accept settles a pending duel. Only the challenged opponent may call it;
// the flip happens immediately and the result is final.
func Accept(cur realm, id string) string {
	caller := cur.Previous().Address()

	v, ok := duels.Get(id)
	if !ok {
		panic("no such duel")
	}
	d := v.(*duel)

	if d.Status != statusPending {
		panic("duel already " + d.Status.String())
	}
	if caller != d.Opponent {
		panic("only the challenged opponent can accept this duel")
	}

	result := flipCoin(d)
	d.Result = result
	d.Status = statusResolved
	d.ResolvedAt = runtime.ChainHeight()

	if result == d.Call {
		d.Winner = d.Challenger
		recordResult(d.Challenger, d.Opponent)
	} else {
		d.Winner = d.Opponent
		recordResult(d.Opponent, d.Challenger)
	}

	totalDone++

	chain.Emit("DuelResolved",
		"id", id,
		"result", result,
		"winner", d.Winner.String(),
	)

	return "the coin landed on " + result + " -- " + d.Winner.String() + " wins duel #" + id
}

// Cancel withdraws a still-pending duel. Only the challenger may cancel,
// and only before the opponent accepts.
func Cancel(cur realm, id string) string {
	caller := cur.Previous().Address()

	v, ok := duels.Get(id)
	if !ok {
		panic("no such duel")
	}
	d := v.(*duel)

	if d.Status != statusPending {
		panic("duel already " + d.Status.String())
	}
	if caller != d.Challenger {
		panic("only the challenger can cancel this duel")
	}

	d.Status = statusCancelled
	return "duel #" + id + " cancelled"
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

func renderHome() string {
	var b strings.Builder
	b.WriteString("# Coin-Flip Duel\n\n")
	b.WriteString("Challenge another address to a coin flip. You call heads or tails " +
		"up front; they accept and the block decides. No stakes -- just a record.\n\n")
	b.WriteString("- Total duels resolved: " + strconv.Itoa(totalDone) + "\n")

	if champion.IsValid() {
		b.WriteString("- Reigning champion: `" + champion.String() +
			"` (" + strconv.Itoa(championWins) + " wins)\n")
	} else {
		b.WriteString("- No champion yet -- be the first to win a duel.\n")
	}

	b.WriteString("\n## How to play\n\n")
	b.WriteString("1. `Challenge(opponentAddr, \"heads\"|\"tails\")` -- opens a duel, returns its ID.\n")
	b.WriteString("2. The opponent calls `Accept(id)` -- flips the coin and settles it on the spot.\n")
	b.WriteString("3. The challenger may `Cancel(id)` while it's still pending.\n\n")
	b.WriteString("View a duel at this realm's path plus its ID (e.g. `.../coinflipduel:3`), " +
		"or a player's record plus their address (e.g. `.../coinflipduel:g1youraddress...`).\n\n")

	b.WriteString("## Pending duels\n\n")
	pending := 0
	duels.Iterate("", "", func(key string, value interface{}) bool {
		d := value.(*duel)
		if d.Status == statusPending {
			pending++
			b.WriteString("- #" + d.ID + ": `" + d.Challenger.String() + "` called " +
				d.Call + ", waiting on `" + d.Opponent.String() + "`\n")
		}
		return false
	})
	if pending == 0 {
		b.WriteString("_none right now_\n")
	}

	return b.String()
}

func renderDuel(id string) string {
	v, ok := duels.Get(id)
	if !ok {
		return "# Duel #" + escapeInline(id) + "\n\nNo such duel.\n"
	}
	d := v.(*duel)

	var b strings.Builder
	b.WriteString("# Duel #" + d.ID + "\n\n")
	b.WriteString("- Challenger: `" + d.Challenger.String() + "` called **" + d.Call + "**\n")
	b.WriteString("- Opponent: `" + d.Opponent.String() + "`\n")
	b.WriteString("- Status: " + d.Status.String() + "\n")

	if d.Status == statusResolved {
		b.WriteString("- Coin landed on: **" + d.Result + "**\n")
		b.WriteString("- Winner: `" + d.Winner.String() + "`\n")
	}
	return b.String()
}

func renderPlayer(rawAddr string) string {
	addr := strings.TrimSpace(rawAddr)
	safe := escapeInline(addr)

	v, ok := players.Get(addr)
	if !ok {
		return "# Player " + safe + "\n\nNo recorded duels yet.\n"
	}
	ps := v.(*playerState)

	var b strings.Builder
	b.WriteString("# Player " + safe + "\n\n")
	b.WriteString("- Wins: " + strconv.Itoa(ps.Wins) + "\n")
	b.WriteString("- Losses: " + strconv.Itoa(ps.Losses) + "\n")
	b.WriteString("- Duels played: " + strconv.Itoa(ps.Duels) + "\n")
	return b.String()
}

// Render shows the duel arena at "", a specific duel when path is a numeric
// ID, or one player's record when path is their bech32 address.
func Render(path string) string {
	path = strings.TrimPrefix(strings.TrimSpace(path), "/")
	if path == "" {
		return renderHome()
	}
	if _, err := strconv.Atoi(path); err == nil {
		return renderDuel(path)
	}
	return renderPlayer(path)
}
