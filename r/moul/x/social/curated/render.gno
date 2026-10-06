package curated

import (
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/moul/kit/num/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/txlink/v0"
	cu "gno.land/p/moul/x/social/curated/v0"
)

// Render routes two views: the list itself, and one entry.
//
// A key never contains a slash, so "entry/<key>" is a prefix strip rather than
// a path element that would have to be rejoined.
func Render(path string) string {
	req := realmpath.Parse(path)

	switch {
	case strings.HasPrefix(req.Path, "entry/"):
		return renderEntry(strings.TrimPrefix(req.Path, "entry/"))
	case req.Path == "":
		return renderIndex()
	default:
		return md.H1("Not found") + "No such view: " + ui.Inline(req.Path)
	}
}

func renderIndex() string {
	out := md.H1("Curated")
	out += "A list you pay to be on, and can be paid for getting somebody off. " +
		"The deposit does not make an entry good: it makes a bad one expensive " +
		"to leave standing, because anybody who disagrees can put the same " +
		"amount at risk and take it.\n\n"

	open := list.Challenged()

	t := ui.NewTable("on the list", "open challenges", "deposit", "window", "locked", "credited")
	t.Row(
		strconv.Itoa(list.Count()),
		strconv.Itoa(len(open)),
		num.GNOTf(Deposit),
		strconv.FormatInt(ChallengeBlocks, 10)+" blocks",
		num.GNOTf(list.Locked()),
		num.GNOTf(list.Owed()),
	)
	out += t.String()

	out += md.H2("The list")
	out += listing(list.Listed())
	out += "\n" + md.Link("➕ Apply for "+num.GNOTf(Deposit), applyURL()) + "\n"

	if len(open) > 0 {
		out += md.H2("Open challenges")
		out += challengeTable(open)
	}

	out += md.H2("How it works")
	out += md.BulletList([]string{
		"**Apply** locks " + num.GNOTf(Deposit) + " and lists the entry immediately. " +
			"There is no application period in v0.",
		"**Challenge** matches that entry's deposit with a bond and opens a vote " +
			"for " + strconv.FormatInt(ChallengeBlocks, 10) + " blocks. An owner cannot challenge their own entry.",
		"**Vote** is one address, one vote, unweighted. An address is free, so read " +
			"a resolution as nobody with a stake objecting, never as a verdict.",
		"**Resolve** can be called by anyone once the window closes. A majority to " +
			"keep credits the owner the bond; otherwise the challenger takes the bond " +
			"and the deposit. A tie keeps the entry, so a challenge that convinced " +
			"nobody loses its bond.",
		"**Voters are paid nothing** in v0, which is the first thing to fix: the only " +
			"two addresses with a reason to vote are the ones with money on the outcome.",
		"**Nothing is ever sent to you.** Every payout is a credit, and " +
			md.InlineCode("Withdraw()") + " collects it.",
	})

	return out
}

func renderEntry(key string) string {
	e, ok := list.Get(key)
	if !ok {
		return md.H1("Curated") + "No entry named " + ui.Inline(key)
	}

	out := md.H1(ui.Inline(e.Key))
	out += md.Blockquote(ui.Inline(e.Description)) + "\n"
	// ShortN truncates without escaping and md.Link escapes what it is given:
	// ui.Inline here would escape twice and render the backslashes.
	out += md.Link(ui.ShortN(e.URL, 60, 0), e.URL) + "\n\n"

	t := ui.NewTable("owner", "deposit", "listed at", "state")
	t.Row(
		ui.Addr(e.Owner),
		num.GNOTf(e.Deposit),
		"block "+strconv.FormatInt(e.At, 10),
		e.State.String(),
	)
	out += t.String()

	c, challenged := list.ChallengeOf(e.Key)
	switch {
	case challenged:
		out += md.H2("Under challenge")
		out += challengeTable([]*cu.Entry{e})
		if c.Open(runtime.ChainHeight()) {
			out += "\n" + ui.Action("👍 Keep", "Vote", "key", e.Key, "keep", "true") +
				" · " + ui.Action("👎 Remove", "Vote", "key", e.Key, "keep", "false") + "\n"
		} else {
			out += "\n" + ui.Action("⚖️ Resolve", "Resolve", "key", e.Key) +
				" · the window has closed and anyone can settle it\n"
		}
	case e.Live():
		out += "\n" + md.Link("🚩 Challenge for "+num.GNOTf(e.Deposit), challengeURL(e.Key, e.Deposit)) +
			" · " + ui.Action("🗑 Unlist", "Unlist", "key", e.Key) + "\n"
	default:
		out += "\n" + ui.Empty("Off the list. The key is free to apply for again.")
		out += md.Link("➕ Apply for "+num.GNOTf(Deposit), applyURL()) + "\n"
	}

	return out
}

// listing renders the entries as the list itself: the key links to its page,
// the description links to the thing it describes.
func listing(entries []*cu.Entry) string {
	if len(entries) == 0 {
		return ui.Empty("Nothing is on the list yet.")
	}
	t := ui.NewTable("key", "what", "link", "owner", "since", "state")
	for _, e := range entries {
		mark := ""
		if e.State == cu.StateChallenged {
			mark = " 🚩"
		}
		t.Row(
			// A key is charset-validated, so md.Link's escaping is the whole
			// story for it. A description is not: md.Link escapes markdown
			// but NOT the pipe, which in a cell would open a column, so the
			// description is never a link title here. Cut first with ShortN,
			// which does not escape, then escape once with ui.Cell.
			md.Link(ui.ShortN(e.Key, 32, 0), entryURL(e.Key)),
			ui.Cell(ui.ShortN(e.Description, 48, 0)),
			md.Link("↗", e.URL),
			ui.Addr(e.Owner),
			"block "+strconv.FormatInt(e.At, 10),
			e.State.String()+mark,
		)
	}
	return t.String()
}

// challengeTable renders the open challenge against each of entries. An entry
// with none is skipped rather than shown blank.
func challengeTable(entries []*cu.Entry) string {
	t := ui.NewTable("entry", "challenger", "bond", "keep", "remove", "voting closes")
	now := runtime.ChainHeight()
	for _, e := range entries {
		c, ok := list.ChallengeOf(e.Key)
		if !ok {
			continue
		}
		closes := "block " + strconv.FormatInt(c.Deadline, 10)
		if !c.Open(now) {
			closes = "closed, awaiting `Resolve`"
		}
		t.Row(
			md.Link(ui.ShortN(e.Key, 32, 0), entryURL(e.Key)),
			ui.Addr(c.Challenger),
			num.GNOTf(c.Bond),
			strconv.FormatInt(c.Keep, 10),
			strconv.FormatInt(c.Remove, 10),
			closes,
		)
	}
	return t.OrEmpty("No challenge is open.")
}

// entryURL is the gnoweb path of one entry's page.
//
// The chain domain is the first element of a package path and a gnoweb path is
// the rest of it, so this is a prefix strip and not a hostname to hardcode.
func entryURL(key string) string {
	path := realmPath
	if i := strings.Index(path, "/"); i >= 0 {
		path = path[i:]
	}
	return path + ":entry/" + key
}

// applyURL is the Apply form with the deposit already attached, so a reader
// never has to work out what -send should say.
func applyURL() string {
	return txlink.NewLink("Apply").SetSend(send(Deposit)).URL()
}

// challengeURL is the same for Challenge, carrying that entry's own bond.
func challengeURL(key string, bond int64) string {
	return txlink.NewLink("Challenge").AddArgs("key", key).SetSend(send(bond)).URL()
}

func send(amount int64) string { return strconv.FormatInt(amount, 10) + Denom }
