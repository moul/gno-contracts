// Package counter implements "Counter Club": a single shared integer counter
// with a rolling history of the last 20 mutations. Anyone may Inc, Dec, or
// Reset the value; every change records the caller, the delta applied, the
// resulting value, and the block height it happened at.
package counter

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
)

// maxHistory is the number of recent changes kept in the log.
const maxHistory = 20

// change is a single recorded mutation of the counter.
type change struct {
	caller address // who triggered the change
	delta  int     // how much the value moved (+1, -1, or reset amount)
	value  int     // the resulting counter value after the change
	height int64   // block height at which it occurred
}

// value is the current shared counter.
var value int

// total counts every mutation ever applied (not capped, unlike history).
var total int

// history holds the last maxHistory changes, oldest first.
var history []change

// record appends a change to the history, trimming to the last maxHistory.
func record(delta, newValue int) {
	c := change{
		caller: unsafe.PreviousRealm().Address(),
		delta:  delta,
		value:  newValue,
		height: runtime.ChainHeight(),
	}
	history = append(history, c)
	if len(history) > maxHistory {
		history = history[len(history)-maxHistory:]
	}
	total++
	chain.Emit(
		"CounterChange",
		"delta", strconv.Itoa(delta),
		"value", strconv.Itoa(newValue),
	)
}

// Inc adds one to the shared counter and logs the change.
func Inc(cur realm) int {
	value++
	record(1, value)
	return value
}

// Dec subtracts one from the shared counter and logs the change.
func Dec(cur realm) int {
	value--
	record(-1, value)
	return value
}

// Reset sets the shared counter back to zero and logs the change. The recorded
// delta is the amount required to bring the previous value to zero.
func Reset(cur realm) int {
	delta := -value
	value = 0
	record(delta, value)
	return value
}

// Value returns the current counter value (read-only helper).
func Value() int {
	return value
}

// Total returns the total number of mutations ever applied.
func Total() int {
	return total
}

// Render produces a Markdown view: the big current value, the total number of
// changes, and a table of the most recent changes (newest first).
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Counter Club\n\n")
	b.WriteString("A shared counter anyone can Inc, Dec, or Reset. ")
	b.WriteString("The last ")
	b.WriteString(strconv.Itoa(maxHistory))
	b.WriteString(" changes are logged below.\n\n")

	// Big current value.
	b.WriteString("## Current value\n\n")
	b.WriteString("# ")
	b.WriteString(strconv.Itoa(value))
	b.WriteString("\n\n")

	b.WriteString("**Total changes:** ")
	b.WriteString(strconv.Itoa(total))
	b.WriteString("\n\n")

	// Recent history, newest first.
	b.WriteString("## Recent history\n\n")
	if len(history) == 0 {
		b.WriteString("_No changes yet — be the first to count!_\n")
		return b.String()
	}

	b.WriteString("| # | Caller | Delta | New value | Height |\n")
	b.WriteString("|---|--------|-------|-----------|--------|\n")
	n := len(history)
	for i := n - 1; i >= 0; i-- {
		c := history[i]
		b.WriteString("| ")
		b.WriteString(strconv.Itoa(n - i))
		b.WriteString(" | ")
		b.WriteString(c.caller.String())
		b.WriteString(" | ")
		b.WriteString(signed(c.delta))
		b.WriteString(" | ")
		b.WriteString(strconv.Itoa(c.value))
		b.WriteString(" | ")
		b.WriteString(strconv.FormatInt(c.height, 10))
		b.WriteString(" |\n")
	}

	return b.String()
}

// signed formats an int with an explicit leading sign for non-negative values.
func signed(n int) string {
	if n >= 0 {
		return "+" + strconv.Itoa(n)
	}
	return strconv.Itoa(n)
}
