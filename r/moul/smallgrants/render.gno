package grants

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/num/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
)

// untrusted-render: every title, reason and note goes through ui.Cell or ui.Inline at the line that renders it

// RecentDecided is how many decided requests the index shows. The page and
// its query gas stay bounded however long the realm runs; older ones are each
// still at their own page.
const RecentDecided = 10

// Render serves the index at "", one request at "request/<id>" and one motion
// at "motion/<id>".
func Render(path string) string {
	req := realmpath.Parse(path)
	switch req.PathPart(0) {
	case "":
		return renderIndex()
	case "request":
		return renderRequest(req.PathPart(1))
	case "motion":
		return renderMotion(req.PathPart(1))
	}
	return md.H1("Not found") + "There is no page at that path.\n"
}

func renderIndex() string {
	out := md.H1("Small grants") + "\n"
	out += "Ask for a small amount of GNOT, for yourself or for someone else, in the open.\n" +
		"The controllers below vote in public, and the vote that makes a majority pays\n" +
		"the request out of this realm's balance in the same transaction.\n\n"

	state := "open to everyone"
	if paused {
		state = "**paused**: new requests from the allowlist only; everything filed still runs"
	}
	t := ui.NewTable("", "")
	t.Row("Requests", state)
	t.Row("Cap per request", num.GNOTf(MaxGrant))
	t.Row("Balance", "**"+num.GNOTf(Balance())+"**")
	t.Row("Paid out", num.GNOTf(totalPaid)+" over "+itoa(paidCount)+" grant(s)")
	t.Row("Decision", strconv.Itoa(Quorum())+" yes of "+strconv.Itoa(len(controllers))+" controllers")
	t.Row("Fund it", "a plain send to "+ui.AddrFull(selfAddr))
	out += t.String() + "\n"

	out += md.H2("Ask") + md.CodeBlock(askCommand()) + "\n"

	out += md.H2("Open requests")
	ot := ui.NewTable("#", "Title", "To", "Amount", "Yes")
	open.Iterate("", "", func(k string, _ any) bool {
		r := requests.Get(k).(*request)
		ot.Row(md.Link("#"+itoa(r.ID), requestLink(r.ID)), ui.Cell(ui.ShortN(r.Title, 60, 0)),
			ui.Addr(r.To), num.GNOTf(r.Amount), strconv.Itoa(yesCount(r.Ballots))+"/"+strconv.Itoa(Quorum()))
		return false
	})
	out += ot.OrEmpty("Nothing is waiting for a decision.") + "\n"

	out += md.H2("Recently decided")
	dt := ui.NewTable("#", "Title", "To", "Amount", "Outcome")
	requests.ReverseIterate("", "", func(k string, v any) bool {
		r := v.(*request)
		if r.Status == StatusPending {
			return false
		}
		dt.Row(md.Link("#"+itoa(r.ID), requestLink(r.ID)), ui.Cell(ui.ShortN(r.Title, 60, 0)),
			ui.Addr(r.To), num.GNOTf(r.Amount), r.Status)
		return dt.Len() >= RecentDecided
	})
	out += dt.OrEmpty("Nothing has been decided yet.") + "\n"

	out += md.H2("Controllers")
	cs := make([]string, len(controllers))
	for i, c := range controllers {
		cs[i] = ui.AddrFull(c)
	}
	out += md.BulletList(cs) + "\n"

	out += md.H2("Motions")
	mt := ui.NewTable("#", "Change", "Status")
	motions.ReverseIterate("", "", func(_ string, v any) bool {
		m := v.(*motion)
		mt.Row(md.Link("#"+itoa(m.ID), motionLink(m.ID)), change(m), m.Status)
		return mt.Len() >= RecentDecided
	})
	out += mt.OrEmpty("Nobody has proposed changing the controllers.") + "\n"

	out += md.H2("Allowlist") +
		"Who may still file while the realm is paused. Its own list, not the controllers.\n\n"
	var al []string
	allowlist.Iterate("", "", func(k string, _ any) bool {
		al = append(al, ui.AddrFull(address(k)))
		return false
	})
	if len(al) == 0 {
		out += ui.Empty("Nobody.")
	} else {
		out += md.BulletList(al)
	}
	return out
}

func renderRequest(raw string) string {
	r := getRequest(parseID(raw))
	if r == nil {
		return md.H1("Not found") + "There is no request " + ui.Inline(raw) + ".\n"
	}
	out := md.H1("Request #"+itoa(r.ID)) + md.H2(ui.Inline(r.Title))
	t := ui.NewTable("", "")
	t.Row("Status", "**"+r.Status+"**")
	t.Row("Amount", num.GNOTf(r.Amount))
	t.Row("Pays", ui.AddrFull(r.To))
	t.Row("Filed by", ui.AddrFull(r.By))
	t.Row("Filed at height", itoa(r.Height))
	if r.Status != StatusPending {
		t.Row("Decided at height", itoa(r.Decided))
	}
	out += t.String() + "\n" + md.Blockquote(ui.Inline(r.Reason)) + "\n"
	out += md.H2("Ballots") + ballots(r.Ballots)
	return out
}

func renderMotion(raw string) string {
	m := getMotion(parseID(raw))
	if m == nil {
		return md.H1("Not found") + "There is no motion " + ui.Inline(raw) + ".\n"
	}
	out := md.H1("Motion #" + itoa(m.ID))
	t := ui.NewTable("", "")
	t.Row("Change", change(m))
	t.Row("Status", "**"+m.Status+"**")
	t.Row("Proposed by", ui.AddrFull(m.By))
	t.Row("Filed at height", itoa(m.Height))
	if m.Status != StatusPending {
		t.Row("Decided at height", itoa(m.Decided))
	}
	out += t.String() + "\n" + md.Blockquote(ui.Inline(m.Reason)) + "\n"
	out += md.H2("Ballots") + ballots(m.Ballots)
	return out
}

func ballots(bs []ballot) string {
	t := ui.NewTable("Controller", "Vote", "Height", "Note")
	for _, b := range bs {
		v := "no"
		if b.Yes {
			v = "yes"
		}
		if !isController(b.Voter) {
			v += " (no longer a controller, not counted)"
		}
		t.Row(ui.Addr(b.Voter), v, itoa(b.Height), ui.Cell(b.Note))
	}
	return t.OrEmpty("No ballots yet.")
}

func change(m *motion) string {
	if m.Add {
		return "add " + ui.Addr(m.Subject)
	}
	return "remove " + ui.Addr(m.Subject)
}

func yesCount(bs []ballot) int {
	n := 0
	for _, b := range bs {
		if b.Yes && isController(b.Voter) {
			n++
		}
	}
	return n
}

func askCommand() string {
	return "gnokey maketx call -pkgpath " + selfPath + " -func Request \\\n" +
		"  -args <payee address> -args <amount in ugnot> \\\n" +
		"  -args '<title>' -args '<what it is for>' ..."
}

func requestLink(id int64) string { return link() + ":request/" + itoa(id) }
func motionLink(id int64) string  { return link() + ":motion/" + itoa(id) }

// link is this realm as a gnoweb route: its path without the domain.
func link() string {
	if i := strings.Index(selfPath, "/"); i >= 0 {
		return selfPath[i:]
	}
	return selfPath
}

func parseID(raw string) int64 {
	n, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || n <= 0 {
		return 0
	}
	return n
}
