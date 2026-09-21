package reaper

import "strings"

// ExampleRender pins the page's skeleton: the title, the two sections that are
// always present, and the footer crediting the two packages that own the parts
// this realm does not.
//
// It deliberately prints only the invariant lines. Everything interesting on
// the page is priced from the current block height and the notes outstanding,
// and an Example runs after every Test in the package and sees whatever state
// they left. The variable half is pinned by TestRenderShowsTheBountyAndTheReapLink
// instead, which controls the board first.
func ExampleRender() {
	for _, line := range strings.Split(Render(""), "\n") {
		switch {
		case strings.HasPrefix(line, "# "),
			strings.HasPrefix(line, "## "),
			strings.HasPrefix(line, "A noticeboard"),
			strings.HasPrefix(line, "The arithmetic is"):
			print(line + "\n")
		}
	}
	// Output:
	// # Reaper
	// A noticeboard whose garbage is a standing bounty. Posting a note locks a storage deposit. Once the note expires, anyone can delete it and the chain refunds that deposit **to whoever signs the deleting transaction**.
	// ## On the table right now
	// ## Board
	// The arithmetic is [p/moul/x/storagecost](/p/moul/x/storagecost/v0); the storage is [p/moul/ulist](/p/moul/ulist/v1), whose `Compact` reclaims dead nodes without moving a live index. Byte figures on this page are estimates from payload length: no stdlib call exposes a realm's real locked storage.
}
