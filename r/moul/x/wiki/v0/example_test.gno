package wiki

import "strings"

// ExampleRender shows what an article looks like once the library has
// rewritten its wikilinks and hoisted its categories into the footer.
//
// It prints only the structural lines: the header carries a timestamp and the
// footer a byte count, and neither is stable across the package's other tests.
// The full output is pinned by TestRenderRoutes and by the library's own
// render tests.
func ExampleRender() {
	for _, line := range strings.Split(Render("Tendermint2"), "\n") {
		switch {
		case strings.HasPrefix(line, "# "),
			strings.HasPrefix(line, "**Categories:**"),
			strings.HasPrefix(line, "Tendermint2 is"):
			print(line + "\n")
		}
	}
	// Output:
	// # Tendermint2
	// Tendermint2 is the consensus engine under [Gno land](/r/moul/x/wiki/v0:Gno_land).
	// **Categories:** [Chains](/r/moul/x/wiki/v0:Category:Chains)
}
