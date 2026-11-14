package govgrant

import (
	"strconv"

	"gno.land/p/moul/grants/v1"
)

// untrusted-render: every caller string is escaped once, inside p/moul/grants/v1's Renderer, pinned by TestEveryCallerSuppliedStringIsEscaped there

// The page is these strings plus the library's Renderer. The governance note
// is built per call because the cap, the pause and the sweeps change.
const (
	intro = "A grant board funded by GovDAO. GovDAO sends the treasury money once; the\n" +
		"members below decide grants out of it, in the open, and every tranche leaves\n" +
		"only on a majority of them. A grant is not a GovDAO proposal: the board is.\n" +
		"Anyone may apply, or apply for someone whose account is empty."

	forothers = "**You can ask for someone else.** `ApplyFor` takes the address the money goes\n" +
		"to and a reason for the detour, and prints both on the request. An account with\n" +
		"nothing in it cannot pay the gas to ask for its first coins, so someone else\n" +
		"filing is how most first grants arrive. Either address may submit the proofs,\n" +
		"and neither may vote on the request."

	footer = "Built on [p/moul/grants/v1](/p/moul/grants/v1), which holds every rule, every\n" +
		"tally and this page's markdown, and has no idea coins exist."
)

// governance says who holds the levers and where they are set right now.
func governance() string {
	capLine := "There is no cap on a request."
	if program.Cap > 0 {
		capLine = "One request may ask for at most " + strconv.FormatInt(program.Cap, 10) + " " + Denom + " in total."
	}
	s := "**GovDAO governs this board.** It seats the members, sets the cap, can pause\n" +
		"payouts and can take money back, each by a proposal its members vote on. The\n" +
		"members cannot change any of that themselves, and this realm's code cannot be\n" +
		"replaced. " + capLine
	if program.Paused {
		s += " **Payouts are paused by GovDAO**: requests and ballots still go on the record,\n" +
			"no tranche is released until it resumes them."
	}
	if n := program.Swept(); n > 0 {
		s += " GovDAO has taken " + strconv.FormatInt(n, 10) + " " + Denom + " back out."
	}
	return s
}

// Render serves the board at "", one request at "request/<id>", and the money
// trail at "ledger".
func Render(path string) string {
	return grants.Renderer{
		Program:  program,
		Title:    "GovDAO grant board",
		Intro:    intro,
		Notes:    []string{governance(), forothers},
		Path:     Path,
		Link:     Link,
		Treasury: Address(),
		Balance:  Balance(),
		Footer:   footer,
	}.Render(path)
}
