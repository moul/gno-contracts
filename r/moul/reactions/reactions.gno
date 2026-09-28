// Package reactions is a reaction block any realm can embed, keyed on the page
// it appears on rather than on the realm that stores it.
//
// It is the shape the web settled on for this in 2010: one hosted widget, the
// same snippet pasted everywhere, deciding what to show from the page
// identifier it is handed. Here the snippet is two lines of gno:
//
//	import "gno.land/r/moul/reactions/v0"
//
//	func Render(path string) string {
//		return body + reactions.RenderBlock()
//	}
//
// [RenderBlock] takes no argument because it does not need one: a plain read
// exported by a realm and called by another opens no realm frame, so
// unsafe.CurrentRealm() inside it reports the CALLER. The host realm's own path
// is the page key, and nothing has to be configured, registered or passed.
// [RenderBlockFor] is the explicit form, for a realm that renders more than one
// page or already holds its path as a constant.
//
// The host realm stores nothing. Every tally lives here, so a realm can add
// reactions without a redeploy the next time it wants to change them, and a
// reader's reaction survives the host realm being replaced.
//
// # What it is not
//
// Not a comment system. There is no text field anywhere, which is what makes
// it possible to run with no moderation at all: six emoji, one reaction per
// address per page, changeable and removable. The page shows the tally and who
// reacted last. That is the whole feature.
package reactions

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	rx "gno.land/p/moul/reactions/v0"
)

// realmPath is this realm's own path, the one its gnomod.toml module line
// declares. It is written out rather than read from unsafe.CurrentRealm(),
// which reports the CALLER in every read this realm exports and would therefore
// build every link against whichever realm embedded the block.
const realmPath = "gno.land/r/moul/reactions/v0"

// board holds every page's tally.
//
// A redeploy would wipe it, which is why this realm is not private (see
// gnomod.toml): the state here belongs to everyone who reacted, and the only
// honest way to change this realm is a v1 beside it.
var board = rx.NewBoard()

// React records the caller's reaction to page.
//
// page is a package path, the full one: "gno.land/r/moul/home". It does not
// have to be a realm that embeds the block, and nothing checks that it exists.
// A page is just a name, which is what lets a realm key the block on something
// finer than itself.
//
// key is one of the palette names, not a glyph: "up", "heart", "fire", "party",
// "rocket", "eyes". Render("") lists them with their emoji.
//
// One reaction per address per page. Reacting again with a different key moves
// it; reacting with the same key changes nothing but the "last reaction" line.
func React(cur realm, page, key string) {
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	if !rx.Valid(key) {
		panic("reactions: no such reaction: " + key)
	}
	if !rx.ValidPage(page) {
		panic("reactions: not a page key: " + page)
	}

	who := unsafe.PreviousRealm().Address()
	board.React(page, who, key, runtime.ChainHeight())
	chain.Emit("React", "page", page, "key", key, "who", who.String())
}

// Unreact removes the caller's reaction from page. It aborts when there is
// none, rather than succeeding silently, so a misspelled page key is visible
// instead of looking like a no-op.
func Unreact(cur realm, page string) {
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	who := unsafe.PreviousRealm().Address()
	if !board.Unreact(page, who) {
		panic("reactions: nothing to remove on " + page)
	}
	chain.Emit("Unreact", "page", page, "who", who.String())
}

// RenderBlock returns the block for the realm CALLING it, which is the form a
// host realm embeds.
//
// It has no cur realm parameter on purpose. A plain read is borrowed: gno opens
// no realm frame for it, so unsafe.CurrentRealm() reports the caller's path and
// the block keys itself with no argument. Adding a cur realm here would
// silently reverse that and key every embed to this realm instead.
//
// Calling it from inside this realm therefore keys on this realm, which is
// never what a caller wants; the views below use the unexported blockFor.
func RenderBlock() string {
	return blockFor(unsafe.CurrentRealm().PkgPath())
}

// RenderBlockFor is [RenderBlock] for a named page. Use it from a crossing
// function, where there is no caller to read off the stack, or when one realm
// renders several pages.
func RenderBlockFor(page string) string { return blockFor(page) }

// blockFor is the shared body, so no exported read of this realm calls another
// and picks up the wrong path.
func blockFor(page string) string {
	return rx.Block(realmPath, page, board.Page(page))
}

// Count reports how many addresses have a reaction on page.
func Count(page string) int { return board.Page(page).Total() }

// CountOf reports how many addresses hold one particular reaction on page.
func CountOf(page, key string) int { return board.Page(page).Count(key) }

// ReactionOf returns who's current reaction key on page, or "" when they have
// none. A host realm can use it to say "you reacted" without reading the tree.
func ReactionOf(page string, who address) string { return board.Page(page).Of(who) }

// Last returns the most recent reaction on page: the palette key, the address,
// and the height. The key is "" when the page has never been reacted to.
func Last(page string) (key string, who address, height int64) {
	return board.Page(page).Last()
}

// Pages reports how many pages have ever been reacted to.
func Pages() int { return board.Pages() }
