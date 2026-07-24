// Package leaderboard is an on-chain score leaderboard realm.
//
// Any account can accumulate points via AddPoints and (optionally) attach a
// display name with SetName. Render produces a ranked Markdown table sorted by
// points descending, with medals for the top three players.
package leaderboard

import (
	"sort"
	"strconv"

	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// player holds the accumulated state for a single address.
type player struct {
	addr   address
	name   string
	points int
}

// players maps address string -> *player. An avl.Tree gives deterministic
// iteration (unlike a Go map) so Render output is stable across nodes.
var players avl.Tree

// get returns the stored *player for addr, creating one if absent.
func get(addr address) *player {
	key := addr.String()
	if v, ok := players.Get(key); ok {
		return v.(*player)
	}
	p := &player{addr: addr}
	players.Set(key, p)
	return p
}

// caller returns the address of the account that invoked the current tx.
// unsafe.PreviousRealm() is the origin user for a MsgCall entry point.
func caller() address {
	return unsafe.PreviousRealm().Address()
}

// AddPoints adds n points to the caller's total. n must be positive.
//
// Crossing function: MsgCall dispatches only to crossing functions, and the
// cur.IsCurrent() check authenticates the live call frame before we trust the
// caller identity derived from it.
func AddPoints(cur realm, n int) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	if n <= 0 {
		panic("points must be positive")
	}
	p := get(caller())
	p.points += n
}

// SetName attaches a display name (max 32 bytes) to the caller. Passing an
// empty string clears the name and falls back to the address in Render.
func SetName(cur realm, name string) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	if len(name) > 32 {
		panic("name too long (max 32)")
	}
	get(caller()).name = name
}

// display returns the player's name, or a shortened address if unnamed.
func (p *player) display() string {
	if p.name != "" {
		return p.name
	}
	s := p.addr.String()
	if len(s) > 12 {
		return s[:8] + "…" + s[len(s)-4:]
	}
	return s
}

// byRank implements sort.Interface, ranking players by points descending with
// ties broken by address so the order is deterministic across nodes. The gno
// sort package exposes Sort/Stable over an Interface — there is no sort.Slice.
type byRank []*player

func (r byRank) Len() int      { return len(r) }
func (r byRank) Swap(i, j int) { r[i], r[j] = r[j], r[i] }
func (r byRank) Less(i, j int) bool {
	if r[i].points != r[j].points {
		return r[i].points > r[j].points
	}
	return r[i].addr.String() < r[j].addr.String()
}

// snapshot collects all players into a slice ranked by points descending.
func snapshot() []*player {
	out := make([]*player, 0, players.Size())
	players.Iterate("", "", func(_ string, v any) bool {
		out = append(out, v.(*player))
		return false
	})
	sort.Stable(byRank(out))
	return out
}

// medal returns the emoji for a given zero-based rank, or "" past the podium.
func medal(rank int) string {
	switch rank {
	case 0:
		return "🥇"
	case 1:
		return "🥈"
	case 2:
		return "🥉"
	default:
		return ""
	}
}

// Render produces the Markdown leaderboard. It is NOT a crossing function
// (read-only view, no cur realm parameter).
func Render(path string) string {
	ranked := snapshot()

	out := "# 🏆 Leaderboard\n\n"
	if len(ranked) == 0 {
		out += "_No players yet. Call `AddPoints(n)` to get on the board._\n"
		return out
	}

	out += "Total players: **" + strconv.Itoa(len(ranked)) + "**\n\n"
	out += "| Rank | Player | Points |\n"
	out += "| ---: | :--- | ---: |\n"
	for i, p := range ranked {
		rankCell := medal(i)
		if rankCell == "" {
			rankCell = strconv.Itoa(i + 1)
		}
		out += "| " + rankCell +
			" | " + p.display() +
			" | " + strconv.Itoa(p.points) + " |\n"
	}
	return out
}
