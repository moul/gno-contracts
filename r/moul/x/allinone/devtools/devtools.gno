// Package devtools is the worked example of wiring moul's developer packages
// into one realm: what a new realm should copy.
//
// Everything here is a COMBINATION. Any one of these packages has its own demo
// showing it alone; the thing that is hard to find is what they look like used
// together, which is the only form a real realm ever meets them in. So this
// realm imports eight of them and every one earns its place in the output:
//
//	r/moul/config     the notice block, the pause switch, the explorer to link
//	p/moul/mygnoscan  the explorer routes themselves
//	p/moul/debug      a metadata panel behind ?debug=1
//	p/moul/realmpath  reading the query string Render was handed
//	p/moul/kit/ui     escaping what a caller typed, and the tables
//	p/moul/md         the markdown, without hand-rolled strings
//	p/moul/txlink     the "call this function" link
//	p/moul/fifo       the bounded note list, so the state cannot grow forever
//
// # The three lines worth copying
//
// A realm that does nothing else should still do these:
//
//	func Render(path string) string {
//		return config.TopBlockFor(realmPath) + body + config.BottomBlockFor(realmPath)
//	}
//
//	func Mutate(cur realm, s string) {
//		config.AssertWritableFor(realmPath)  // honours the pause switch
//		notes.Append(ui.Inline(s))           // escapes what a caller typed
//	}
//
// The first gives every realm a place to put a warning and a pause banner
// without shipping banner code. The second is two separate guards that both
// have to be there: the pause one so an incident can stop writes from outside
// the realm, and the escaping one because a string a caller typed is the
// oldest way to break a page.
package devtools

import (
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/moul/debug/v0"
	"gno.land/p/moul/fifo/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/mygnoscan/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/txlink/v0"
	"gno.land/r/moul/config/v1"
)

// realmPath is this realm's own path.
//
// Passed explicitly to config rather than relying on its zero-argument helpers.
// Both work (a plain read is borrowed, so config sees this realm as the
// caller), but a constant cannot be wrong, and spelling it out is what a reader
// copying this file needs to see.
const realmPath = "gno.land/r/moul/x/allinone/devtools/v0"

// maxNotes bounds the guest list. fifo drops the oldest rather than growing,
// because storage on chain is paid for and never refunded: an unbounded list in
// a demo anyone can write to is a bill with no ceiling.
const maxNotes = 10

var notes = fifo.New(maxNotes)

// Add appends a note. It is the only mutating function here, and it carries
// both guards a real one should.
func Add(cur realm, body string) {
	// 1. The pause switch. Set `pause@r/moul/x/allinone/devtools` on
	//    r/moul/config and this aborts, with the reason, from outside this
	//    realm and without a redeploy.
	config.AssertWritableFor(realmPath)

	body = strings.TrimSpace(body)
	if body == "" {
		panic("empty note")
	}
	if len(body) > 200 {
		panic("note too long: max 200 bytes, got " + strconv.Itoa(len(body)))
	}

	// 2. Escaping. body is a string a caller typed, and it is about to land in
	//    a markdown list. ui.Inline is the repo's standard for exactly this.
	notes.Append(ui.Inline(body))
}

// Reset empties the list, so the realm can be put back to a known state
// without a redeploy. Not gated by the pause switch: clearing up is the thing
// you still want to do while paused.
func Reset(cur realm) {
	notes = fifo.New(maxNotes)
}

// Render shows every package at work. The root view is deliberately free of
// anything that moves on its own, so an example test can pin it; the live
// numbers live under "chain".
func Render(path string) string {
	req := realmpath.Parse(path)

	var b strings.Builder
	b.WriteString(config.TopBlockFor(realmPath))
	b.WriteString(md.H1("allinone: devtools"))
	b.WriteString("\nEight packages, used together rather than one at a time. ")
	b.WriteString(md.Link("source", config.MygnoscanFor(realmPath)))
	b.WriteString("\n\n")

	switch req.PathPart(0) {
	case "chain":
		b.WriteString(renderChain())
	default:
		b.WriteString(renderHome(path))
	}

	// debug prints its own panel only when ?debug=1 is set, and the empty
	// string otherwise, so this line is safe to leave in a deployed realm.
	b.WriteString(debug.Render(path))
	b.WriteString(config.BottomBlockFor(realmPath))
	return b.String()
}

func renderHome(path string) string {
	var b strings.Builder

	b.WriteString(md.H2("Notes"))
	b.WriteString("\n")
	// renderNotes returns no trailing newline of its own: md.BulletList and
	// ui.Empty already end in one, and adding a second here produced two
	// consecutive blank lines, which gno collapses inside an // Output: block
	// and which therefore no example test can ever pin.
	b.WriteString(renderNotes())
	b.WriteString("\n")

	// txlink builds the "call this function" URL for the CURRENT realm, so it
	// keeps working after a version bump without anything here changing.
	b.WriteString(md.BulletList([]string{
		md.Link("add a note", txlink.NewLink("Add").AddArgs("body", "hello").URL()),
		md.Link("clear them", txlink.Call("Reset")),
		md.Link("live chain values", "/r/moul/x/allinone/devtools/v0:chain"),
		md.Link("toggle the debug panel", debug.ToggleURL(path)),
	}))
	b.WriteString("\n")

	b.WriteString(md.H2("What each package does here"))
	b.WriteString("\n")
	t := ui.NewTable("package", "what it contributed")
	t.Row("`r/moul/config`", "the notice block above, the pause guard on `Add`, and which explorer to link")
	t.Row("`p/moul/mygnoscan`", "the explorer routes, so a link survives a route change")
	t.Row("`p/moul/debug`", "the `?debug=1` panel, empty otherwise")
	t.Row("`p/moul/realmpath`", "splitting the render path into a view and a query")
	t.Row("`p/moul/kit/ui`", "escaping a caller's note, and this table")
	t.Row("`p/moul/md`", "every heading, link and list on the page")
	t.Row("`p/moul/txlink`", "the call links above, relative to this realm")
	t.Row("`p/moul/fifo`", "the note list, bounded so storage cannot grow forever")
	b.WriteString(t.String())

	return b.String()
}

// renderChain is everything that moves: the height, and the links built from
// it. Kept off the root view so the root can be pinned by an example.
func renderChain() string {
	s := config.Scanner()
	h := runtime.ChainHeight()

	var b strings.Builder
	b.WriteString(md.H2("Live"))
	b.WriteString("\n")

	t := ui.NewTable("what", "value")
	t.Row("chain id", ui.Cell(runtime.ChainID()))
	t.Row("height", strconv.FormatInt(h, 10))
	t.Row("explorer", ui.Cell(s.Base()))
	t.Row("network", ui.Cell(s.Network()))
	b.WriteString(t.String())
	b.WriteString("\n")

	// mygnoscan.Link used directly, rather than through config, to show that
	// the builder is an ordinary value: config only decides where it points.
	b.WriteString(md.BulletList([]string{
		mygnoscan.Link("this block", s.Block(h)),
		mygnoscan.Link("this realm's transactions", s.Realm(realmPath, mygnoscan.TabCalls)),
		mygnoscan.Link("its dependency graph", s.Realm(realmPath, mygnoscan.TabDeps)),
		mygnoscan.Link("the parked deploy queue", s.Packages(mygnoscan.PackagesInert)),
	}))
	b.WriteString("\n")
	b.WriteString(md.Link("back", "/r/moul/x/allinone/devtools/v0"))
	b.WriteString("\n")
	return b.String()
}

func renderNotes() string {
	if notes.Size() == 0 {
		return ui.Empty("no notes yet")
	}
	items := []string{}
	for _, e := range notes.Entries() {
		items = append(items, e.(string))
	}
	return md.BulletList(items)
}
