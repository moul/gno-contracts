// Package guestbook is a public, on-chain guestbook realm for gno.land.
//
// Anyone can sign the guestbook with a short message via the Sign crossing
// function. Every entry records the caller's address, the message, and the
// block height at which it was signed. Render lists all entries newest-first
// as a Markdown table.
package guestbook

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// Entry is a single signed guestbook line.
type Entry struct {
	ID      int    // 1-based sequence number
	Author  string // bech32 address of the signer
	Message string // the message left by the signer
	Height  int64  // block height at which the entry was signed
}

const maxMessageLen = 280

var (
	// entries is keyed by a zero-padded sequence so avl iteration is ordered.
	entries = avl.NewTree()
	count   int
)

// Sign appends a new entry to the guestbook attributed to the immediate caller.
//
// It is a crossing function (gno 0.9 interrealm convention): callers invoke it
// as Sign(cross(cur), "hello"). The cur.IsCurrent() guard is the authentication
// primitive — without it a stale/forged realm value could spoof the author.
func Sign(cur realm, message string) {
	if !cur.IsCurrent() {
		panic("guestbook: spoofed realm; Sign must be called via cross(cur)")
	}

	author := cur.Previous().Address().String()
	e := addEntry(author, message, runtime.ChainHeight())

	chain.Emit("Signed",
		"id", strconv.Itoa(e.ID),
		"author", e.Author,
		"height", strconv.FormatInt(e.Height, 10),
	)
}

// addEntry validates the message and appends an entry. Non-crossing internal
// helper so the append/validation logic is unit-testable without a realm frame.
// Panics (aborting the tx, reverting state) on an invalid message.
func addEntry(author, message string, height int64) *Entry {
	msg := strings.TrimSpace(message)
	if msg == "" {
		panic("guestbook: message must not be empty")
	}
	if len(msg) > maxMessageLen {
		panic("guestbook: message too long (max " + strconv.Itoa(maxMessageLen) + " bytes)")
	}

	count++
	e := &Entry{
		ID:      count,
		Author:  author,
		Message: msg,
		Height:  height,
	}
	entries.Set(seqKey(count), e)
	return e
}

// Count returns the total number of signatures. Read-only, non-crossing.
func Count() int {
	return count
}

// Render lists every entry newest-first as a Markdown table plus a total count.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Guestbook\n\n")

	if count == 0 {
		b.WriteString("_No one has signed yet. Be the first!_\n")
		return b.String()
	}

	b.WriteString("**Total signatures:** ")
	b.WriteString(strconv.Itoa(count))
	b.WriteString("\n\n")

	b.WriteString("| # | Who | Message | Height |\n")
	b.WriteString("|---|-----|---------|--------|\n")

	// avl iterates ascending by key; ReverseIterate gives newest-first.
	entries.ReverseIterate("", "", func(_ string, v any) bool {
		e := v.(*Entry)
		b.WriteString("| ")
		b.WriteString(strconv.Itoa(e.ID))
		b.WriteString(" | ")
		b.WriteString(shortAddr(e.Author))
		b.WriteString(" | ")
		b.WriteString(escapeCell(e.Message))
		b.WriteString(" | ")
		b.WriteString(strconv.FormatInt(e.Height, 10))
		b.WriteString(" |\n")
		return false
	})

	return b.String()
}

// seqKey renders a sequence number as a fixed-width, zero-padded string so
// avl's lexicographic key order matches numeric order.
func seqKey(n int) string {
	s := strconv.Itoa(n)
	const width = 16
	if len(s) >= width {
		return s
	}
	return strings.Repeat("0", width-len(s)) + s
}

// shortAddr abbreviates a bech32 address for compact display.
func shortAddr(addr string) string {
	if len(addr) <= 12 {
		return addr
	}
	return addr[:8] + "…" + addr[len(addr)-4:]
}

// escapeCell neutralizes characters that would break a Markdown table cell.
func escapeCell(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "|", "\\|")
	s = strings.ReplaceAll(s, "\r\n", " ")
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.ReplaceAll(s, "\r", " ")
	return s
}
