// Package ringlog is an on-chain port of Go's container/ring: a fixed-capacity
// circular message board where new posts overwrite the oldest entries once full.
package ringlog

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"
)

// Cap is the maximum number of messages the ring buffer holds.
const Cap = 16

// Entry is a single posted message.
type Entry struct {
	Author  address
	Message string
	Height  int64
}

var (
	buf   [Cap]Entry // the ring storage
	head  int        // index of the next write slot
	count int        // number of entries currently stored (0 ≤ count ≤ Cap)
)

// Post adds a message to the ring buffer.
// Once Cap entries are stored, the oldest entry is overwritten.
func Post(msg string) {
	msg = strings.TrimSpace(msg)
	if len(msg) == 0 {
		panic("message cannot be empty")
	}
	if len(msg) > 280 {
		panic("message too long (max 280 chars)")
	}
	buf[head] = Entry{
		Author:  unsafe.PreviousRealm().Address(),
		Message: msg,
		Height:  runtime.ChainHeight(),
	}
	head = (head + 1) % Cap
	if count < Cap {
		count++
	}
}

// Entries returns all stored messages in chronological order (oldest first).
func Entries() []Entry {
	if count == 0 {
		return nil
	}
	result := make([]Entry, count)
	oldest := (head - count + Cap) % Cap
	for i := 0; i < count; i++ {
		result[i] = buf[(oldest+i)%Cap]
	}
	return result
}

// Len returns the number of messages currently stored.
func Len() int { return count }

// Render displays the ring buffer as a Markdown page.
func Render(path string) string {
	var sb strings.Builder

	sb.WriteString("# RingLog\n\n")
	sb.WriteString("> A ring-buffer message board (capacity: **")
	sb.WriteString(strconv.Itoa(Cap))
	sb.WriteString("**). New messages overwrite the oldest once the buffer is full.\n\n")

	if count == 0 {
		sb.WriteString("*No messages yet. Call `Post(msg)` to add one.*\n")
		return sb.String()
	}

	sb.WriteString("| # | Author | Block | Message |\n")
	sb.WriteString("|---|--------|-------|---------|\n")

	entries := Entries()
	for i, e := range entries {
		sb.WriteString("| ")
		sb.WriteString(strconv.Itoa(i + 1))
		sb.WriteString(" | `")
		sb.WriteString(shorten(e.Author.String()))
		sb.WriteString("` | ")
		sb.WriteString(strconv.FormatInt(e.Height, 10))
		sb.WriteString(" | ")
		sb.WriteString(e.Message)
		sb.WriteString(" |\n")
	}

	sb.WriteString("\n*Showing ")
	sb.WriteString(strconv.Itoa(count))
	sb.WriteString(" of ")
	sb.WriteString(strconv.Itoa(Cap))
	sb.WriteString(" slots used.*\n")

	return sb.String()
}

// shorten trims a long address for display.
func shorten(s string) string {
	if len(s) <= 14 {
		return s
	}
	return s[:6] + "…" + s[len(s)-6:]
}
