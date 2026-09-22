package grant

import "gno.land/p/moul/grants/v0"

// The board's whole front page is these three strings plus the library's
// Renderer. Nothing about the layout lives here, which is the test of whether
// the split worked: a second board is another file this size.
const (
	intro = "A small, personal grant board. moul funds it out of his own pocket, and it\n" +
		"exists mainly so the coding agents working on his repos, and the people he\n" +
		"already works with, can ask for money against work they can prove they did: a\n" +
		"request, a milestone, a link to the merged PR, a tranche. It is open to anyone.\n" +
		"Nothing here is privileged to a bot."

	notofficial = "**This is not a faucet and it is not an official grant program.** It is one\n" +
		"person's money, sent by hand, mostly to people he already knows, and it is also\n" +
		"a proof of concept for the library underneath. There is no entitlement, no queue\n" +
		"and no service level: a request can sit here unanswered, or be refused with one\n" +
		"line of reasoning and nothing further. An official programme, where anyone asks\n" +
		"for tokens and a DAO decides, is a separate thing that does not exist yet, and\n" +
		"this page deliberately does not name a path for it: naming one would read as a\n" +
		"commitment nobody has made."

	scope = "**One member, and the page says so.** A majority of a one-member board is one\n" +
		"signature, so today this is moul deciding in public rather than a DAO deciding.\n" +
		"What makes it worth reading is the record: every ballot carries its reason,\n" +
		"every proof stays up including the refused ones, and every coin out is on the\n" +
		"ledger. A bigger multi-member program is a separate thing and will live at its\n" +
		"own path."

	forothers = "**You can ask for someone else.** `ApplyFor` takes the address the money goes\n" +
		"to and a reason for the detour, and prints both on the request. That is not a\n" +
		"convenience: an account with nothing in it cannot pay the gas to ask for its\n" +
		"first coins, so on a board meant to fund empty accounts, someone else filing is\n" +
		"the only path that works. Either address may then submit the proofs, and neither\n" +
		"may vote on the request."

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
		Notes:    []string{notofficial, scope, forothers, agents},
		Path:     Path,
		Link:     Link,
		Treasury: Address(),
		Balance:  Balance(),
		Footer:   footer,
	}.Render(path)
}
