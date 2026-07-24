// Package dice implements a provably-fair on-chain dice game for gno.land.
//
// There is no true randomness on-chain: every node must reach the same result
// deterministically. Instead, each roll derives its 1-6 face from public block
// entropy (chain height) mixed with the caller address and the caller's roll
// count. The derivation is fully reproducible from public data, which is what
// "provably fair" means here — anyone can recompute a roll and verify it.
package dice

import (
	"chain"
	"chain/runtime"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// history holds every roll made by a single caller, most recent last.
type history struct {
	rolls []int // each value in [1,6]
}

var (
	// count[i] is the total number of times face (i+1) has come up globally.
	count [6]int
	// total is the total number of rolls across all callers.
	total int
	// players maps caller address string -> *history (deterministic iteration).
	players = avl.NewTree()
)

// deriveFace turns public entropy into a face in [1,6]. It is deterministic:
// the same (height, addr, n) always yields the same face, so any observer can
// recompute and verify a roll. Uses a simple FNV-1a-style hash over the mixed
// entropy bytes so different callers at the same height get different faces.
func deriveFace(height int64, addr string, n int) int {
	const (
		offset = uint64(1469598103934665603)
		prime  = uint64(1099511628211)
	)
	h := offset
	mix := func(v uint64) {
		for i := 0; i < 8; i++ {
			h ^= v & 0xff
			h *= prime
			v >>= 8
		}
	}
	mix(uint64(height))
	mix(uint64(n))
	for i := 0; i < len(addr); i++ {
		h ^= uint64(addr[i])
		h *= prime
	}
	return int(h%6) + 1
}

// Roll performs one dice roll for the calling account and records it.
//
// It is a crossing function (gno 0.9 interrealm convention: `cur realm` first
// parameter). Callers invoke it as Roll(cross(cur)). The result is derived
// deterministically from the current block height, the caller address, and the
// caller's prior roll count — no stored secret, fully verifiable.
func Roll(cur realm) int {
	if !cur.IsCurrent() {
		panic("dice: spoofed realm value")
	}
	addr := cur.Previous().Address().String()

	var h *history
	if v, ok := players.Get(addr); ok {
		h = v.(*history)
	} else {
		h = &history{}
		players.Set(addr, h)
	}

	face := deriveFace(runtime.ChainHeight(), addr, len(h.rolls))
	h.rolls = append(h.rolls, face)
	count[face-1]++
	total++

	chain.Emit("Roll", "player", addr, "face", strconv.Itoa(face))
	return face
}

// RollsOf returns the recorded roll history for an address (oldest first).
// Read-only helper, safe to call as a query.
func RollsOf(addr string) []int {
	v, ok := players.Get(addr)
	if !ok {
		return nil
	}
	out := v.(*history).rolls
	cp := make([]int, len(out))
	copy(cp, out)
	return cp
}

// Total returns the global roll count.
func Total() int { return total }

// Distribution returns the global per-face counts, faces 1-6.
func Distribution() [6]int { return count }

// bar renders a proportional ▓/░ bar of fixed width for a face's share.
func bar(n, max, width int) string {
	if max <= 0 {
		return strings.Repeat("░", width)
	}
	filled := n * width / max
	if filled > width {
		filled = width
	}
	return strings.Repeat("▓", filled) + strings.Repeat("░", width-filled)
}

// Render returns the realm's gnoweb Markdown view.
//
// Render is NOT a crossing function (no `cur realm` param) — it is a read-only
// query surface. It shows the total roll count, a distribution bar chart for
// faces 1-6, and the most recent rolls.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# 🎲 Provably-Fair Dice\n\n")
	b.WriteString("Every roll is derived deterministically from the block height, ")
	b.WriteString("the caller address, and their roll count — no hidden randomness, ")
	b.WriteString("fully reproducible from public data.\n\n")

	b.WriteString("**Total rolls:** " + strconv.Itoa(total) + "\n\n")

	// Distribution bar chart.
	b.WriteString("## Distribution\n\n")
	max := 0
	for _, c := range count {
		if c > max {
			max = c
		}
	}
	for face := 1; face <= 6; face++ {
		c := count[face-1]
		pct := 0
		if total > 0 {
			pct = c * 100 / total
		}
		b.WriteString("`" + strconv.Itoa(face) + "` ")
		b.WriteString(bar(c, max, 20))
		b.WriteString(" " + strconv.Itoa(c))
		b.WriteString(" (" + strconv.Itoa(pct) + "%)\n\n")
	}

	// Recent rolls: walk players, collect last rolls, show most recent globally.
	b.WriteString("## Recent rolls\n\n")
	if total == 0 {
		b.WriteString("_No rolls yet. Call `Roll` to play._\n")
		return b.String()
	}
	type entry struct {
		addr string
		face int
	}
	recent := []entry{}
	players.Iterate("", "", func(key string, value interface{}) bool {
		h := value.(*history)
		// take up to the last 3 rolls of each player
		start := len(h.rolls) - 3
		if start < 0 {
			start = 0
		}
		for _, f := range h.rolls[start:] {
			recent = append(recent, entry{addr: key, face: f})
		}
		return false
	})
	// show at most the last 10 collected
	start := len(recent) - 10
	if start < 0 {
		start = 0
	}
	for _, e := range recent[start:] {
		short := e.addr
		if len(short) > 12 {
			short = short[:8] + "…" + short[len(short)-4:]
		}
		b.WriteString("- 🎲 **" + strconv.Itoa(e.face) + "** — `" + short + "`\n")
	}
	return b.String()
}
