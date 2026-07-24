// Package todos is a shared, on-chain to-do board realm.
//
// Anyone can add an item; the caller's address is recorded as the author.
// Items can be toggled (open/done) or removed. Render exposes the board as
// Markdown checkboxes with open/done counts, newest item first.
package todos

import (
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// item is one entry on the board. `address` is the uverse bech32 type — it is
// persistable (unlike a `realm` value), so it is safe to store across txs.
type item struct {
	id     int
	text   string
	done   bool
	author address
}

var (
	// items is keyed by zero-padded id string so avl iteration is ordered by id.
	items  avl.Tree
	nextID int
)

// Add appends a new item authored by the caller and returns its id.
//
// Crossing function: takes `cur realm` first (gno 0.9 interrealm convention),
// authenticates with cur.IsCurrent() before trusting cur.Previous().
func Add(cur realm, text string) int {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	text = strings.TrimSpace(text)
	if text == "" {
		panic("todos: text must not be empty")
	}

	author := cur.Previous().Address()

	nextID++
	id := nextID
	items.Set(idKey(id), &item{
		id:     id,
		text:   text,
		done:   false,
		author: author,
	})
	return id
}

// Toggle flips the done state of the item with the given id.
func Toggle(cur realm, id int) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	v, ok := items.Get(idKey(id))
	if !ok {
		panic("todos: item not found: #" + strconv.Itoa(id))
	}
	it := v.(*item)
	it.done = !it.done
}

// Remove deletes the item with the given id.
func Remove(cur realm, id int) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	if _, removed := items.Remove(idKey(id)); !removed {
		panic("todos: item not found: #" + strconv.Itoa(id))
	}
}

// idKey renders an id as a fixed-width, zero-padded key so avl.Tree's
// byte-lexicographic ordering matches numeric id ordering.
func idKey(id int) string {
	s := strconv.Itoa(id)
	const width = 12
	if len(s) >= width {
		return s
	}
	return strings.Repeat("0", width-len(s)) + s
}

// shortAddr renders an address as "g1abc…" (first 6 chars + ellipsis).
func shortAddr(a address) string {
	s := a.String()
	if len(s) <= 6 {
		return s
	}
	return s[:6] + "…"
}

// counts returns the number of open and done items.
func counts() (open, done int) {
	items.Iterate("", "", func(_ string, v interface{}) bool {
		if v.(*item).done {
			done++
		} else {
			open++
		}
		return false
	})
	return open, done
}

// Render returns the board as Markdown. Newest item (highest id) first.
//
// Render is NOT a crossing function (no `cur realm` param) — it is read-only
// and invoked by gnoweb, not via MsgCall.
func Render(path string) string {
	open, done := counts()

	var b strings.Builder
	b.WriteString("# Shared To-Do Board\n\n")
	b.WriteString(strconv.Itoa(open) + " open · ")
	b.WriteString(strconv.Itoa(done) + " done · ")
	b.WriteString(strconv.Itoa(open+done) + " total\n\n")

	if open+done == 0 {
		b.WriteString("_No items yet. Add one with `Add(text)`._\n")
		return b.String()
	}

	// Collect in ascending id order, then emit newest first.
	var lines []string
	items.Iterate("", "", func(_ string, v interface{}) bool {
		it := v.(*item)
		mark := " "
		if it.done {
			mark = "x"
		}
		line := "- [" + mark + "] #" + strconv.Itoa(it.id) + " " +
			it.text + " (" + shortAddr(it.author) + ")"
		lines = append(lines, line)
		return false
	})

	for i := len(lines) - 1; i >= 0; i-- {
		b.WriteString(lines[i])
		b.WriteString("\n")
	}

	return b.String()
}
