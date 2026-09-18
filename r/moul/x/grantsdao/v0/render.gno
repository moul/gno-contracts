package grantsdao

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/grants/v0"
)

// link is Path as a gnoweb route.
const link = "/r/moul/x/grantsdao/v0"

// Seeded history. The board is not an empty page at deploy: it has already
// co-opted a fourth member, carried one grant that is mid-delivery, and
// turned another down. No coins moved for any of it (a seed can write votes
// and proofs, it cannot mint a treasury), so the ledger starts empty and the
// seeded grant shows up on the front page as a promise the board has not yet
// been funded to keep. Funding it is the demo.
const (
	// These three are placeholders, derived the way p/nt/testutils derives a
	// test address: readable bytes, valid checksum, and NO key behind them.
	// Nobody can sign as them, so the seeded grant can never be finished by
	// its applicant, and a member who accepted its proof on a funded board
	// would be sending coins nowhere. Render says so on the request page.
	seedMember    = address("g1vaexzmn5wvkk6etdvfjhytf5ta047h6lyrpr58") // "grants-member-4"
	seedApplicant = address("g1vaexzmn5wvkkzursd35kxctww3047h6lhfh8j5") // "grants-applicant"
	seedRejected  = address("g1vaexzmn5wvkkgetrd35kuetyta047h6l8njv6e") // "grants-declined"
)

// seed installs the starting state. Also called by the tests: realm globals
// persist for a whole test binary and examples run after every Test, so a
// pinned Render has to start from a known state.
func seed() {
	board = grants.New(Founders...)
	donations, payments = nil, nil

	alice, bob, carol := Founders[0], Founders[1], Founders[2]

	// 1. The board co-opts a fourth member. Membership executes the moment
	//    it carries, so this one is already completed.
	m := mustRequest(board.SubmitMemberChange(alice, seedMember, true,
		"Reviewed six of the last eight applications from the outside. Give them the seat.", 100))
	mustVote(board.Vote(alice, m.ID, true, "Proposed it.", 101))
	mustVote(board.Vote(bob, m.ID, true, "No objection.", 102))

	// 2. A grant that carried, is mid-delivery, and has a proof under review.
	g := mustRequest(board.Submit(seedApplicant,
		"Port the p/nt/avl benchmarks to gno",
		"Three weeks. Deliverables are a benchmark harness, a report on the "+
			"tree rebalancing costs, and a PR against the monorepo.",
		[]*grants.Milestone{
			grants.NewMilestone("harness merged", 1200),
			grants.NewMilestone("report published", 800),
		}, 110))
	mustVote(board.Vote(alice, g.ID, true, "Cheap for what it tells us.", 111))
	mustVote(board.Vote(bob, g.ID, false, "The second milestone is vague.", 112))
	mustVote(board.Vote(carol, g.ID, true, "Vague but bounded. Worth it.", 113))
	mustVote(board.Vote(seedMember, g.ID, true, "Agreed with carol.", 114))
	must(board.SubmitProof(seedApplicant, g.ID, 0, grants.Proof{
		Kind:   "url",
		Ref:    "https://github.com/gnolang/gno/pull/9999",
		Note:   "Harness merged, 14 benchmarks, runs in CI.",
		Height: 120,
	}))
	mustReview(board.Review(alice, g.ID, 0, true, "Merged, I reviewed it.", 121))

	// 3. A grant the board turned down, kept with the reasons it was turned
	//    down for.
	n := mustRequest(board.Submit(seedRejected,
		"Rewrite gnoweb in a different framework",
		"Six months, one person, no migration plan.",
		[]*grants.Milestone{grants.NewMilestone("the rewrite", 250000)}, 130))
	mustVote(board.Vote(alice, n.ID, false, "No migration plan and no second maintainer.", 131))
	mustVote(board.Vote(bob, n.ID, false, "Out of scope for this board.", 132))
	mustVote(board.Vote(carol, n.ID, false, "Same.", 133))
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

func mustRequest(r *grants.Request, err error) *grants.Request {
	must(err)
	return r
}

func mustVote(_ grants.Status, err error)    { must(err) }
func mustReview(_ grants.Outcome, err error) { must(err) }

// Render serves the board at "", one request at "request/<id>", and the money
// trail at "ledger".
func Render(path string) string {
	path = strings.TrimSpace(path)
	switch {
	case path == "" || path == "/":
		return renderIndex()
	case path == "ledger":
		return renderLedger()
	case strings.HasPrefix(path, "request/"):
		return renderRequest(strings.TrimPrefix(path, "request/"))
	}
	return "# Grants DAO\n\nNo page `" + path + "`. Try [the board](" + link + ") or [the ledger](" + link + ":ledger).\n"
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# Grants DAO\n\n")
	b.WriteString("Anyone may ask this board for money. The members decide in the open, and the\n")
	b.WriteString("money leaves one milestone at a time, each tranche against a proof the board\n")
	b.WriteString("accepted. Every ballot on this page carries the name of who cast it and the\n")
	b.WriteString("reason they gave, including the ones on proofs that were refused.\n\n")

	b.WriteString("## Treasury\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString("| Address | `" + Address().String() + "` |\n")
	b.WriteString("| Balance | " + ugnot(Balance()) + " |\n")
	b.WriteString("| Promised | " + ugnot(Committed()) + " |\n")
	b.WriteString("| Unpromised | " + ugnot(Available()) + " |\n")
	b.WriteString("| Donated | " + ugnot(Raised()) + " |\n")
	b.WriteString("| Paid out | " + ugnot(Disbursed()) + " |\n\n")
	if short := -Available(); short > 0 {
		b.WriteString("The board has promised " + ugnot(short) + " more than it holds. Approving a grant\n")
		b.WriteString("does not escrow anything, so a tranche can come due against an empty treasury;\n")
		b.WriteString("a review that would release one is refused until the money is there. Top it up\n")
		b.WriteString("with `Fund`, or by sending ugnot straight to the address above.\n\n")
	}

	b.WriteString("## Board\n\n")
	b.WriteString("A decision needs a majority of the members eligible to cast a ballot on it,\n")
	b.WriteString("recomputed every time: the party a decision is about never votes on it, so an\n")
	b.WriteString("applicant who sits on the board shrinks the room rather than packing it.\n\n")
	b.WriteString("| Member | Joined at height |\n|---|---|\n")
	for _, m := range Members() {
		b.WriteString("| `" + m.String() + "` | " + i64(board.JoinedAt(m)) + " |\n")
	}
	b.WriteString("\n")

	b.WriteString("## Requests\n\n")
	all := board.List()
	if len(all) == 0 {
		b.WriteString("Nothing has been asked of this board yet.\n\n")
	} else {
		b.WriteString("| # | Kind | Title | Asking | Status | Ballots |\n|---|---|---|---|---|---|\n")
		for _, r := range all {
			yes, no := board.Standing(r)
			b.WriteString("| [" + strconv.Itoa(r.ID) + "](" + link + ":request/" + strconv.Itoa(r.ID) + ")" +
				" | " + r.Kind.String() +
				" | " + r.Title +
				" | " + ask(r) +
				" | " + r.Status.String() +
				" | " + strconv.Itoa(yes) + " for, " + strconv.Itoa(no) + " against" +
				" |\n")
		}
		b.WriteString("\n")
	}

	b.WriteString("## Where the money went\n\n")
	b.WriteString("[The ledger](" + link + ":ledger) lists every donation in and every tranche out,\n")
	b.WriteString("with the height, the payee and the milestone it paid for.\n\n")

	b.WriteString("## Calling it\n\n")
	b.WriteString("```sh\n")
	b.WriteString("# put money in\n")
	b.WriteString("gnokey maketx call -pkgpath " + Path + " -func Fund -send 5000000ugnot ...\n")
	b.WriteString("# ask for some\n")
	b.WriteString("gnokey maketx call -pkgpath " + Path + " -func Apply \\\n")
	b.WriteString("  -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' ...\n")
	b.WriteString("# decide (members only)\n")
	b.WriteString("gnokey maketx call -pkgpath " + Path + " -func Vote -args 4 -args true -args 'reason' ...\n")
	b.WriteString("# show your work, then get paid for it\n")
	b.WriteString("gnokey maketx call -pkgpath " + Path + " -func SubmitProof \\\n")
	b.WriteString("  -args 4 -args 0 -args url -args 'https://…' -args 'what it is' ...\n")
	b.WriteString("gnokey maketx call -pkgpath " + Path + " -func Review -args 4 -args 0 -args true -args 'looks done' ...\n")
	b.WriteString("```\n\n")

	b.WriteString("Built on [p/moul/x/grants/v0](/p/moul/x/grants/v0), which holds the state\n")
	b.WriteString("machine and no coins.\n")
	return b.String()
}

func renderRequest(raw string) string {
	id, err := strconv.Atoi(raw)
	if err != nil {
		return "# Grants DAO\n\n`" + raw + "` is not a request number.\n"
	}
	r := board.Get(id)
	if r == nil {
		return "# Grants DAO\n\nThere is no request " + raw + ".\n"
	}

	var b strings.Builder
	b.WriteString("# Request " + strconv.Itoa(r.ID) + ": " + r.Title + "\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString("| Kind | " + r.Kind.String() + " |\n")
	b.WriteString("| Applicant | `" + r.Applicant.String() + "` |\n")
	if r.Kind == grants.KindMember {
		b.WriteString("| Subject | `" + r.Subject.String() + "` |\n")
		b.WriteString("| Effect | " + addRemove(r.Add) + " |\n")
	}
	b.WriteString("| Status | " + r.Status.String() + " |\n")
	b.WriteString("| Filed at height | " + i64(r.CreatedAt) + " |\n")
	if r.DecidedAt != 0 {
		b.WriteString("| Decided at height | " + i64(r.DecidedAt) + " |\n")
	}
	if r.Kind == grants.KindGrant {
		b.WriteString("| Asking | " + ugnot(r.Total()) + " |\n")
		b.WriteString("| Paid so far | " + ugnot(r.Paid()) + " |\n")
		b.WriteString("| Still owed | " + ugnot(r.Outstanding()) + " |\n")
	}
	b.WriteString("\n")

	if placeholder(r.Applicant) {
		b.WriteString("> Seeded at deploy, not filed by anyone. `" + r.Applicant.String() + "`\n")
		b.WriteString("> is a placeholder with a valid checksum and no key behind it, so this request\n")
		b.WriteString("> can never be carried further by its applicant, and a tranche released to it\n")
		b.WriteString("> would go nowhere. It is here to show the shape of a live one.\n\n")
	}

	if r.Body != "" {
		b.WriteString("## The ask\n\n" + r.Body + "\n\n")
	}

	b.WriteString("## Ballots\n\n")
	yes, no := board.Standing(r)
	recorded, against := r.Tally()
	b.WriteString("Needs " + strconv.Itoa(board.Majority(r)) + " of " + strconv.Itoa(board.Eligible(r)) +
		" eligible members. Standing: " + strconv.Itoa(yes) + " for, " + strconv.Itoa(no) + " against.\n")
	if recorded != yes || against != no {
		b.WriteString("On the record: " + strconv.Itoa(recorded) + " for, " + strconv.Itoa(against) +
			" against. The difference is ballots cast by people who have since left the board;\n")
		b.WriteString("they stay on the record and stop counting.\n")
	}
	b.WriteString("\n")
	if len(r.Votes) == 0 {
		b.WriteString("Nobody has voted yet.\n\n")
	} else {
		b.WriteString(ballots(r.Votes, "for", "against"))
	}

	if r.Kind != grants.KindGrant {
		return b.String()
	}

	b.WriteString("## Milestones\n\n")
	b.WriteString("Earned in order. The applicant submits a proof, the board reviews that proof,\n")
	b.WriteString("and the verdict that carries also moves the coins.\n\n")
	for i, m := range r.Milestones {
		b.WriteString("### " + strconv.Itoa(i+1) + ". " + m.Title + ": " + ugnot(m.Amount) + "\n\n")
		b.WriteString(milestoneState(r, i, m) + "\n\n")
		for j, a := range m.Attempts {
			b.WriteString("**Proof " + strconv.Itoa(j+1) + "** (" + a.Proof.Kind + ", height " +
				i64(a.Proof.Height) + ", " + a.Outcome.String() + ")\n\n")
			b.WriteString("```\n" + a.Proof.Ref + "\n```\n\n")
			if a.Proof.Note != "" {
				b.WriteString(a.Proof.Note + "\n\n")
			}
			if len(a.Reviews) == 0 {
				b.WriteString("No review yet.\n\n")
				continue
			}
			b.WriteString(ballots(a.Reviews, "accept", "refuse"))
		}
	}
	return b.String()
}

func renderLedger() string {
	var b strings.Builder
	b.WriteString("# Grants DAO: the ledger\n\n")
	b.WriteString("Every coin in and every coin out, in the order it happened. Coins sent\n")
	b.WriteString("straight to `" + Address().String() + "` land in the treasury\n")
	b.WriteString("without appearing here, which is why `Fund` exists: it is the same transfer\n")
	b.WriteString("with a name attached.\n\n")

	b.WriteString("## In\n\n")
	if len(donations) == 0 {
		b.WriteString("Nothing donated through `Fund` yet.\n\n")
	} else {
		b.WriteString("| Height | From | Amount |\n|---|---|---|\n")
		for _, d := range donations {
			b.WriteString("| " + i64(d.Height) + " | `" + d.From.String() + "` | " + ugnot(d.Amount) + " |\n")
		}
		b.WriteString("\nTotal in: " + ugnot(Raised()) + "\n\n")
	}

	b.WriteString("## Out\n\n")
	if len(payments) == 0 {
		b.WriteString("No tranche has been released yet.\n\n")
	} else {
		b.WriteString("| Height | Request | Milestone | To | Amount |\n|---|---|---|---|---|\n")
		for _, p := range payments {
			b.WriteString("| " + i64(p.Height) +
				" | [" + strconv.Itoa(p.Request) + "](" + link + ":request/" + strconv.Itoa(p.Request) + ")" +
				" | " + strconv.Itoa(p.Milestone+1) +
				" | `" + p.To.String() + "`" +
				" | " + ugnot(p.Amount) + " |\n")
		}
		b.WriteString("\nTotal out: " + ugnot(Disbursed()) + "\n\n")
	}

	b.WriteString("Balance now: " + ugnot(Balance()) + ". [Back to the board](" + link + ").\n")
	return b.String()
}

// ballots renders one decision's ballots, marking anyone who has since left
// the board: their vote stays on the record and stops counting.
func ballots(bs []grants.Ballot, forLabel, againstLabel string) string {
	var b strings.Builder
	b.WriteString("| Member | Vote | Height | Reason |\n|---|---|---|---|\n")
	for _, v := range bs {
		who := "`" + v.Voter.String() + "`"
		if !board.IsMember(v.Voter) {
			who += " (left the board)"
		}
		vote := againstLabel
		if v.Approve {
			vote = forLabel
		}
		b.WriteString("| " + who + " | " + vote + " | " + i64(v.Height) + " | " + orDash(v.Reason) + " |\n")
	}
	b.WriteString("\n")
	return b.String()
}

func milestoneState(r *grants.Request, i int, m *grants.Milestone) string {
	switch {
	case m.Released:
		return "Released at height " + i64(m.ReleasedAt) + ", paid to `" + r.Applicant.String() + "`."
	case r.Status != grants.Approved:
		return "Locked: the request is " + r.Status.String() + "."
	case m.Current() != nil:
		return "A proof is under review."
	case i == r.Next():
		return "Waiting on a proof from the applicant."
	}
	return "Locked until milestone " + strconv.Itoa(r.Next()+1) + " is released."
}

// placeholder reports whether an address is one of the seeded stand-ins.
func placeholder(a address) bool {
	return a == seedMember || a == seedApplicant || a == seedRejected
}

func ask(r *grants.Request) string {
	if r.Kind == grants.KindMember {
		return "nothing"
	}
	return ugnot(r.Total())
}

func addRemove(add bool) string {
	if add {
		return "add to the board"
	}
	return "remove from the board"
}

func ugnot(n int64) string { return strconv.FormatInt(n, 10) + " ugnot" }

func i64(n int64) string { return strconv.FormatInt(n, 10) }

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
