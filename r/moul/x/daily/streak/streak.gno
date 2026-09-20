// Package streak is an on-chain check-in streak tracker: call CheckIn once per
// "day" to keep a streak alive, miss one and it resets to 1.
//
// There is no wall clock on-chain, so a "day" here is a fixed window of
// BlocksPerDay blocks: day = ChainHeight() / BlocksPerDay. That makes every
// streak decision a pure function of block height — deterministic, replayable,
// and impossible to game by waiting for a favourable timestamp.
//
// State is per-caller and append-only in spirit: an address's best streak is
// never lowered, so breaking a run costs the current streak but not the record.
//
// This is a stateful app with nothing reusable to extract, so it ships as a
// lone realm rather than a p/ library + demo pair.
package streak

import (
	"sort"
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// BlocksPerDay is the length of a check-in window, in blocks. Chosen so a
// window is a meaningful stretch of chain activity while keeping tests and
// demos quick to reason about.
const BlocksPerDay = 1000

// maxLeaderboard caps how many entries Render lists.
const maxLeaderboard = 10

// record is one address's streak state.
type record struct {
	current int   // consecutive days up to lastDay
	best    int   // highest current ever reached; never lowered
	lastDay int64 // day index of the most recent check-in
	totalIn int   // total check-ins ever
}

// users maps address string -> *record.
var users = avl.NewTree()

// today returns the current day index: block height divided into fixed windows.
func today() int64 { return runtime.ChainHeight() / BlocksPerDay }

// CheckIn records a check-in for the caller and returns the resulting streak.
//
// Checking in twice in the same window is rejected — the streak only moves when
// the window does. A gap of exactly one window continues the streak; any larger
// gap restarts it at 1.
func CheckIn(cur realm) int {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("only an EOA via MsgCall can check in")
	}
	addr := prev.Address()
	day := today()

	r := get(addr)
	if r == nil {
		r = &record{}
		users.Set(addr.String(), r)
	} else {
		switch {
		case r.totalIn > 0 && r.lastDay == day:
			panic("already checked in for day " + strconv.FormatInt(day, 10))
		case r.totalIn > 0 && r.lastDay == day-1:
			// consecutive window: the streak continues below
		default:
			// missed at least one window: the run is broken
			r.current = 0
		}
	}

	r.current++
	r.lastDay = day
	r.totalIn++
	if r.current > r.best {
		r.best = r.current
	}

	chain.Emit("CheckIn",
		"addr", addr.String(),
		"day", strconv.FormatInt(day, 10),
		"streak", strconv.Itoa(r.current),
	)
	return r.current
}

// get returns the caller's record, or nil.
//
// avl/v0's Get returns a single `any` (not the value, ok pair Go maps use), so
// a missing key surfaces as a nil interface rather than a second return value.
func get(addr address) *record {
	v := users.Get(addr.String())
	if v == nil {
		return nil
	}
	return v.(*record)
}

// Current returns addr's live streak — 0 once a window has been missed, even
// though the stored value only updates on the next check-in.
func Current(addr address) int {
	r := get(addr)
	if r == nil {
		return 0
	}
	day := today()
	if r.lastDay != day && r.lastDay != day-1 {
		return 0
	}
	return r.current
}

// Best returns addr's record streak, which is never lowered.
func Best(addr address) int {
	r := get(addr)
	if r == nil {
		return 0
	}
	return r.best
}

// Day returns the current day index.
func Day() int64 { return today() }

// entry is a flattened record for rendering.
type entry struct {
	addr    string
	current int
	best    int
	total   int
}

// byBest ranks entries by best streak descending, then by address so equal
// scores always come out in the same order (Render must be deterministic).
type byBest []entry

func (e byBest) Len() int      { return len(e) }
func (e byBest) Swap(i, j int) { e[i], e[j] = e[j], e[i] }
func (e byBest) Less(i, j int) bool {
	if e[i].best != e[j].best {
		return e[i].best > e[j].best
	}
	return e[i].addr < e[j].addr
}

// Render renders the streak board for gnoweb.
//
//	Render("")          / Render("/") -> leaderboard by best streak
//	Render("/<address>")             -> that address's standing
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Check-in Streaks\n\n")
	b.WriteString("A \"day\" is ")
	b.WriteString(strconv.Itoa(BlocksPerDay))
	b.WriteString(" blocks — there is no clock on-chain, so streaks are decided by block height alone.\n\n")
	b.WriteString("Current day: **")
	b.WriteString(strconv.FormatInt(today(), 10))
	b.WriteString("**\n\n")

	if q := parseArg(path); q != "" {
		return b.String() + renderOne(q)
	}

	entries := all()
	if len(entries) == 0 {
		b.WriteString("_Nobody has checked in yet._\n\n")
		b.WriteString("> Call `CheckIn()` to start a streak.\n")
		return b.String()
	}

	// gno's sort has Sort(Interface) but no Slice(), so ranking goes through an
	// explicit sort.Interface. Ties break on address so the board is stable.
	sort.Sort(byBest(entries))
	if len(entries) > maxLeaderboard {
		entries = entries[:maxLeaderboard]
	}

	b.WriteString("| # | address | current | best | check-ins |\n|---|---|---|---|---|\n")
	for i, e := range entries {
		b.WriteString("| ")
		b.WriteString(strconv.Itoa(i + 1))
		b.WriteString(" | `")
		b.WriteString(e.addr)
		b.WriteString("` | ")
		b.WriteString(strconv.Itoa(e.current))
		b.WriteString(" | ")
		b.WriteString(strconv.Itoa(e.best))
		b.WriteString(" | ")
		b.WriteString(strconv.Itoa(e.total))
		b.WriteString(" |\n")
	}
	return b.String()
}

// renderOne renders a single address's standing.
func renderOne(q string) string {
	addr := address(q)
	var b strings.Builder
	b.WriteString("## `")
	b.WriteString(q)
	b.WriteString("`\n\n")
	if !addr.IsValid() {
		b.WriteString("_Not a valid address._\n")
		return b.String()
	}
	r := get(addr)
	if r == nil {
		b.WriteString("_No check-ins yet._\n")
		return b.String()
	}
	b.WriteString("- current streak: **")
	b.WriteString(strconv.Itoa(Current(addr)))
	b.WriteString("**\n- best streak: **")
	b.WriteString(strconv.Itoa(r.best))
	b.WriteString("**\n- total check-ins: **")
	b.WriteString(strconv.Itoa(r.totalIn))
	b.WriteString("**\n- last check-in: day **")
	b.WriteString(strconv.FormatInt(r.lastDay, 10))
	b.WriteString("**\n")
	return b.String()
}

// all flattens the tree into a slice.
func all() []entry {
	out := []entry{}
	users.Iterate("", "", func(k string, v any) bool {
		r := v.(*record)
		out = append(out, entry{
			addr:    k,
			current: Current(address(k)),
			best:    r.best,
			total:   r.totalIn,
		})
		return false
	})
	return out
}

// parseArg extracts the first path segment.
func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
