// Package streaks is an on-chain habit-streak tracker. Call CheckIn() again
// within graceBlocks of your last check-in and the streak keeps growing; let
// the gap run past that and it resets to zero on your next check-in. Gno has
// no wall clock, so "again soon enough" is measured in blocks rather than
// calendar days — graceBlocks is the tunable stand-in for "before tomorrow".
package streaks

import (
	"sort"
	"strconv"

	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// graceBlocks is the max block gap between two check-ins that still counts
// as consecutive. A gap larger than this lapses the streak.
const graceBlocks int64 = 100

// record is the persisted streak state for one address.
type record struct {
	owner      address
	current    int64
	longest    int64
	total      int64
	lastHeight int64
}

var streaks avl.Tree // owner address string -> *record

func get(owner address) (*record, bool) {
	v, ok := streaks.Get(owner.String()).(*record)
	return v, ok
}

// project reports the record's current streak as of height without
// mutating it: once the gap since lastHeight exceeds graceBlocks the streak
// reads as lapsed, even though the stored value only resets on the next
// actual check-in.
func project(r *record, height int64) (current int64, alive bool) {
	if height-r.lastHeight > graceBlocks {
		return 0, false
	}
	return r.current, true
}

// checkin is the non-crossing core of CheckIn, kept separate so unit tests
// can drive it directly by address and height.
func checkin(owner address, height int64) string {
	r, ok := get(owner)
	if !ok {
		r = &record{owner: owner}
		streaks.Set(owner.String(), r)
	} else {
		if height <= r.lastHeight {
			panic("already checked in at this block height")
		}
		if height-r.lastHeight > graceBlocks {
			r.current = 0
		}
	}
	r.current++
	if r.current > r.longest {
		r.longest = r.current
	}
	r.lastHeight = height
	r.total++
	return "checked in — current streak: " + strconv.FormatInt(r.current, 10) + " 🔥"
}

// CheckIn records a check-in for the caller at the current block height.
func CheckIn(cur realm) string {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	return checkin(cur.Previous().Address(), runtime.ChainHeight())
}

// CurrentStreak returns addr's live current streak, 0 if it has lapsed or
// addr has never checked in.
func CurrentStreak(addr string) int64 {
	r, ok := get(address(addr))
	if !ok {
		return 0
	}
	current, _ := project(r, runtime.ChainHeight())
	return current
}

// LongestStreak returns addr's best streak ever, 0 if it has never checked in.
func LongestStreak(addr string) int64 {
	r, ok := get(address(addr))
	if !ok {
		return 0
	}
	return r.longest
}

// byRank orders the leaderboard by longest streak, then current streak, then
// owner address — fully deterministic regardless of avl iteration order.
type byRank []*record

func (b byRank) Len() int      { return len(b) }
func (b byRank) Swap(i, j int) { b[i], b[j] = b[j], b[i] }
func (b byRank) Less(i, j int) bool {
	if b[i].longest != b[j].longest {
		return b[i].longest > b[j].longest
	}
	if b[i].current != b[j].current {
		return b[i].current > b[j].current
	}
	return b[i].owner.String() < b[j].owner.String()
}

func shortAddr(a address) string {
	s := a.String()
	if len(s) > 12 {
		return s[:8] + "…" + s[len(s)-4:]
	}
	return s
}

func renderDetail(r *record, height int64) string {
	current, alive := project(r, height)
	status := "🔥 active"
	if !alive {
		status = "💤 lapsed"
	}
	out := "## `" + shortAddr(r.owner) + "`\n\n"
	out += "- Status: " + status + "\n"
	out += "- Current streak: " + strconv.FormatInt(current, 10) + "\n"
	out += "- Longest streak: " + strconv.FormatInt(r.longest, 10) + "\n"
	out += "- Total check-ins: " + strconv.FormatInt(r.total, 10) + "\n"
	out += "- Last check-in at block " + strconv.FormatInt(r.lastHeight, 10) + "\n"
	return out
}

// Render shows either the full leaderboard (path == "") or a single
// address's detail card when path is a bech32 address.
func Render(path string) string {
	height := runtime.ChainHeight()

	out := "# 🔥 Streaks\n\n"
	out += "An on-chain habit-streak tracker. Call `CheckIn()` again within " +
		strconv.FormatInt(graceBlocks, 10) + " blocks of your last check-in to keep it alive; " +
		"wait longer than that and it resets to zero on your next check-in.\n\n"

	if path != "" {
		r, ok := get(address(path))
		if !ok {
			return out + "_No check-ins yet for `" + path + "`._\n"
		}
		return out + renderDetail(r, height)
	}

	var rows []*record
	streaks.Iterate("", "", func(_ string, v any) bool {
		rows = append(rows, v.(*record))
		return false
	})
	if len(rows) == 0 {
		out += "_Nobody has checked in yet. Be the first!_\n"
		return out
	}
	sort.Stable(byRank(rows))

	out += "| Rank | Address | Status | Current | Longest | Total |\n"
	out += "| ---: | :--- | :--- | ---: | ---: | ---: |\n"
	for i, r := range rows {
		current, alive := project(r, height)
		status := "🔥"
		if !alive {
			status = "💤"
		}
		out += "| " + strconv.Itoa(i+1) + " | `" + shortAddr(r.owner) + "` | " + status +
			" | " + strconv.FormatInt(current, 10) + " | " + strconv.FormatInt(r.longest, 10) +
			" | " + strconv.FormatInt(r.total, 10) + " |\n"
	}
	out += "\n_View a single address at `?<address>`._\n"
	return out
}
