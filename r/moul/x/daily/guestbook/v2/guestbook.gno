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

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/kit/ui/v0"
)

// Entry is a single signed guestbook line. It carries no ID field: the id
// belongs to the store, which hands it back on lookup and iteration.
type Entry struct {
	Author  string // bech32 address of the signer
	Message string // the message left by the signer
	Height  int64  // block height at which the entry was signed
}

const maxMessageLen = 280

// entries assigns the sequence numbers. v1 kept its own count plus a seqKey()
// that zero-padded to width 16, the widest of the six hand-rolled variants in
// this repo and still a ceiling; the store key has none.
var entries = store.Named("guestbook: entry")

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
	id, e := addEntry(author, message, runtime.ChainHeight())

	chain.Emit("Signed",
		"id", id.String(),
		"author", e.Author,
		"height", strconv.FormatInt(e.Height, 10),
	)
}

// addEntry validates the message and appends an entry. Non-crossing internal
// helper so the append/validation logic is unit-testable without a realm frame.
// Panics (aborting the tx, reverting state) on an invalid message.
func addEntry(author, message string, height int64) (store.ID, *Entry) {
	msg := strings.TrimSpace(message)
	if msg == "" {
		panic("guestbook: message must not be empty")
	}
	if len(msg) > maxMessageLen {
		panic("guestbook: message too long (max " + strconv.Itoa(maxMessageLen) + " bytes)")
	}

	e := &Entry{
		Author:  author,
		Message: msg,
		Height:  height,
	}
	return entries.Add(e), e
}

// Count returns the total number of signatures. Read-only, non-crossing.
func Count() int {
	return entries.Len()
}

// Render lists every entry newest-first as a Markdown table plus a total count.
func Render(path string) string {
	if entries.Len() == 0 {
		return "# Guestbook\n\n" + ui.Empty("No one has signed yet. Be the first!")
	}

	t := ui.NewTable("#", "Who", "Message", "Height")
	// Ids ascend with signing, so reverse iteration is newest-first.
	entries.EachReverse(func(id store.ID, v any) {
		e := v.(*Entry)
		t.Row(
			id.String(),
			ui.AddrOf(e.Author),
			ui.Cell(e.Message),
			strconv.FormatInt(e.Height, 10),
		)
	})

	return "# Guestbook\n\n**Total signatures:** " + strconv.Itoa(entries.Len()) + "\n\n" + t.String()
}
