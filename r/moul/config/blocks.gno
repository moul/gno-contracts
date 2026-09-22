package config

import "strings"

// The notice blocks: two strings a realm drops at the top and the bottom of its
// Render, empty by default, so moul can put a warning, a changelog line or a
// bit of news on every realm at once or on one of them.
//
//	func Render(path string) string {
//		return config.TopBlock() + body + config.BottomBlock()
//	}
//
// Both are set with the ordinary Set, which is what keeps this realm's surface
// from growing a function per idea:
//
//	Set block.top            "> Chain migration on Tuesday."   # every realm
//	Set block.top@r/moul/gns "> v2 shipped, see the changelog" # this one only
const (
	// KeyBlockTop is the notice rendered above a realm's content.
	KeyBlockTop = "block.top"
	// KeyBlockBottom is the notice rendered below it.
	KeyBlockBottom = "block.bottom"
)

// TopBlock returns the notice for the realm calling in, ready to concatenate
// in front of its content. Empty when there is nothing to say, which is the
// default and the usual case.
//
// Three things can appear, in this order, separated by blank lines:
//
//  1. the pause banner, when this realm or every realm is paused
//  2. the global block.top
//  3. this realm's own block.top
//
// The pause banner comes first because it is the one a reader has to see, and
// it is included here rather than left to the realm so that guarding writes
// with AssertWritable is enough to also explain the refusal on the page.
//
// Global and scoped are BOTH shown rather than one overriding the other: a
// chain-wide warning and a per-realm changelog are different messages, and
// dropping either because the other exists is the surprising behaviour.
func TopBlock() string { return TopBlockFor(caller()) }

// TopBlockFor is TopBlock for a named realm. Use it from a crossing function,
// where the caller cannot be read off the stack, or to render another realm's
// notice.
func TopBlockFor(pkgPath string) string {
	global, scoped := scopedPair(KeyBlockTop, pkgPath)
	return joinBlocks(PauseFor(pkgPath).Notice(), global, scoped)
}

// BottomBlock returns the notice for the realm calling in, ready to
// concatenate after its content.
//
// No pause banner here: one is enough, and the top is where it is read.
func BottomBlock() string { return BottomBlockFor(caller()) }

// BottomBlockFor is BottomBlock for a named realm.
func BottomBlockFor(pkgPath string) string {
	global, scoped := scopedPair(KeyBlockBottom, pkgPath)
	return joinBlocks(global, scoped)
}

// joinBlocks assembles the non-empty parts into one markdown fragment.
//
// Each part is separated by a blank line, because two markdown blocks with
// only a newline between them are one paragraph, and a blockquote followed
// directly by text swallows the text into the quote.
//
// The result ends with a blank line when there is anything at all, so a realm
// can write config.TopBlock() + body without a separator of its own and get
// the same output whether or not a notice is set. Nothing to say means the
// empty string, and the page is byte-for-byte what it was before.
func joinBlocks(parts ...string) string {
	var kept []string
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			kept = append(kept, p)
		}
	}
	if len(kept) == 0 {
		return ""
	}
	return strings.Join(kept, "\n\n") + "\n\n"
}
