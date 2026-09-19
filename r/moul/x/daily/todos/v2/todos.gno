// Package todos is a shared, on-chain to-do board realm.
//
// Anyone can add an item; the caller's address is recorded as the author.
// Items can be toggled (open/done) or removed. Render exposes the board as
// Markdown checkboxes with open/done counts, newest item first.
package todos

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/kit/store/v0"
)

// item is one entry on the board. `address` is the uverse bech32 type — it is
// persistable (unlike a `realm` value), so it is safe to store across txs.
// It carries no id field: the id belongs to the store, which hands it back on
// lookup and iteration.
type item struct {
	text   string
	done   bool
	author address
}

// items assigns the item ids. v1 kept its own nextID plus an idKey() that
// zero-padded to width 12, which stopped ordering Render past 10^12.
var items = store.Named("todos: item")

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

	return int(items.Add(&item{
		text:   text,
		done:   false,
		author: author,
	}))
}

// Toggle flips the done state of the item with the given id.
func Toggle(cur realm, id int) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	it := items.MustGet(store.ID(id)).(*item)
	it.done = !it.done
}

// Remove deletes the item with the given id.
func Remove(cur realm, id int) {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	if _, removed := items.Remove(store.ID(id)); !removed {
		panic("todos: item #" + strconv.Itoa(id) + " not found")
	}
}

// counts returns the number of open and done items.
func counts() (open, done int) {
	items.Each(func(_ store.ID, v any) {
		if v.(*item).done {
			done++
		} else {
			open++
		}
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

	// The store iterates by id, so newest-first is one call rather than a
	// collect-then-walk-backwards.
	items.EachReverse(func(id store.ID, v any) {
		it := v.(*item)
		mark := " "
		if it.done {
			mark = "x"
		}
		b.WriteString("- [" + mark + "] #" + id.String() + " " +
			it.text + " (" + ui.Addr(it.author) + ")\n")
	})

	return b.String()
}
