package compact

import "strings"

// ExampleRender pins the page's skeleton: the title and the three sections
// that are always there, whatever the board holds.
//
// Only the invariant lines, on purpose. Everything else on the page is
// derived from the current fragmentation, and an Example runs after every
// Test in the package and sees whatever state they left. The variable half is
// pinned by TestRenderShowsBothIntegersAndTheAction, which controls the board
// first.
func ExampleRender() {
	for _, line := range strings.Split(Render(""), "\n") {
		switch {
		case strings.HasPrefix(line, "# "),
			strings.HasPrefix(line, "## "),
			strings.HasPrefix(line, "Soft-deleting"):
			print(line + "\n")
		}
	}
	// Output:
	// # Compact
	// Soft-deleting an entry frees nothing: the tree node stays, the bytes stay locked, and every read still walks past the hole. Compacting drops those nodes and the chain refunds their deposit **to whoever signs the transaction**. The only question is when.
	// ## The two integers
	// ## Why allocated minus live is not the answer
	// ## Board
}
