// Package guestbook is a public, on-chain guestbook realm for gno.land.
//
// Anyone can sign the guestbook with a short message via the Sign crossing
// function. Every entry records the caller's address, the message, and the
// block height at which it was signed. Render lists all entries newest-first
// as a Markdown table.
//
// v1 renders through [p/moul/kit/ui](/p/moul/kit/ui/v0) instead of the
// hand-rolled shortAddr and escapeCell helpers v0 carried. The escaping is the
// substantive change: v0 replaced four characters, while ui.Cell also strips
// bidi and zero-width characters, which a message can otherwise use to reorder
// how the rest of the row reads.
package guestbook

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/moul/kit/ui/v0"
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
	if count == 0 {
		return "# Guestbook\n\n" + ui.Empty("No one has signed yet. Be the first!")
	}

	t := ui.NewTable("#", "Who", "Message", "Height")
	// avl iterates ascending by key; ReverseIterate gives newest-first.
	entries.ReverseIterate("", "", func(_ string, v any) bool {
		e := v.(*Entry)
		t.Row(
			strconv.Itoa(e.ID),
			ui.AddrOf(e.Author),
			ui.Cell(e.Message),
			strconv.FormatInt(e.Height, 10),
		)
		return false
	})

	return "# Guestbook\n\n**Total signatures:** " + strconv.Itoa(count) + "\n\n" + t.String()
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
