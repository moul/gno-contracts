package grants

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/nt/markdown/sanitize/v0"
)

// Renderer turns a Program into the three markdown pages a grant program
// needs: the board, one request, and the ledger. Everything that differs
// between one program and the next is a field, so a realm's whole Render is
// building this literal and calling it.
//
// Build it INSIDE Render rather than storing it in a realm global: Note is a
// func, and Balance has to be read fresh on every call anyway.
//
// # Escaping
//
// Everything a caller typed (titles, bodies, reasons, proofs, notes) is
// escaped here, once, through p/moul/kit/ui and p/nt/markdown/sanitize. A
// realm does not repeat it and must not pre-escape: escaping twice shows the
// backslashes. The realm's OWN fields below (Title, Intro, Notes, Footer) are
// chrome, are written by whoever deployed the realm, and are emitted as-is so
// they can carry markdown.
type Renderer struct {
	Program  *Program
	Title    string   // page heading
	Intro    string   // markdown under the heading, already wrapped
	Notes    []string // extra paragraphs on the board page: house rules, scope
	Path     string   // package path, for the gnokey examples
	Link     string   // gnoweb route prefix, e.g. "/r/moul/grant/v0"
	Treasury address  // where the money sits
	Balance  int64    // what it holds right now
	Footer   string   // closing paragraph on the board page

	// Note returns an extra callout for one request page, or "". Use it for
	// anything the library cannot know, such as a seeded request whose
	// applicant address has no key behind it.
	Note func(*Request) string
}

// Render serves the board at "", one request at "request/<id>", and the money
// trail at "ledger".
func (rr Renderer) Render(path string) string {
	path = strings.TrimSpace(path)
	switch {
	case path == "" || path == "/":
		return rr.index()
	case path == "ledger":
		return rr.ledger()
	case strings.HasPrefix(path, "request/"):
		return rr.request(strings.TrimPrefix(path, "request/"))
	}
	return "# " + rr.Title + "\n\nNo page `" + path + "`. Try [the board](" + rr.Link +
		") or [the ledger](" + rr.Link + ":ledger).\n"
}

func (rr Renderer) index() string {
	p := rr.Program
	var b strings.Builder
	b.WriteString("# " + rr.Title + "\n\n")
	if rr.Intro != "" {
		b.WriteString(rr.Intro + "\n\n")
	}
	for _, n := range rr.Notes {
		b.WriteString(n + "\n\n")
	}

	b.WriteString("## Treasury\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString("| Address | " + ui.AddrFull(rr.Treasury) + " |\n")
	b.WriteString("| Balance | " + rr.amount(rr.Balance) + " |\n")
	b.WriteString("| Promised | " + rr.amount(p.Committed()) + " |\n")
	b.WriteString("| Unpromised | " + rr.amount(p.Available(rr.Balance)) + " |\n")
	b.WriteString("| Donated | " + rr.amount(p.Raised()) + " |\n")
	b.WriteString("| Paid out | " + rr.amount(p.Disbursed()) + " |\n\n")
	if short := -p.Available(rr.Balance); short > 0 {
		b.WriteString("The board has promised " + rr.amount(short) + " more than it holds. Approving a\n")
		b.WriteString("grant does not escrow anything, so a tranche can come due against an empty\n")
		b.WriteString("treasury; a review that would release one is refused until the money is there.\n")
		b.WriteString("Top it up with `Fund`, or by sending coins straight to the address above.\n\n")
	}

	b.WriteString("## Board\n\n")
	b.WriteString("A decision needs a majority of the members eligible to cast a ballot on it,\n")
	b.WriteString("recomputed every time: the party a decision is about never votes on it, so an\n")
	b.WriteString("applicant who sits on the board shrinks the room rather than packing it.\n\n")
	b.WriteString("| Member | Joined at height |\n|---|---|\n")
	for _, m := range p.Board.Members() {
		b.WriteString("| " + ui.AddrFull(m) + " | " + i64(p.Board.JoinedAt(m)) + " |\n")
	}
	b.WriteString("\n")

	b.WriteString("## Requests\n\n")
	all := p.Board.List()
	if len(all) == 0 {
		b.WriteString("Nothing has been asked of this board yet. `Apply` is open to anyone.\n\n")
	} else {
		b.WriteString("| # | Kind | Title | For | Asking | Status | Ballots |\n|---|---|---|---|---|---|---|\n")
		for _, r := range all {
			yes, no := p.Board.Standing(r)
			b.WriteString("| [" + strconv.Itoa(r.ID) + "](" + rr.Link + ":request/" + strconv.Itoa(r.ID) + ")" +
				" | " + r.Kind.String() +
				" | " + ui.Cell(r.Title) +
				" | " + rr.who(r) +
				" | " + rr.ask(r) +
				" | " + r.Status.String() +
				" | " + strconv.Itoa(yes) + " for, " + strconv.Itoa(no) + " against" +
				" |\n")
		}
		b.WriteString("\n")
	}

	b.WriteString("## Where the money went\n\n")
	b.WriteString("[The ledger](" + rr.Link + ":ledger) lists every donation in and every tranche\n")
	b.WriteString("out, with the height, the payee and the milestone it paid for.\n\n")

	b.WriteString("## Calling it\n\n")
	b.WriteString("```sh\n")
	b.WriteString("# put money in\n")
	b.WriteString("gnokey maketx call -pkgpath " + rr.Path + " -func Fund -send 5000000" + p.Denom + " ...\n")
	b.WriteString("# ask for some\n")
	b.WriteString("gnokey maketx call -pkgpath " + rr.Path + " -func Apply \\\n")
	b.WriteString("  -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' ...\n")
	b.WriteString("# ask on behalf of someone who cannot pay the gas to ask\n")
	b.WriteString("gnokey maketx call -pkgpath " + rr.Path + " -func ApplyFor \\\n")
	b.WriteString("  -args g1... -args 'their account is empty' \\\n")
	b.WriteString("  -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' ...\n")
	b.WriteString("# decide (members only)\n")
	b.WriteString("gnokey maketx call -pkgpath " + rr.Path + " -func Vote -args 1 -args true -args 'reason' ...\n")
	b.WriteString("# show your work, then get paid for it\n")
	b.WriteString("gnokey maketx call -pkgpath " + rr.Path + " -func SubmitProof \\\n")
	b.WriteString("  -args 1 -args 0 -args url -args 'https://...' -args 'what it is' ...\n")
	b.WriteString("gnokey maketx call -pkgpath " + rr.Path + " -func Review -args 1 -args 0 -args true -args 'looks done' ...\n")
	b.WriteString("```\n")
	if rr.Footer != "" {
		b.WriteString("\n" + rr.Footer + "\n")
	}
	return b.String()
}

func (rr Renderer) request(raw string) string {
	id, err := strconv.Atoi(raw)
	if err != nil {
		return "# " + rr.Title + "\n\n`" + raw + "` is not a request number.\n"
	}
	r := rr.Program.Board.Get(id)
	if r == nil {
		return "# " + rr.Title + "\n\nThere is no request " + raw + ".\n"
	}
	board := rr.Program.Board

	var b strings.Builder
	b.WriteString("# Request " + strconv.Itoa(r.ID) + ": " + ui.Inline(r.Title) + "\n\n")
	b.WriteString("| Field | Value |\n|---|---|\n")
	b.WriteString("| Kind | " + r.Kind.String() + " |\n")
	b.WriteString("| Applicant | " + ui.AddrFull(r.Applicant) + " |\n")
	if r.OnBehalf() {
		b.WriteString("| Beneficiary | " + ui.AddrFull(r.Beneficiary) + " |\n")
	}
	if r.Kind == KindMember {
		b.WriteString("| Subject | " + ui.AddrFull(r.Subject) + " |\n")
		b.WriteString("| Effect | " + addRemove(r.Add) + " |\n")
	}
	b.WriteString("| Status | " + r.Status.String() + " |\n")
	b.WriteString("| Filed at height | " + i64(r.CreatedAt) + " |\n")
	if r.DecidedAt != 0 {
		b.WriteString("| Decided at height | " + i64(r.DecidedAt) + " |\n")
	}
	if r.Kind == KindGrant {
		b.WriteString("| Asking | " + rr.amount(r.Total()) + " |\n")
		b.WriteString("| Paid so far | " + rr.amount(r.Paid()) + " |\n")
		b.WriteString("| Still owed | " + rr.amount(r.Outstanding()) + " |\n")
	}
	b.WriteString("\n")

	if r.OnBehalf() {
		b.WriteString("## Filed for someone else\n\n")
		b.WriteString("The applicant is not the payee: every tranche of this request pays\n")
		b.WriteString(ui.AddrFull(r.Beneficiary) + ". Both addresses are barred from voting on it, and\n")
		b.WriteString("either may submit a proof. The reason given:\n\n")
		b.WriteString("> " + ui.Inline(r.Reason) + "\n\n")
		b.WriteString("Nothing checks that reason. It is a claim by the applicant, and the point of\n")
		b.WriteString("printing it here is that a member can check it before voting.\n\n")
	}

	if rr.Note != nil {
		if note := rr.Note(r); note != "" {
			b.WriteString(note + "\n\n")
		}
	}

	if r.Body != "" {
		b.WriteString("## The ask\n\n" + block(r.Body) + "\n\n")
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
		b.WriteString(rr.ballots(r.Votes, "for", "against"))
	}

	if r.Kind != KindGrant {
		return b.String()
	}

	b.WriteString("## Milestones\n\n")
	b.WriteString("Earned in order. The applicant submits a proof, the board reviews that proof,\n")
	b.WriteString("and the verdict that carries also moves the coins.\n\n")
	for i, m := range r.Milestones {
		b.WriteString("### " + strconv.Itoa(i+1) + ". " + ui.Inline(m.Title) + ": " + rr.amount(m.Amount) + "\n\n")
		b.WriteString(milestoneState(r, i, m) + "\n\n")
		for j, a := range m.Attempts {
			b.WriteString("**Proof " + strconv.Itoa(j+1) + "** (" + a.Proof.Kind + ", height " +
				i64(a.Proof.Height) + ", " + a.Outcome.String() + ")\n\n")
			b.WriteString(fence(a.Proof.Ref) + "\n\n")
			if a.Proof.Note != "" {
				b.WriteString(block(a.Proof.Note) + "\n\n")
			}
			if len(a.Reviews) == 0 {
				b.WriteString("No review yet.\n\n")
				continue
			}
			b.WriteString(rr.ballots(a.Reviews, "accept", "refuse"))
		}
	}
	return b.String()
}

func (rr Renderer) ledger() string {
	p := rr.Program
	var b strings.Builder
	b.WriteString("# " + rr.Title + ": the ledger\n\n")
	b.WriteString("Every coin in and every coin out, in the order it happened. Coins sent\n")
	b.WriteString("straight to " + ui.AddrFull(rr.Treasury) + " land in the treasury\n")
	b.WriteString("without appearing here, which is why `Fund` exists: it is the same transfer\n")
	b.WriteString("with a name attached.\n\n")

	b.WriteString("## In\n\n")
	if len(p.Donations) == 0 {
		b.WriteString("Nothing donated through `Fund` yet.\n\n")
	} else {
		b.WriteString("| Height | From | Amount |\n|---|---|---|\n")
		for _, d := range p.Donations {
			b.WriteString("| " + i64(d.Height) + " | " + ui.AddrFull(d.From) + " | " + rr.amount(d.Amount) + " |\n")
		}
		b.WriteString("\nTotal in: " + rr.amount(p.Raised()) + "\n\n")
	}

	b.WriteString("## Out\n\n")
	if len(p.Payments) == 0 {
		b.WriteString("No tranche has been released yet.\n\n")
	} else {
		b.WriteString("| Height | Request | Milestone | To | Amount |\n|---|---|---|---|---|\n")
		for _, pay := range p.Payments {
			b.WriteString("| " + i64(pay.Height) +
				" | [" + strconv.Itoa(pay.Request) + "](" + rr.Link + ":request/" + strconv.Itoa(pay.Request) + ")" +
				" | " + strconv.Itoa(pay.Milestone+1) +
				" | " + ui.AddrFull(pay.To) +
				" | " + rr.amount(pay.Amount) + " |\n")
		}
		b.WriteString("\nTotal out: " + rr.amount(p.Disbursed()) + "\n\n")
	}

	b.WriteString("Balance now: " + rr.amount(rr.Balance) + ". [Back to the board](" + rr.Link + ").\n")
	return b.String()
}

// ballots renders one decision's ballots, marking anyone who has since left
// the board: their vote stays on the record and stops counting.
func (rr Renderer) ballots(bs []Ballot, forLabel, againstLabel string) string {
	var b strings.Builder
	b.WriteString("| Member | Vote | Height | Reason |\n|---|---|---|---|\n")
	for _, v := range bs {
		who := ui.AddrFull(v.Voter)
		if !rr.Program.Board.IsMember(v.Voter) {
			who += " (left the board)"
		}
		vote := againstLabel
		if v.Approve {
			vote = forLabel
		}
		b.WriteString("| " + who + " | " + vote + " | " + i64(v.Height) + " | " + orDash(ui.Cell(v.Reason)) + " |\n")
	}
	b.WriteString("\n")
	return b.String()
}

func (rr Renderer) amount(n int64) string { return strconv.FormatInt(n, 10) + " " + rr.Program.Denom }

// who is the board index's "For" column: who this request would pay, marked
// when that is not the address that filed it.
func (rr Renderer) who(r *Request) string {
	if r.Kind == KindMember {
		return "-"
	}
	if r.OnBehalf() {
		return ui.Addr(r.Beneficiary) + " (filed by " + ui.AddrText(r.Applicant) + ")"
	}
	return ui.Addr(r.Applicant)
}

func (rr Renderer) ask(r *Request) string {
	if r.Kind == KindMember {
		return "nothing"
	}
	return rr.amount(r.Total())
}

func milestoneState(r *Request, i int, m *Milestone) string {
	switch {
	case m.Released:
		return "Released at height " + i64(m.ReleasedAt) + ", paid to " + ui.AddrFull(r.Payee()) + "."
	case r.Status != Approved:
		return "Locked: the request is " + r.Status.String() + "."
	case m.Current() != nil:
		return "A proof is under review."
	case i == r.Next():
		return "Waiting on a proof from the applicant."
	}
	return "Locked until milestone " + strconv.Itoa(r.Next()+1) + " is released."
}

func addRemove(add bool) string {
	if add {
		return "add to the board"
	}
	return "remove from the board"
}

// block and fence escape a multi-line, user-written string for its slot and
// then trim the sanitizer's own trailing newlines.
//
// The trim is not cosmetic. gno collapses two consecutive blank lines in an
// Example's output the way Go does, so any page that emits one can never be
// pinned by an ExampleRender, and the only test that proves a whole page is
// the one that stops working.
func block(s string) string { return strings.TrimSpace(sanitize.Block(s)) }

func fence(s string) string { return strings.TrimSpace(sanitize.CodeBlock(s)) }

func i64(n int64) string { return strconv.FormatInt(n, 10) }

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
