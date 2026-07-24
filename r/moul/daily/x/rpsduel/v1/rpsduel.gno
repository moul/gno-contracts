// Package rpsduel is an asynchronous, two-player rock-paper-scissors duel
// with a commit-reveal handshake. The challenger locks in a move as a
// sha256 commitment up front so the opponent can't peek at it; the
// opponent then replies in the clear (seeing only a hash gives them no
// edge); the challenger reveals last to settle the round. A challenger who
// tries to dodge a losing reveal can be forfeited by the opponent once the
// reveal window expires.
package rpsduel

import (
	"crypto/sha256"
	"encoding/hex"
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

// revealWindow is how many blocks the challenger gets to reveal after the
// opponent accepts before the opponent can claim a forfeit win.
const revealWindow int64 = 50

type duelStatus int

const (
	statusPending duelStatus = iota
	statusAwaitingReveal
	statusResolved
	statusForfeited
	statusCancelled
)

func (s duelStatus) String() string {
	switch s {
	case statusPending:
		return "pending"
	case statusAwaitingReveal:
		return "awaiting reveal"
	case statusResolved:
		return "resolved"
	case statusForfeited:
		return "forfeited"
	case statusCancelled:
		return "cancelled"
	default:
		return "?"
	}
}

// duel is one asynchronous round between Challenger and Opponent. The
// challenger's move is hidden behind Commit until Reveal; the opponent's
// move is stored in the clear once they Accept.
type duel struct {
	ID             string
	Challenger     address
	Opponent       address
	Commit         string // hex sha256 of "<move>:<salt>"
	OpponentMove   Move
	Status         duelStatus
	Result         string // "challenger" | "opponent" | "draw" once settled
	Winner         address
	OpenedAt       int64
	AcceptedAt     int64
	RevealDeadline int64
}

// playerState is the persisted record for one address.
type playerState struct {
	Wins     int
	Losses   int
	Draws    int
	Forfeits int // times this player, as challenger, failed to reveal in time
	Duels    int
}

var (
	duels   avl.Tree // duel ID -> *duel
	players avl.Tree // address string -> *playerState

	nextID        int
	totalResolved int

	champion     address
	championWins int
)

// ComputeCommit hashes a move and salt exactly the way Reveal checks it, so
// a caller can compute their commitment (e.g. via a read-only query) before
// calling Open, then remember the salt to pass to Reveal later.
func ComputeCommit(moveStr, salt string) string {
	m, ok := parseMove(moveStr)
	if !ok {
		panic("invalid move: use rock, paper, or scissors (r/p/s)")
	}
	sum := sha256.Sum256([]byte(moveName(m) + ":" + salt))
	return hex.EncodeToString(sum[:])
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

func bumpChampion(addr address, wins int) {
	if wins > championWins {
		championWins = wins
		champion = addr
	}
}

// settle scores a revealed round and updates both players' records.
func settle(d *duel, challengerMove Move, result int) {
	cs := getOrCreate(d.Challenger)
	os := getOrCreate(d.Opponent)
	cs.Duels++
	os.Duels++

	switch result {
	case 1:
		cs.Wins++
		os.Losses++
		d.Winner = d.Challenger
		d.Result = "challenger"
		bumpChampion(d.Challenger, cs.Wins)
	case 2:
		os.Wins++
		cs.Losses++
		d.Winner = d.Opponent
		d.Result = "opponent"
		bumpChampion(d.Opponent, os.Wins)
	default:
		cs.Draws++
		os.Draws++
		d.Result = "draw"
	}
	d.Status = statusResolved
	totalResolved++
}

// Open challenges opponentAddr to a duel, locking in the challenger's move
// as a commitment (see ComputeCommit) so the opponent can't see it before
// replying.
func Open(cur realm, opponentAddr string, commitHex string) string {
	challenger := cur.Previous().Address()

	opponent := address(strings.TrimSpace(opponentAddr))
	if !opponent.IsValid() {
		panic("invalid opponent address")
	}
	if opponent == challenger {
		panic("cannot duel yourself")
	}

	commit := strings.ToLower(strings.TrimSpace(commitHex))
	if len(commit) != sha256.Size*2 {
		panic("commit must be a 64-character hex sha256 digest; build it with ComputeCommit")
	}
	if _, err := hex.DecodeString(commit); err != nil {
		panic("commit must be valid hex")
	}

	nextID++
	id := strconv.Itoa(nextID)
	d := &duel{
		ID:         id,
		Challenger: challenger,
		Opponent:   opponent,
		Commit:     commit,
		Status:     statusPending,
		OpenedAt:   runtime.ChainHeight(),
	}
	duels.Set(id, d)

	chain.Emit("DuelOpened",
		"id", id,
		"challenger", challenger.String(),
		"opponent", opponent.String(),
	)

	return "duel #" + id + " opened against " + opponent.String() + " -- waiting for them to Accept"
}

// Accept replies to a pending duel with a plain move. Only the challenged
// opponent may call it; going second behind the challenger's hidden
// commitment is what keeps this fair.
func Accept(cur realm, id string, moveStr string) string {
	caller := cur.Previous().Address()

	v := duels.Get(id)
	if v == nil {
		panic("no such duel")
	}
	d := v.(*duel)

	if d.Status != statusPending {
		panic("duel is " + d.Status.String() + ", not pending")
	}
	if caller != d.Opponent {
		panic("only the challenged opponent can accept this duel")
	}

	m, ok := parseMove(moveStr)
	if !ok {
		panic("invalid move: use rock, paper, or scissors (r/p/s)")
	}

	d.OpponentMove = m
	d.Status = statusAwaitingReveal
	d.AcceptedAt = runtime.ChainHeight()
	d.RevealDeadline = d.AcceptedAt + revealWindow

	chain.Emit("DuelAccepted", "id", id, "opponentMove", moveName(m))

	return "you played " + moveName(m) + " in duel #" + id +
		" -- waiting for " + d.Challenger.String() + " to reveal by block " +
		strconv.Itoa(int(d.RevealDeadline))
}

// Reveal settles an accepted duel. Only the original challenger may call
// it, and only with the exact move+salt that produced their commitment.
func Reveal(cur realm, id string, moveStr string, salt string) string {
	caller := cur.Previous().Address()

	v := duels.Get(id)
	if v == nil {
		panic("no such duel")
	}
	d := v.(*duel)

	if d.Status != statusAwaitingReveal {
		panic("duel is " + d.Status.String() + ", not awaiting reveal")
	}
	if caller != d.Challenger {
		panic("only the challenger can reveal")
	}

	m, ok := parseMove(moveStr)
	if !ok {
		panic("invalid move: use rock, paper, or scissors (r/p/s)")
	}
	sum := sha256.Sum256([]byte(moveName(m) + ":" + salt))
	if hex.EncodeToString(sum[:]) != d.Commit {
		panic("revealed move+salt doesn't match your original commitment")
	}

	result := judge(m, d.OpponentMove)
	settle(d, m, result)

	chain.Emit("DuelResolved",
		"id", id,
		"result", d.Result,
		"challengerMove", moveName(m),
		"opponentMove", moveName(d.OpponentMove),
	)

	return "you revealed " + moveName(m) + " vs " + moveName(d.OpponentMove) + " -- " + outcomeMsg(d)
}

func outcomeMsg(d *duel) string {
	switch d.Result {
	case "challenger":
		return "you win duel #" + d.ID + "!"
	case "opponent":
		return "you lose duel #" + d.ID + " -- " + d.Opponent.String() + " wins."
	default:
		return "draw."
	}
}

// ClaimForfeit lets the opponent collect a default win when the challenger
// dodges revealing (e.g. because they saw the opponent's move and knew
// they'd lose) past the reveal window.
func ClaimForfeit(cur realm, id string) string {
	caller := cur.Previous().Address()

	v := duels.Get(id)
	if v == nil {
		panic("no such duel")
	}
	d := v.(*duel)

	if d.Status != statusAwaitingReveal {
		panic("duel is " + d.Status.String() + ", not awaiting reveal")
	}
	if caller != d.Opponent {
		panic("only the waiting opponent can claim a forfeit")
	}
	if runtime.ChainHeight() <= d.RevealDeadline {
		panic("reveal window hasn't expired yet")
	}

	d.Status = statusForfeited
	d.Winner = d.Opponent
	d.Result = "opponent"

	cs := getOrCreate(d.Challenger)
	cs.Duels++
	cs.Losses++
	cs.Forfeits++
	os := getOrCreate(d.Opponent)
	os.Duels++
	os.Wins++
	totalResolved++
	bumpChampion(d.Opponent, os.Wins)

	chain.Emit("DuelForfeited", "id", id, "winner", d.Opponent.String())

	return "duel #" + id + " forfeited -- " + d.Challenger.String() + " never revealed"
}

// Cancel withdraws a still-pending duel. Only the challenger may cancel,
// and only before the opponent accepts.
func Cancel(cur realm, id string) string {
	caller := cur.Previous().Address()

	v := duels.Get(id)
	if v == nil {
		panic("no such duel")
	}
	d := v.(*duel)

	if d.Status != statusPending {
		panic("duel is " + d.Status.String() + ", not pending")
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
	b.WriteString("# Rock-Paper-Scissors Duel\n\n")
	b.WriteString("Challenge another address to rock-paper-scissors, async and " +
		"fair: you commit your move as a hash, they reply in the open, then you " +
		"reveal to settle it. Stall on revealing a losing round and your opponent " +
		"can claim a forfeit win once the window expires.\n\n")

	b.WriteString("- Total duels resolved: " + strconv.Itoa(totalResolved) + "\n")
	if champion.IsValid() {
		b.WriteString("- Reigning champion: `" + champion.String() + "` (" +
			strconv.Itoa(championWins) + " wins)\n")
	} else {
		b.WriteString("- No champion yet -- be the first to win a duel.\n")
	}

	b.WriteString("\n## How to play\n\n")
	b.WriteString("1. Pick a move and a random salt, e.g. `rock` + `xyz123`.\n")
	b.WriteString("2. Compute your commitment: `ComputeCommit(\"rock\", \"xyz123\")` (read-only call).\n")
	b.WriteString("3. `Open(opponentAddr, commit)` -- opens the duel, returns its ID.\n")
	b.WriteString("4. The opponent calls `Accept(id, \"paper\"|\"scissors\"|\"rock\")`.\n")
	b.WriteString("5. You call `Reveal(id, \"rock\", \"xyz123\")` -- must match your commitment exactly.\n")
	b.WriteString("6. If you never reveal, the opponent can call `ClaimForfeit(id)` after " +
		strconv.Itoa(int(revealWindow)) + " blocks.\n\n")
	b.WriteString("View a duel at this realm's path plus its ID (e.g. `.../rpsduel:3`), " +
		"or a player's record plus their address (e.g. `.../rpsduel:g1youraddress...`).\n\n")

	b.WriteString("## Open duels\n\n")
	open := 0
	duels.Iterate("", "", func(key string, value interface{}) bool {
		d := value.(*duel)
		if d.Status == statusPending {
			open++
			b.WriteString("- #" + d.ID + ": `" + d.Challenger.String() +
				"` waiting on `" + d.Opponent.String() + "` to Accept\n")
		} else if d.Status == statusAwaitingReveal {
			open++
			b.WriteString("- #" + d.ID + ": `" + d.Challenger.String() +
				"` must Reveal by block " + strconv.Itoa(int(d.RevealDeadline)) + "\n")
		}
		return false
	})
	if open == 0 {
		b.WriteString("_none right now_\n")
	}

	return b.String()
}

func renderDuel(id string) string {
	v := duels.Get(id)
	if v == nil {
		return "# Duel #" + escapeInline(id) + "\n\nNo such duel.\n"
	}
	d := v.(*duel)

	var b strings.Builder
	b.WriteString("# Duel #" + d.ID + "\n\n")
	b.WriteString("- Challenger: `" + d.Challenger.String() + "`\n")
	b.WriteString("- Opponent: `" + d.Opponent.String() + "`\n")
	b.WriteString("- Status: " + d.Status.String() + "\n")

	if d.Status == statusAwaitingReveal {
		b.WriteString("- Opponent played: **" + moveName(d.OpponentMove) + "**\n")
		b.WriteString("- Reveal deadline: block " + strconv.Itoa(int(d.RevealDeadline)) + "\n")
	}
	if d.Status == statusResolved || d.Status == statusForfeited {
		b.WriteString("- Result: " + d.Result + "\n")
		b.WriteString("- Winner: `" + d.Winner.String() + "`\n")
	}
	return b.String()
}

func renderPlayer(rawAddr string) string {
	addr := strings.TrimSpace(rawAddr)
	safe := escapeInline(addr)

	v := players.Get(addr)
	if v == nil {
		return "# Player " + safe + "\n\nNo recorded duels yet.\n"
	}
	ps := v.(*playerState)

	var b strings.Builder
	b.WriteString("# Player " + safe + "\n\n")
	b.WriteString("- Wins: " + strconv.Itoa(ps.Wins) + "\n")
	b.WriteString("- Losses: " + strconv.Itoa(ps.Losses) + "\n")
	b.WriteString("- Draws: " + strconv.Itoa(ps.Draws) + "\n")
	b.WriteString("- Duels played: " + strconv.Itoa(ps.Duels) + "\n")
	if ps.Forfeits > 0 {
		b.WriteString("- Forfeited (didn't reveal in time): " + strconv.Itoa(ps.Forfeits) + "\n")
	}
	return b.String()
}

// Render shows the duel lobby at "", a specific duel when path is a
// numeric ID, or one player's record when path is their bech32 address.
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
