package grants

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	erin  = testutils.TestAddress("erin")  // applicant, mid-delivery
	frank = testutils.TestAddress("frank") // donor
	grace = testutils.TestAddress("grace") // beneficiary of a request she did not file
)

// demo drives a program through every state the renderer has to show: a
// membership change that executed, a donation, a grant carried over one
// dissent, a milestone released and paid, a proof the board refused, a second
// attempt still under review, and a request turned down flat.
//
// It uses the library's own API only, so if a rule changes under it the
// pinned pages below move and the diff says exactly what changed.
func demo() *Program {
	p := NewProgram("ugnot", alice, bob, carol)
	p.Fund(frank, 3000, 100)

	m, _ := p.Board.SubmitMemberChange(alice, dave, true,
		"Reviewed six of the last eight applications from the outside. Give them the seat.", 100)
	p.Board.Vote(alice, m.ID, true, "Proposed it.", 101)
	p.Board.Vote(bob, m.ID, true, "No objection.", 102)

	g, _ := p.Apply(erin, "Port the p/nt/avl benchmarks to gno",
		"Three weeks. A benchmark harness, a report on the tree rebalancing costs, "+
			"and a PR against the monorepo.",
		"harness merged:1200,report published:800", 110)
	p.Board.Vote(alice, g.ID, true, "Cheap for what it tells us.", 111)
	p.Board.Vote(bob, g.ID, false, "The second milestone is vague.", 112)
	p.Board.Vote(carol, g.ID, true, "Vague but bounded. Worth it.", 113)
	p.Board.Vote(dave, g.ID, true, "Agreed with carol.", 114)

	p.Board.SubmitProof(erin, g.ID, 0, Proof{
		Kind: "url", Ref: "https://github.com/gnolang/gno/pull/9999",
		Note: "Harness merged, 14 benchmarks, runs in CI.", Height: 120,
	})
	p.Review(alice, g.ID, 0, true, "Merged, I reviewed it.", 121, 3000)
	p.Review(carol, g.ID, 0, true, "Confirmed.", 122, 3000)
	p.Review(dave, g.ID, 0, true, "Confirmed.", 123, 3000)

	p.Board.SubmitProof(erin, g.ID, 1, Proof{Kind: "text", Ref: "it is basically done", Height: 130})
	p.Review(alice, g.ID, 1, false, "That is not a report.", 131, 1800)
	p.Review(bob, g.ID, 1, false, "Agreed, no numbers.", 132, 1800)
	p.Review(carol, g.ID, 1, false, "Same.", 133, 1800)

	p.Board.SubmitProof(erin, g.ID, 1, Proof{
		Kind: "url", Ref: "https://example.com/avl-rebalancing-costs",
		Note: "Rewritten with the measurements.", Height: 140,
	})
	p.Review(alice, g.ID, 1, true, "Much better.", 141, 1800)

	o, _ := p.ApplyFor(erin, grace, "Her account is empty, so she cannot pay the gas to file this herself.",
		"Translate the onboarding guide to Portuguese",
		"One pass over the eight pages, reviewed by a second speaker.",
		"translation merged:600", 145)
	p.Board.Vote(alice, o.ID, true, "Cheap, and we have no pt-BR page at all.", 146)
	p.Board.Vote(bob, o.ID, true, "Fine.", 147)
	p.Board.Vote(carol, o.ID, true, "Fine.", 148)

	n, _ := p.Apply(mallory, "Rewrite gnoweb in a different framework",
		"Six months, one person, no migration plan.", "the rewrite:250000", 150)
	p.Board.Vote(alice, n.ID, false, "No migration plan and no second maintainer.", 151)
	p.Board.Vote(bob, n.ID, false, "Out of scope for this board.", 152)
	p.Board.Vote(carol, n.ID, false, "Same.", 153)
	return p
}

// view wraps demo in a Renderer configured the way a realm would. Balance is
// 3000 donated minus the 1200 tranche already paid.
func view() Renderer {
	return Renderer{
		Program:  demo(),
		Title:    "Example grant board",
		Intro:    "Anyone may ask this board for money.",
		Path:     "gno.land/r/example/board/v0",
		Link:     "/r/example/board/v0",
		Treasury: testutils.TestAddress("treasury"),
		Balance:  1800,
		Footer:   "Built on [p/moul/grants/v0](/p/moul/grants/v0).",
	}
}

func TestDemoReachedEveryStateTheseExamplesPin(t *testing.T) {
	p := demo()
	uassert.Equal(t, 4, p.Board.MemberCount(), "the membership change executed")
	uassert.Equal(t, 4, p.Board.Size())
	uassert.Equal(t, "completed", p.Board.Get(1).Status.String())
	uassert.Equal(t, "approved", p.Board.Get(2).Status.String())
	uassert.Equal(t, "approved", p.Board.Get(3).Status.String())
	uassert.Equal(t, "rejected", p.Board.Get(4).Status.String())

	o := p.Board.Get(3)
	uassert.True(t, o.OnBehalf(), "request 3 is filed by erin for grace")
	uassert.Equal(t, grace.String(), o.Payee().String())

	g := p.Board.Get(2)
	uassert.True(t, g.Milestones[0].Released, "one tranche paid")
	uassert.Equal(t, int64(1200), p.Disbursed())
	uassert.Equal(t, int64(1400), p.Committed(), "800 still owed on 2, 600 on 3")
	uassert.Equal(t, int64(3000), p.Raised())
	uassert.Equal(t, 1, len(p.Payments))
	uassert.Equal(t, 2, len(g.Milestones[1].Attempts), "one refused, one in flight")
	uassert.Equal(t, "refused", g.Milestones[1].Attempts[0].Outcome.String())
	uassert.Equal(t, "under review", g.Milestones[1].Attempts[1].Outcome.String())
}

// Deliberately over an EMPTY program: the routing is what is under test, and
// rendering the full demo four times costs seconds of VM time for nothing.
func TestRenderUnknownPaths(t *testing.T) {
	v := Renderer{Program: NewProgram("ugnot", alice), Title: "Example grant board", Link: "/r/x/v0"}
	uassert.Equal(t, "# Example grant board\n\nThere is no request 99.\n", v.Render("request/99"))
	uassert.Equal(t, "# Example grant board\n\n`abc` is not a request number.\n", v.Render("request/abc"))
	uassert.True(t, len(v.Render("nope")) > 0)
	uassert.Equal(t, v.Render(""), v.Render("/"), "the root is the root either way")
}

// ExampleRendererIndex pins the board page.
func ExampleRendererIndex() {
	print(view().Render(""))
	// Output:
	// # Example grant board
	//
	// Anyone may ask this board for money.
	//
	// ## Treasury
	//
	// | Field | Value |
	// |---|---|
	// | Address | `g1w3ex2ctnw4e8jh6lta047h6lta047h6llhugks` |
	// | Balance | 1800 ugnot |
	// | Promised | 1400 ugnot |
	// | Unpromised | 400 ugnot |
	// | Donated | 3000 ugnot |
	// | Paid out | 1200 ugnot |
	//
	// ## Board
	//
	// A decision needs a majority of the members eligible to cast a ballot on it,
	// recomputed every time: the party a decision is about never votes on it, so an
	// applicant who sits on the board shrinks the room rather than packing it.
	//
	// | Member | Joined at height |
	// |---|---|
	// | `g1v3shve2lta047h6lta047h6lta047h6lel7d9l` | 102 |
	// | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` | 0 |
	// | `g1vdshymmvta047h6lta047h6lta047h6l2asz94` | 0 |
	// | `g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu` | 0 |
	//
	// ## Requests
	//
	// | # | Kind | Title | For | Asking | Status | Ballots |
	// |---|---|---|---|---|---|---|
	// | [1](/r/example/board/v0:request/1) | membership | Add g1v3shve2lta047h6lta047h6lta047h6lel7d9l | - | nothing | completed | 2 for, 0 against |
	// | [2](/r/example/board/v0:request/2) | grant | Port the p/nt/avl benchmarks to gno | `g1v4exjm…sj8d` | 2000 ugnot | approved | 3 for, 1 against |
	// | [3](/r/example/board/v0:request/3) | grant | Translate the onboarding guide to Portuguese | `g1vaexzc…qsw9` (filed by g1v4exjm…sj8d) | 600 ugnot | approved | 3 for, 0 against |
	// | [4](/r/example/board/v0:request/4) | grant | Rewrite gnoweb in a different framework | `g1d4skcm…cwc9` | 250000 ugnot | rejected | 0 for, 3 against |
	//
	// ## Where the money went
	//
	// [The ledger](/r/example/board/v0:ledger) lists every donation in and every tranche
	// out, with the height, the payee and the milestone it paid for.
	//
	// ## Calling it
	//
	// ```sh
	// # put money in
	// gnokey maketx call -pkgpath gno.land/r/example/board/v0 -func Fund -send 5000000ugnot ...
	// # ask for some
	// gnokey maketx call -pkgpath gno.land/r/example/board/v0 -func Apply \
	//   -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' ...
	// # ask on behalf of someone who cannot pay the gas to ask
	// gnokey maketx call -pkgpath gno.land/r/example/board/v0 -func ApplyFor \
	//   -args g1... -args 'their account is empty' \
	//   -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' ...
	// # decide (members only)
	// gnokey maketx call -pkgpath gno.land/r/example/board/v0 -func Vote -args 1 -args true -args 'reason' ...
	// # show your work, then get paid for it
	// gnokey maketx call -pkgpath gno.land/r/example/board/v0 -func SubmitProof \
	//   -args 1 -args 0 -args url -args 'https://...' -args 'what it is' ...
	// gnokey maketx call -pkgpath gno.land/r/example/board/v0 -func Review -args 1 -args 0 -args true -args 'looks done' ...
	// ```
	//
	// Built on [p/moul/grants/v0](/p/moul/grants/v0).
}

// ExampleRendererRequest pins the richest page: a grant mid-delivery with one
// tranche paid, a refused proof kept on the record, and a second attempt
// still being reviewed.
func ExampleRendererRequest() {
	print(view().Render("request/2"))
	// Output:
	// # Request 2: Port the p/nt/avl benchmarks to gno
	//
	// | Field | Value |
	// |---|---|
	// | Kind | grant |
	// | Applicant | `g1v4exjmjlta047h6lta047h6lta047h6lv8sj8d` |
	// | Status | approved |
	// | Filed at height | 110 |
	// | Decided at height | 114 |
	// | Asking | 2000 ugnot |
	// | Paid so far | 1200 ugnot |
	// | Still owed | 800 ugnot |
	//
	// ## The ask
	//
	//
	//
	// Three weeks. A benchmark harness, a report on the tree rebalancing costs, and a PR against the monorepo.
	//
	//
	//
	// ## Ballots
	//
	// Needs 3 of 4 eligible members. Standing: 3 for, 1 against.
	//
	// | Member | Vote | Height | Reason |
	// |---|---|---|---|
	// | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` | for | 111 | Cheap for what it tells us\. |
	// | `g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu` | against | 112 | The second milestone is vague\. |
	// | `g1vdshymmvta047h6lta047h6lta047h6l2asz94` | for | 113 | Vague but bounded\. Worth it\. |
	// | `g1v3shve2lta047h6lta047h6lta047h6lel7d9l` | for | 114 | Agreed with carol\. |
	//
	// ## Milestones
	//
	// Earned in order. The applicant submits a proof, the board reviews that proof,
	// and the verdict that carries also moves the coins.
	//
	// ### 1. harness merged: 1200 ugnot
	//
	// Released at height 123, paid to `g1v4exjmjlta047h6lta047h6lta047h6lv8sj8d`.
	//
	// **Proof 1** (url, height 120, accepted)
	//
	// ```
	// https://github.com/gnolang/gno/pull/9999
	// ```
	//
	//
	//
	// Harness merged, 14 benchmarks, runs in CI.
	//
	//
	//
	// | Member | Vote | Height | Reason |
	// |---|---|---|---|
	// | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` | accept | 121 | Merged, I reviewed it\. |
	// | `g1vdshymmvta047h6lta047h6lta047h6l2asz94` | accept | 122 | Confirmed\. |
	// | `g1v3shve2lta047h6lta047h6lta047h6lel7d9l` | accept | 123 | Confirmed\. |
	//
	// ### 2. report published: 800 ugnot
	//
	// A proof is under review.
	//
	// **Proof 1** (text, height 130, refused)
	//
	// ```
	// it is basically done
	// ```
	//
	// | Member | Vote | Height | Reason |
	// |---|---|---|---|
	// | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` | refuse | 131 | That is not a report\. |
	// | `g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu` | refuse | 132 | Agreed, no numbers\. |
	// | `g1vdshymmvta047h6lta047h6lta047h6l2asz94` | refuse | 133 | Same\. |
	//
	// **Proof 2** (url, height 140, under review)
	//
	// ```
	// https://example.com/avl-rebalancing-costs
	// ```
	//
	//
	//
	// Rewritten with the measurements.
	//
	//
	//
	// | Member | Vote | Height | Reason |
	// |---|---|---|---|
	// | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` | accept | 141 | Much better\. |
}

// ExampleRendererMembership pins a membership request, which asks for no
// money and therefore renders no milestones.
func ExampleRendererMembership() {
	print(view().Render("request/1"))
	// Output:
	// # Request 1: Add g1v3shve2lta047h6lta047h6lta047h6lel7d9l
	//
	// | Field | Value |
	// |---|---|
	// | Kind | membership |
	// | Applicant | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` |
	// | Subject | `g1v3shve2lta047h6lta047h6lta047h6lel7d9l` |
	// | Effect | add to the board |
	// | Status | completed |
	// | Filed at height | 100 |
	// | Decided at height | 102 |
	//
	// ## The ask
	//
	//
	//
	// Reviewed six of the last eight applications from the outside. Give them the seat.
	//
	//
	//
	// ## Ballots
	//
	// Needs 2 of 3 eligible members. Standing: 2 for, 0 against.
	//
	// | Member | Vote | Height | Reason |
	// |---|---|---|---|
	// | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` | for | 101 | Proposed it\. |
	// | `g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu` | for | 102 | No objection\. |
}

// ExampleRendererLedger pins the money trail.
func ExampleRendererLedger() {
	print(view().Render("ledger"))
	// Output:
	// # Example grant board: the ledger
	//
	// Every coin in and every coin out, in the order it happened. Coins sent
	// straight to `g1w3ex2ctnw4e8jh6lta047h6lta047h6llhugks` land in the treasury
	// without appearing here, which is why `Fund` exists: it is the same transfer
	// with a name attached.
	//
	// ## In
	//
	// | Height | From | Amount |
	// |---|---|---|
	// | 100 | `g1veexzmntta047h6lta047h6lta047h6lthxxu5` | 3000 ugnot |
	//
	// Total in: 3000 ugnot
	//
	// ## Out
	//
	// | Height | Request | Milestone | To | Amount |
	// |---|---|---|---|---|
	// | 123 | [2](/r/example/board/v0:request/2) | 1 | `g1v4exjmjlta047h6lta047h6lta047h6lv8sj8d` | 1200 ugnot |
	//
	// Total out: 1200 ugnot
	//
	// Balance now: 1800 ugnot. [Back to the board](/r/example/board/v0).
}

// ExampleRendererOnBehalf pins a request one address filed for another: the
// beneficiary row, the callout carrying the applicant's reason, and the "For"
// column that says on the board page who the money would reach.
func ExampleRendererOnBehalf() {
	print(view().Render("request/3"))
	// Output:
	// # Request 3: Translate the onboarding guide to Portuguese
	//
	// | Field | Value |
	// |---|---|
	// | Kind | grant |
	// | Applicant | `g1v4exjmjlta047h6lta047h6lta047h6lv8sj8d` |
	// | Beneficiary | `g1vaexzcm9ta047h6lta047h6lta047h6lr5qsw9` |
	// | Status | approved |
	// | Filed at height | 145 |
	// | Decided at height | 148 |
	// | Asking | 600 ugnot |
	// | Paid so far | 0 ugnot |
	// | Still owed | 600 ugnot |
	//
	// ## Filed for someone else
	//
	// The applicant is not the payee: every tranche of this request pays
	// `g1vaexzcm9ta047h6lta047h6lta047h6lr5qsw9`. Both addresses are barred from voting on it, and
	// either may submit a proof. The reason given:
	//
	// > Her account is empty, so she cannot pay the gas to file this herself\.
	//
	// Nothing checks that reason. It is a claim by the applicant, and the point of
	// printing it here is that a member can check it before voting.
	//
	// ## The ask
	//
	// One pass over the eight pages, reviewed by a second speaker.
	//
	// ## Ballots
	//
	// Needs 3 of 4 eligible members. Standing: 3 for, 0 against.
	//
	// | Member | Vote | Height | Reason |
	// |---|---|---|---|
	// | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` | for | 146 | Cheap, and we have no pt\-BR page at all\. |
	// | `g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu` | for | 147 | Fine\. |
	// | `g1vdshymmvta047h6lta047h6lta047h6l2asz94` | for | 148 | Fine\. |
	//
	// ## Milestones
	//
	// Earned in order. The applicant submits a proof, the board reviews that proof,
	// and the verdict that carries also moves the coins.
	//
	// ### 1. translation merged: 600 ugnot
	//
	// Waiting on a proof from the applicant.
}

// injected is every dangerous markdown sequence a caller can type, in one
// string, so a slot that forgets to escape shows up as a live link or a
// gnoweb tag in the assertions below rather than on a deployed page.
const injected = "[click](https://evil.example) ![x](https://evil.example/p.png) " +
	"<gno-columns> | fake | cell | ```\nsecond line\n"

// injectedShort is the same attack inside the 100-character limit a title and
// a milestone name are held to.
const injectedShort = "[click](https://evil.example) <gno-columns>|x|\nnext"

// TestEveryCallerSuppliedStringIsEscaped drives one board through every slot
// a caller controls and asserts that none of them can reshape the page.
//
// The bar is not the same in every slot, on purpose. A one-line slot (a
// title, a milestone name, the reason on a ballot, the reason for filing on
// someone else's behalf) is chrome the page lays out, so nothing a caller
// typed may survive as markup there. A prose slot (the body of an
// application, the note on a proof) goes through sanitize.Block, which
// PRESERVES inline links and emphasis by design: a grant application whose
// link to the merged PR renders as literal text is a worse page, and the
// sanitizer's own contract is that prose formats. What Block still kills is
// everything structural, so the paragraph cannot leave its paragraph.
//
// Assertions are on the dangerous SEQUENCE, never on the exact escaped bytes:
// those belong to the sanitizer, they change when it changes, and a test that
// pins them fails for the wrong reason.
func TestEveryCallerSuppliedStringIsEscaped(t *testing.T) {
	p := NewProgram("ugnot", alice, bob)
	r, err := p.ApplyFor(erin, grace, injected, injectedShort, injected, injectedShort+":100", 10)
	urequire.NoError(t, err)
	p.Board.Vote(alice, r.ID, true, injected, 11)
	p.Board.Vote(bob, r.ID, true, injected, 12)
	urequire.NoError(t, p.Board.SubmitProof(erin, r.ID, 0, Proof{
		Kind: "url", Ref: injected, Note: injected, Height: 13,
	}))
	p.Board.Review(alice, r.ID, 0, false, injected, 14)

	v := Renderer{Program: p, Title: "Board", Path: "gno.land/r/x/v0", Link: "/r/x/v0", Balance: 0}

	// Every structural line of every page: a table row, a heading, a
	// blockquote. Nothing a caller typed may render as markup in one.
	for _, page := range []string{"", "request/1", "ledger"} {
		for _, line := range strings.Split(v.Render(page), "\n") {
			if !strings.HasPrefix(line, "|") && !strings.HasPrefix(line, "#") &&
				!strings.HasPrefix(line, ">") {
				continue
			}
			for _, dead := range []string{"](http", "![", "<gno-"} {
				uassert.False(t, strings.Contains(line, dead),
					"page "+page+" line still carries "+dead+": "+line)
			}
		}
	}

	// A table row keeps exactly its own cells: an unescaped pipe would open a
	// column and an unescaped newline would end the row early, and both
	// reshape the table silently rather than failing.
	for _, line := range strings.Split(v.Render("request/1"), "\n") {
		if !strings.HasPrefix(line, "| `"+alice.String()+"`") {
			continue
		}
		uassert.Equal(t, 5, strings.Count(line, "|")-strings.Count(line, "\\|"),
			"the ballot row kept its four cells: "+line)
	}

	// An escaper that ate the content would pass every assertion above.
	out := v.Render("request/1")
	uassert.True(t, strings.Contains(out, "click"), "the readable text survived")
	uassert.True(t, strings.Contains(out, "second line"), "the second line survived")

	// The structural attack is dead in the prose slots too, even though the
	// link in them is deliberately alive.
	body := out[strings.Index(out, "## The ask"):strings.Index(out, "## Ballots")]
	uassert.False(t, strings.Contains(body, "\n<gno-"), "no gnoweb tag at a line start")
	uassert.False(t, strings.Contains(body, "\n| "), "prose cannot open a table")
	uassert.False(t, strings.Contains(body, "\n#"), "prose cannot forge a heading")
}
