// Package kingofdice is a "king of the hill" dice game. Anyone can Roll a
// pseudo-random 1-100 die; beat the reigning king's roll and you dethrone
// them, becoming king yourself. The leaderboard doesn't rank raw points — it
// ranks accumulated *reign length*, measured in blocks held as king, so
// camping on a lucky high roll pays off more than a single spike.
package kingofdice

import (
	"sort"
	"strconv"

	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// playerStats is the persisted record for one address.
type playerStats struct {
	addr              address
	rolls             int
	bestRoll          int
	reigns            int
	totalReignBlocks  int64 // blocks held as king across all past reigns
}

var (
	players avl.Tree // address string -> *playerStats

	king       address
	kingRoll   int
	reignSince int64 // chain height at which the current king took the throne

	nonce     int
	totalRolls int
)

// get returns the stored *playerStats for addr, creating one if absent.
func get(addr address) *playerStats {
	key := addr.String()
	if v, ok := players.Get(key); ok {
		return v.(*playerStats)
	}
	ps := &playerStats{addr: addr}
	players.Set(key, ps)
	return ps
}

// pseudoRoll derives a deterministic 1-100 value from the caller's address,
// a per-call nonce, and the current chain height, so no two calls in the
// same block from the same address collide, yet the result can't be
// pre-computed off-chain before the triggering transaction lands.
func pseudoRoll(addr address, nonce int, height int64) int {
	s := addr.String()
	var h int64
	for i := 0; i < len(s); i++ {
		h = h*31 + int64(s[i])
	}
	h += int64(nonce)*104729 + height*7919
	if h < 0 {
		h = -h
	}
	return int(h%100) + 1
}

// Roll throws the die for the caller. Rolling higher than the current king's
// roll dethrones them (crediting their finished reign in blocks) and crowns
// the caller as the new king.
func Roll(cur realm) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	caller := cur.Previous().Address()

	nonce++
	totalRolls++
	height := runtime.ChainHeight()
	roll := pseudoRoll(caller, nonce, height)

	ps := get(caller)
	ps.rolls++
	if roll > ps.bestRoll {
		ps.bestRoll = roll
	}

	if !king.IsValid() || roll > kingRoll {
		if king.IsValid() {
			prev := get(king)
			prev.totalReignBlocks += height - reignSince
		}
		king = caller
		kingRoll = roll
		reignSince = height
		ps.reigns++
		return "you rolled " + strconv.Itoa(roll) + " and seized the throne!"
	}

	if king == caller {
		return "you rolled " + strconv.Itoa(roll) + " — you're still king (need to beat " +
			strconv.Itoa(kingRoll) + ")"
	}
	return "you rolled " + strconv.Itoa(roll) + " — not enough to dethrone the king's " +
		strconv.Itoa(kingRoll)
}

// effectiveReignBlocks returns a player's accumulated reign length, including
// the currently-in-progress reign if they are the sitting king. It does not
// mutate state — it's a display-time projection.
func effectiveReignBlocks(ps *playerStats, height int64) int64 {
	if king.IsValid() && ps.addr == king {
		return ps.totalReignBlocks + (height - reignSince)
	}
	return ps.totalReignBlocks
}

// byReign implements sort.Interface, ranking players by effective reign
// length descending, ties broken by best roll then address so the order is
// fully deterministic.
type byReign struct {
	stats  []*playerStats
	blocks []int64
}

func (r byReign) Len() int      { return len(r.stats) }
func (r byReign) Swap(i, j int) {
	r.stats[i], r.stats[j] = r.stats[j], r.stats[i]
	r.blocks[i], r.blocks[j] = r.blocks[j], r.blocks[i]
}
func (r byReign) Less(i, j int) bool {
	if r.blocks[i] != r.blocks[j] {
		return r.blocks[i] > r.blocks[j]
	}
	if r.stats[i].bestRoll != r.stats[j].bestRoll {
		return r.stats[i].bestRoll > r.stats[j].bestRoll
	}
	return r.stats[i].addr.String() < r.stats[j].addr.String()
}

// snapshot collects all players ranked by effective reign length descending.
func snapshot(height int64) ([]*playerStats, []int64) {
	stats := make([]*playerStats, 0, players.Size())
	players.Iterate("", "", func(_ string, v any) bool {
		stats = append(stats, v.(*playerStats))
		return false
	})
	blocks := make([]int64, len(stats))
	for i, ps := range stats {
		blocks[i] = effectiveReignBlocks(ps, height)
	}
	sort.Stable(byReign{stats: stats, blocks: blocks})
	return stats, blocks
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

// display returns a shortened address for table display.
func display(addr address) string {
	s := addr.String()
	if len(s) > 12 {
		return s[:8] + "…" + s[len(s)-4:]
	}
	return s
}

// Render shows the current king and a reign-length leaderboard.
func Render(path string) string {
	height := runtime.ChainHeight()

	out := "# 👑 King of the Dice\n\n"
	out += "Roll higher than the reigning king to take the throne. The leaderboard " +
		"ranks total blocks held as king, not raw roll count — outlasting beats " +
		"getting lucky once.\n\n"

	if !king.IsValid() {
		out += "_No king yet. Call `Roll()` to make the first claim._\n\n"
	} else {
		out += "**Current king:** `" + display(king) + "` with a roll of **" +
			strconv.Itoa(kingRoll) + "**, reigning for **" +
			strconv.Itoa(int(height-reignSince)) + "** blocks so far.\n\n"
	}
	out += "Total rolls: **" + strconv.Itoa(totalRolls) + "**\n\n"

	stats, blocks := snapshot(height)
	if len(stats) == 0 {
		return out
	}

	out += "| Rank | Player | Blocks reigned | Reigns | Best roll | Rolls |\n"
	out += "| ---: | :--- | ---: | ---: | ---: | ---: |\n"
	for i, ps := range stats {
		rankCell := medal(i)
		if rankCell == "" {
			rankCell = strconv.Itoa(i + 1)
		}
		out += "| " + rankCell +
			" | " + display(ps.addr) +
			" | " + strconv.Itoa(int(blocks[i])) +
			" | " + strconv.Itoa(ps.reigns) +
			" | " + strconv.Itoa(ps.bestRoll) +
			" | " + strconv.Itoa(ps.rolls) + " |\n"
	}
	return out
}
