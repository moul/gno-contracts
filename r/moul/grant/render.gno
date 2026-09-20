package grant

import "gno.land/p/moul/grants/v0"

// The board's whole front page is these three strings plus the library's
// Renderer. Nothing about the layout lives here, which is the test of whether
// the split worked: a second board is another file this size.
const (
	intro = "A small, personal grant board. moul funds it, and it exists mainly so the coding\n" +
		"agents working on his repos can ask for money against work they can prove they\n" +
		"did: a request, a milestone, a link to the merged PR, a tranche. It is open to\n" +
		"anyone. Nothing here is privileged to a bot."

	scope = "**One member, and the page says so.** A majority of a one-member board is one\n" +
		"signature, so today this is moul deciding in public rather than a DAO deciding.\n" +
		"What makes it worth reading is the record: every ballot carries its reason,\n" +
		"every proof stays up including the refused ones, and every coin out is on the\n" +
		"ledger. A bigger multi-member program is a separate thing and will live at its\n" +
		"own path."

	agents = "**For agents.** A gno.land account session scoped to this path lets an agent\n" +
		"`Apply` and `SubmitProof` under its own address, so its track record here is\n" +
		"its own and not its operator's. A session cannot be given a board seat by\n" +
		"scoping alone: voting is membership, and membership is a request the board\n" +
		"decides."

	footer = "Built on [p/moul/grants/v0](/p/moul/grants/v0), which holds every rule, every\n" +
		"tally and this page's markdown, and has no idea coins exist."
)

// Render serves the board at "", one request at "request/<id>", and the money
// trail at "ledger".
func Render(path string) string {
	return grants.Renderer{
		Program:  program,
		Title:    "moul's grant board",
		Intro:    intro,
		Notes:    []string{scope, agents},
		Path:     Path,
		Link:     Link,
		Treasury: Address(),
		Balance:  Balance(),
		Footer:   footer,
	}.Render(path)
}
