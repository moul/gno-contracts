// Package tipjar is a public tip jar. Anyone can send real ugnot with an
// optional message via Tip; the realm keeps a running leaderboard of the
// most generous tippers and a feed of the most recent tips, both shown in
// Render. Only the deployer (captured as owner at init time) can Withdraw
// the accumulated balance. State-mutating functions are crossing functions
// (`cur realm`) per the gno 0.9 interrealm convention.
package tipjar

import (
	"sort"
	"strconv"

	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

const (
	denom         = "ugnot"
	maxRecent     = 10
	maxMessageLen = 140
)

// tipperStats is the persisted, accumulated record for one tipper.
type tipperStats struct {
	addr        address
	total       int64
	count       int
	lastMessage string
	lastHeight  int64
}

// tipEntry is one line in the recent-tips feed.
type tipEntry struct {
	from    address
	amount  int64
	message string
	height  int64
}

var (
	owner address // captured deployer, set once in init

	tippers avl.Tree // address string -> *tipperStats
	recent  []tipEntry

	totalReceived int64
	withdrawn     int64
	tipCount      int
)

func init() {
	owner = unsafe.OriginCaller()
}

// get returns the stored *tipperStats for addr, creating one if absent.
func get(addr address) *tipperStats {
	key := addr.String()
	if v := tippers.Get(key); v != nil {
		return v.(*tipperStats)
	}
	ts := &tipperStats{addr: addr}
	tippers.Set(key, ts)
	return ts
}

// Tip credits the caller's OriginSend ugnot to the jar and records it
// against their running total. Only an EOA calling directly via MsgCall may
// tip — see the payment-guard note on IsUserCall vs IsUser.
func Tip(cur realm, message string) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("only an EOA via MsgCall can tip")
	}
	if len(message) > maxMessageLen {
		panic("message too long (max " + strconv.Itoa(maxMessageLen) + " chars)")
	}

	amount := unsafe.OriginSend().AmountOf(denom)
	if amount <= 0 {
		panic("send some ugnot to tip")
	}

	from := prev.Address()
	height := runtime.ChainHeight()

	ts := get(from)
	ts.total += amount
	ts.count++
	ts.lastMessage = message
	ts.lastHeight = height

	totalReceived += amount
	tipCount++

	recent = append(recent, tipEntry{from: from, amount: amount, message: message, height: height})
	if len(recent) > maxRecent {
		recent = recent[len(recent)-maxRecent:]
	}

	chain.Emit("Tip", "from", from.String(), "amount", strconv.FormatInt(amount, 10), "message", message)
	return "thanks for the " + strconv.FormatInt(amount, 10) + "ugnot tip!"
}

// Balance reports the ugnot still held by the jar (received minus withdrawn).
func Balance() int64 {
	return totalReceived - withdrawn
}

// Withdraw sends amount ugnot from the jar to the owner. Owner-only.
func Withdraw(cur realm, amount int64) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	if cur.Previous().Address() != owner {
		panic("only the owner can withdraw")
	}
	if amount <= 0 {
		panic("amount must be positive")
	}
	if amount > Balance() {
		panic("amount exceeds available balance")
	}

	bnk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bnk.SendCoins(cur.Address(), owner, chain.NewCoins(chain.NewCoin(denom, amount)))
	withdrawn += amount

	chain.Emit("Withdraw", "amount", strconv.FormatInt(amount, 10))
}

// byTotal implements sort.Interface, ranking tippers by total tipped
// descending, ties broken by tip count then address for a fully
// deterministic order.
type byTotal struct {
	stats []*tipperStats
}

func (b byTotal) Len() int      { return len(b.stats) }
func (b byTotal) Swap(i, j int) { b.stats[i], b.stats[j] = b.stats[j], b.stats[i] }
func (b byTotal) Less(i, j int) bool {
	if b.stats[i].total != b.stats[j].total {
		return b.stats[i].total > b.stats[j].total
	}
	if b.stats[i].count != b.stats[j].count {
		return b.stats[i].count > b.stats[j].count
	}
	return b.stats[i].addr.String() < b.stats[j].addr.String()
}

// leaderboard collects all tippers ranked by total tipped descending.
func leaderboard() []*tipperStats {
	stats := make([]*tipperStats, 0, tippers.Size())
	tippers.Iterate("", "", func(_ string, v any) bool {
		stats = append(stats, v.(*tipperStats))
		return false
	})
	sort.Stable(byTotal{stats: stats})
	return stats
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

// Render shows the jar's balance, the tipper leaderboard, and a feed of the
// most recent tips.
func Render(path string) string {
	out := "# 🫙 Tip Jar\n\n"
	out += "Send ugnot with `Tip(message)` to leave a tip and a note. " +
		"The owner can withdraw the accumulated balance with `Withdraw(amount)`.\n\n"

	out += "**Balance:** " + strconv.FormatInt(Balance(), 10) + "ugnot" +
		"  ·  **Total tips:** " + strconv.Itoa(tipCount) +
		"  ·  **All-time received:** " + strconv.FormatInt(totalReceived, 10) + "ugnot\n\n"

	stats := leaderboard()
	out += "## Leaderboard\n\n"
	if len(stats) == 0 {
		out += "_No tips yet. Be the first!_\n\n"
	} else {
		out += "| Rank | Tipper | Total tipped | Tips |\n"
		out += "| ---: | :--- | ---: | ---: |\n"
		for i, ts := range stats {
			rankCell := medal(i)
			if rankCell == "" {
				rankCell = strconv.Itoa(i + 1)
			}
			out += "| " + rankCell +
				" | " + display(ts.addr) +
				" | " + strconv.FormatInt(ts.total, 10) + "ugnot" +
				" | " + strconv.Itoa(ts.count) + " |\n"
		}
		out += "\n"
	}

	out += "## Recent tips\n\n"
	if len(recent) == 0 {
		out += "_Nothing yet._\n"
		return out
	}
	for i := len(recent) - 1; i >= 0; i-- {
		e := recent[i]
		out += "- **" + display(e.from) + "** tipped " + strconv.FormatInt(e.amount, 10) +
			"ugnot at block " + strconv.FormatInt(e.height, 10)
		if e.message != "" {
			out += ": _" + e.message + "_"
		}
		out += "\n"
	}
	return out
}
