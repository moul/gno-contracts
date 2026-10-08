package crews

import (
	"strconv"

	"chain/runtime"

	"gno.land/p/moul/kit/num/v0"
	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/x/social/crew/v0"
	"gno.land/p/moul/xmath/v1"
)

// Render routes three views: the index, one crew, and one proposal.
func Render(path string) string {
	req := realmpath.Parse(path)

	switch req.PathPart(0) {
	case "":
		return renderIndex()
	case "crew":
		return renderCrew(req.PathPart(1))
	case "proposal":
		return renderProposal(req.PathPart(1))
	default:
		return md.H1("Not found") + "No such view: " + ui.Inline(req.Path)
	}
}

func renderIndex() string {
	out := md.H1("Crews")
	out += "Three to fifteen people with a shared pot, a way to decide, and a way to " +
		"leave with their share. One transaction to start one.\n\n"

	t := ui.NewTable("crews", "proposals", "owed to people who left")
	t.Row(
		strconv.Itoa(crews.Len()),
		strconv.Itoa(crews.ProposalCount()),
		num.GNOTf(crews.TotalOwed()),
	)
	out += t.String()

	out += md.H2("The crews")
	out += crewTable(crews.List(IndexCrews))

	out += "\n" + ui.Action("Start a crew", "Create", "name", "") + "\n"

	out += md.H2("How a share works")
	out += md.BulletList([]string{
		"A share is the vote weight and the claim on the treasury at once. There is no second token.",
		"Joining mints shares at what a share is worth NOW: " +
			md.InlineCode("amount * totalShares / treasury") +
			", rounded down, so a late joiner cannot buy into value the others built.",
		"Ragequitting burns every share you hold and credits you " +
			md.InlineCode("shares * treasury / totalShares") +
			", rounded down. Nobody has to agree.",
		"Both round in the crew's favour. The last member out holds every share, " +
			"so the treasury still empties to the last ugnot.",
		"A proposal is advisory text. Passing one records agreement and executes nothing.",
	})

	out += md.H2("Custody")
	out += "One realm address holds every crew's treasury, with per-crew accounting " +
		"inside. A bug in that accounting is a bug across crews, not inside one. " +
		"The fix is one realm per crew, and it is v1.\n"

	return out
}

func renderCrew(raw string) string {
	id, ok := store.ParseID(raw)
	if !ok {
		return md.H1("Crews") + "Not a crew id: " + ui.Inline(raw)
	}
	c, found := crews.Get(id)
	if !found {
		return md.H1("Crews") + "No crew #" + id.String()
	}

	out := md.H1(ui.Inline(c.Name))
	out += md.Italic("crew #"+id.String()+" · opened at block "+
		strconv.FormatInt(c.CreatedAt, 10)) + "\n\n"

	t := ui.NewTable("members", "shares", "treasury", "per share")
	t.Row(
		strconv.Itoa(c.MemberCount())+" of "+strconv.Itoa(crew.MaxMembers),
		strconv.FormatInt(c.TotalShares, 10),
		num.GNOTf(c.Treasury),
		num.GNOTf(c.ValuePerShare()),
	)
	out += t.String()

	out += md.H2("Members")
	if c.MemberCount() == 0 {
		out += ui.Empty("Everybody has left. The next member in pays the opening price again.")
	} else {
		m := ui.NewTable("member", "shares", "weight", "worth")
		for _, who := range c.Members() {
			shares := c.SharesOf(who)
			m.Row(
				ui.Addr(who),
				strconv.FormatInt(shares, 10),
				num.Pct(xmath.MulDiv(shares, 10000, c.TotalShares)),
				num.GNOTf(xmath.MulDiv(shares, c.Treasury, c.TotalShares)),
			)
		}
		out += m.String()
	}

	out += md.H2("Proposals")
	out += proposalTable(c.Proposals())
	out += "\nA proposal is advisory text. Passing one records that the crew agreed " +
		"by share weight, and executes nothing.\n"

	out += "\n" + ui.Join(" · ",
		ui.Action("Join", "Join", "crewID", id.String()),
		ui.Action("Fund", "Fund", "crewID", id.String()),
		ui.Action("Propose", "Propose", "crewID", id.String(), "text", ""),
		ui.Action("Ragequit", "Ragequit", "crewID", id.String()),
	) + "\n"
	return out
}

func renderProposal(raw string) string {
	pid, ok := store.ParseID(raw)
	if !ok {
		return md.H1("Crews") + "Not a proposal id: " + ui.Inline(raw)
	}
	p, found := crews.Proposal(pid)
	if !found {
		return md.H1("Crews") + "No proposal #" + pid.String()
	}

	out := md.H1("Proposal #" + pid.String())
	out += md.Blockquote(ui.Inline(p.Text)) + "\n"

	crewName := "crew #" + p.CrewID.String()
	if c, ok := crews.Get(p.CrewID); ok {
		crewName = c.Name
	}
	out += md.Italic("by "+ui.Addr(p.Author)+" · in "+
		md.Link(ui.ShortN(crewName, crew.ExcerptLen, 0), crewURL(p.CrewID))) + "\n\n"

	now := runtime.ChainHeight()
	t := ui.NewTable("state", "yes", "no", "voters")
	t.Row(
		state(p, now),
		strconv.FormatInt(p.Yes, 10),
		strconv.FormatInt(p.No, 10),
		strconv.Itoa(p.Voters()),
	)
	out += t.String()

	if p.Open(now) {
		out += "\n" + ui.Join(" · ",
			ui.Action("Vote yes", "Vote", "proposalID", pid.String(), "yes", "true"),
			ui.Action("Vote no", "Vote", "proposalID", pid.String(), "yes", "false"),
		) + "\n"
	} else if !p.Closed {
		out += "\n" + ui.Action("Close it", "Close", "proposalID", pid.String()) + "\n"
	}
	return out
}

// crewTable lists crews, newest first.
func crewTable(items []crew.Listing) string {
	t := ui.NewTable("crew", "members", "shares", "treasury")
	for _, it := range items {
		t.Row(
			// ShortN truncates without escaping and md.Link escapes what it
			// is given: ui.Inline here would escape twice and render the
			// backslashes. A pipe is what md.Link's escaper does NOT cover,
			// which is why crew.ValidName refuses one at write time.
			md.Link(ui.ShortN(it.Crew.Name, crew.ExcerptLen, 0), crewURL(it.ID)),
			strconv.Itoa(it.Crew.MemberCount()),
			strconv.FormatInt(it.Crew.TotalShares, 10),
			num.GNOTf(it.Crew.Treasury),
		)
	}
	return t.OrEmpty("No crews yet.")
}

// proposalTable lists a crew's proposals, newest first.
//
// The link title is the id and not the text, which is the opposite of
// crewTable and deliberate: a proposal's text is free prose and may contain a
// pipe, md.Link's escaper leaves pipes alone, and a pipe in a link title inside
// a table cell opens a column. So the chrome carries the link and the prose
// goes through ui.Cell, which is the escaper that knows it is in a table.
func proposalTable(ids []store.ID) string {
	now := runtime.ChainHeight()
	// Finding 325-cost-at-caps-1: this rendered every proposal a crew has
	// ever had, and proposing is open to every member with no delete path.
	// Newest first already, so the bound is on where the walk stops.
	total := len(ids)
	stop := 0
	if total > IndexProposals {
		stop = total - IndexProposals
	}
	t := ui.NewTable("#", "proposal", "state", "yes", "no")
	for i := total - 1; i >= stop; i-- {
		p, ok := crews.Proposal(ids[i])
		if !ok {
			continue
		}
		t.Row(
			md.Link("#"+ids[i].String(), proposalURL(ids[i])),
			// Cut on a rune boundary first, escape once after: escaping
			// first and cutting after can strand a lone backslash.
			ui.Cell(ui.ShortN(p.Text, crew.ExcerptLen, 0)),
			state(p, now),
			strconv.FormatInt(p.Yes, 10),
			strconv.FormatInt(p.No, 10),
		)
	}
	out := t.OrEmpty("Nothing has been proposed yet.")
	if total > IndexProposals {
		out += md.Italic("Showing the newest "+strconv.Itoa(IndexProposals)+" of "+
			strconv.Itoa(total)+" proposals.") + "\n"
	}
	return out
}

// state is the one word a proposal is in at height now.
func state(p *crew.Proposal, now int64) string {
	switch {
	case p.Open(now):
		return "open until " + strconv.FormatInt(p.Deadline, 10)
	case !p.Closed:
		return "awaiting a close"
	case p.Passed:
		return "passed"
	default:
		return "failed"
	}
}

// crewURL is the gnoweb path of one crew.
func crewURL(id store.ID) string { return realmURL() + ":crew/" + id.String() }

// proposalURL is the gnoweb path of one proposal.
func proposalURL(id store.ID) string { return realmURL() + ":proposal/" + id.String() }

// realmURL is this realm's gnoweb path. The chain domain is the first element
// of a package path and a gnoweb path is the rest of it, so this is a prefix
// strip and not a hostname the realm has to know.
func realmURL() string {
	for i := 0; i < len(realmPath); i++ {
		if realmPath[i] == '/' {
			return realmPath[i:]
		}
	}
	return "/" + realmPath
}
