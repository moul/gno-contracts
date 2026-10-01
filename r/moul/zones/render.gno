package zones

import (
	"chain/runtime"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/zones/v0"
)

// realmURL is this realm as gnoweb serves it. Absolute, because the path ends in
// /v0 and a relative link would resolve against the parent directory. Not
// derived at runtime: a Render has no cur, and CurrentRealm there is the caller.
// TestRealmURLMatchesTheModule pins it to the module line.
const realmURL = "/r/moul/zones/v0"

// pkgPath is this realm's package path, for the action links.
const pkgPath = "gno.land" + realmURL

// action is a call link to a function of THIS realm, named explicitly.
//
// Not ui.Action: that resolves its target through unsafe.CurrentRealm, which in
// a borrowed Render is the caller, so a realm embedding this page would get
// links that call its own functions. filetests/z_borrowed_render_filetest.gno
// pins it from a caller realm, the only place the difference shows.
func action(title, fn string, args ...string) string {
	return ui.ActionIn(pkgPath, title, fn, args...)
}

// PageSize is how many rows any table here shows at once. Every list is
// paginated and every page reads only its own records, because vm/qrender is
// gas-metered and a Render that outgrows it stops answering instead of slowing
// down. At the registry's caps (256 zones, 512 endpoints on one zone) a zone
// page plus an endpoint page measured about 7.5M gas of the 3B ceiling; see
// zones.Registry.ZonePage.
const PageSize = 25

// Render is the whole public surface, three pages: the zone list (official,
// or retired with ?status=retired), one zone (?kind= narrows its endpoints),
// and the proposals (pending, or rejected with ?status=rejected). Every list
// takes ?page=.
func Render(path string) string {
	req := realmpath.Parse(path)
	switch req.PathPart(0) {
	case "":
		return renderIndex(req)
	case "zone":
		return renderZone(req.PathPart(1), req)
	case "proposals":
		return renderProposals(req)
	}
	return notFound("No such page.")
}

func renderIndex(req *realmpath.Request) string {
	status, heading := zones.Approved, "Official"
	switch req.Query.Get("status") {
	case "", "approved":
	case "retired":
		status, heading = zones.Retired, "Retired"
	default:
		return notFound("No such list.")
	}
	query := ""
	if status == zones.Retired {
		query = "status=retired&"
	}
	table, pages := zoneTable(status, req, "")

	links := []string{}
	if status == zones.Retired {
		links = append(links, md.Link("official zones", realmURL))
	} else if n := reg.ZoneCount(zones.Retired); n > 0 {
		links = append(links, md.Link(strconv.Itoa(n)+" retired zone(s)", realmURL+":?status=retired"))
	}
	links = append(links,
		md.Link(strconv.Itoa(reg.ZoneCount(zones.Pending))+" proposal(s) waiting for review", realmURL+":proposals"),
		action("Propose a zone", "ProposeZone",
			"slug", "", "chainID", "", "title", "", "description", "", "kind", "testnet",
			"gnowebURL", "", "rpcURL", "", "genesisURL", ""))

	return ui.Join("\n",
		md.H1("Zones"),
		para("A curated registry of gno.land networks and the endpoints that reach them. "+
			"Anybody can propose a zone or register an endpoint; a curator approves, rejects, "+
			"retires, verifies or flags it, and every rejection, retirement and flag says why, in public."),
		md.H2(heading),
		table,
		pager("", query, pageNum(req, pages), pages),
		para(strings.Join(links, " · ")),
		md.H2("Read it from a node"),
		para("Every list is a plain function, so a node operator or a script can ask for it directly. "+
			"An empty kind or status matches anything."),
		md.CodeBlock(queryCommand(`ListAddresses("onyx", "peer", "verified")`)),
		md.BulletList([]string{
			md.InlineCode(`ListZones(status, kind)`) + ": `approved` is the official list",
			md.InlineCode(`GetZone(slug)`),
			md.InlineCode(`ListEndpoints(slug, kind, status)`) + ": kind is rpc, gnoweb, seed, peer, indexer, faucet or explorer",
			md.InlineCode(`ListAddresses(slug, kind, status)`) + ": the same, reduced to what a config file wants",
		}),
		para("Curated by "+curatorList()+"."),
	)
}

// zoneTable renders one page of the zones with that status, and returns how
// many pages there are.
func zoneTable(status zones.Status, req *realmpath.Request, empty string) (string, int) {
	pages := pageCount(reg.ZoneCount(status))
	var t *ui.Table
	switch status {
	case zones.Approved:
		t = ui.NewTable("zone", "chain id", "kind", "rpc", "endpoints")
	case zones.Pending:
		t = ui.NewTable("zone", "chain id", "kind", "proposed by", "review")
	default:
		t = ui.NewTable("zone", "chain id", "proposed by", "why")
	}
	for _, z := range reg.ZonePage(status, pageNum(req, pages), PageSize) {
		switch status {
		case zones.Approved:
			verified, total := reg.Count(z.Slug)
			t.Row(zoneLink(z), md.InlineCode(z.ChainID), string(z.Kind), md.InlineCode(z.RPCURL),
				strconv.Itoa(verified)+" verified of "+strconv.Itoa(total))
		case zones.Pending:
			t.Row(zoneLink(z), md.InlineCode(z.ChainID), string(z.Kind), ui.Addr(z.Proposer),
				action("Approve", "ApproveZone", "slug", z.Slug, "reason", "")+" · "+
					action("Reject", "RejectZone", "slug", z.Slug, "reason", ""))
		default:
			t.Row(zoneLink(z), md.InlineCode(z.ChainID), ui.Addr(z.Proposer), ui.Cell(z.Reason))
		}
	}
	if empty == "" {
		empty = "No " + string(status) + " zone yet."
	}
	return t.OrEmpty(empty), pages
}

func renderZone(slug string, req *realmpath.Request) string {
	z, ok := reg.Zone(slug)
	if !ok {
		return notFound("No such zone.")
	}
	kind, err := zones.ParseEndpointKind(req.Query.Get("kind"))
	if err != nil {
		return notFound("No such endpoint kind.")
	}

	facts := []string{
		md.Bold("chain id") + ": " + md.InlineCode(z.ChainID),
		md.Bold("kind") + ": " + string(z.Kind),
		md.Bold("rpc") + ": " + md.InlineCode(z.RPCURL),
	}
	if z.GnowebURL != "" {
		facts = append(facts, md.Bold("gnoweb")+": "+md.Link(z.GnowebURL, z.GnowebURL))
	}
	if z.GenesisURL != "" {
		facts = append(facts, md.Bold("genesis")+": "+md.Link("genesis.json", z.GenesisURL))
	}
	facts = append(facts, md.Bold("proposed")+" by "+ui.Addr(z.Proposer)+" at block "+strconv.FormatInt(z.ProposedAt, 10))
	if z.Reviewed() {
		facts = append(facts, md.Bold("last reviewed")+" "+reviewText(z.ReviewedBy, z.ReviewedAt, z.Reason))
	}

	parts := []string{
		md.H1(ui.Inline(z.Title)),
		para(statusBadge(z.Status) + " · " + md.InlineCode(z.Slug)),
	}
	if z.Description != "" {
		parts = append(parts, para(ui.Inline(z.Description)))
	}
	parts = append(parts, md.BulletList(facts), md.H2("Endpoints"))

	// One link per kind the zone has, from the index counts: no endpoint is
	// read to draw them.
	base := realmURL + ":zone/" + z.Slug
	kinds := []string{}
	if all := reg.EndpointCount(z.Slug, ""); all > 0 {
		kinds = append(kinds, kindLink("all", base, all, kind == ""))
		for _, k := range zones.EndpointKinds() {
			if n := reg.EndpointCount(z.Slug, k); n > 0 {
				kinds = append(kinds, kindLink(string(k), base+"?kind="+string(k), n, kind == k))
			}
		}
		parts = append(parts, para(strings.Join(kinds, " · ")))
	}

	pages := pageCount(reg.EndpointCount(z.Slug, kind))
	t := ui.NewTable("#", "kind", "address", "label", "status", "registered by")
	for _, e := range reg.EndpointPage(z.Slug, kind, pageNum(req, pages), PageSize) {
		t.Row(
			strconv.FormatInt(e.ID, 10),
			string(e.Kind),
			md.InlineCode(e.Address),
			ui.Cell(e.Label),
			endpointStatus(e),
			ui.Addr(e.Registrant),
		)
	}
	query := ""
	if kind != "" {
		query = "kind=" + string(kind) + "&"
	}
	parts = append(parts, t.OrEmpty("No endpoint registered yet."), pager("zone/"+z.Slug, query, pageNum(req, pages), pages))

	actions := []string{}
	if z.Status == zones.Pending || z.Status == zones.Approved {
		actions = append(actions, action("Register an endpoint", "RegisterEndpoint",
			"slug", z.Slug, "kind", "rpc", "addr", "", "label", ""))
	}
	switch z.Status {
	case zones.Pending:
		actions = append(actions,
			action("Approve", "ApproveZone", "slug", z.Slug, "reason", ""),
			action("Reject", "RejectZone", "slug", z.Slug, "reason", ""))
	case zones.Approved:
		actions = append(actions, action("Retire", "RetireZone", "slug", z.Slug, "reason", ""))
	case zones.Rejected, zones.Retired:
		actions = append(actions, action("Approve", "ApproveZone", "slug", z.Slug, "reason", ""))
	}
	parts = append(parts,
		para(strings.Join(actions, " · ")),
		md.CodeBlock(queryCommand(`GetZone("`+z.Slug+`")`)),
		para(md.Link("All zones", realmURL)),
	)
	return ui.Join("\n", parts...)
}

func renderProposals(req *realmpath.Request) string {
	status, heading, other := zones.Pending, "Pending", ""
	switch req.Query.Get("status") {
	case "", "pending":
		if n := reg.ZoneCount(zones.Rejected); n > 0 {
			other = md.Link(strconv.Itoa(n)+" rejected", realmURL+":proposals?status=rejected")
		}
	case "rejected":
		status, heading = zones.Rejected, "Rejected"
		other = md.Link("pending", realmURL+":proposals")
	default:
		return notFound("No such list.")
	}
	query := ""
	if status == zones.Rejected {
		query = "status=rejected&"
	}
	empty := "Nothing waiting for review."
	if status == zones.Rejected {
		empty = "Nothing rejected."
	}
	table, pages := zoneTable(status, req, empty)
	links := []string{}
	if other != "" {
		links = append(links, other)
	}
	links = append(links, md.Link("All zones", realmURL))
	return ui.Join("\n",
		md.H1("Proposals"),
		para("Zones somebody proposed and no curator has approved. Only an approved zone is official."),
		md.H2(heading),
		table,
		pager("proposals", query, pageNum(req, pages), pages),
		para(strings.Join(links, " · ")),
	)
}

// pageCount is how many pages n rows make, at least one.
func pageCount(n int) int {
	pages := n / PageSize
	if n%PageSize != 0 {
		pages++
	}
	if pages < 1 {
		pages = 1
	}
	return pages
}

// pageNum reads ?page= and clamps it into 1..pages: it is a reader's input,
// and ?page=-1 must not render a footer saying "page -1 of 2".
func pageNum(req *realmpath.Request, pages int) int {
	page := 1
	raw := req.Query.Get("page")
	if n, err := strconv.Atoi(raw); err == nil {
		page = n
	} else if raw != "" && strings.Trim(raw, "0123456789") == "" {
		// All digits and still unparseable: a positive number past int. It is
		// past the last page too, so it lands there, as any big number does.
		page = pages
	}
	if page < 1 {
		page = 1
	}
	if page > pages {
		page = pages
	}
	return page
}

// pager links the neighbouring pages of a list, keeping the list's other query
// parameters (query ends in "&" when not empty). One page needs no pager.
func pager(path, query string, page, pages int) string {
	if pages < 2 {
		return ""
	}
	link := func(n int) string { return realmURL + ":" + path + "?" + query + "page=" + strconv.Itoa(n) }
	out := ""
	if page > 1 {
		out += md.Link("previous", link(page-1)) + " · "
	}
	out += "page " + strconv.Itoa(page) + " of " + strconv.Itoa(pages)
	if page < pages {
		out += " · " + md.Link("next", link(page+1))
	}
	return para(out)
}

func kindLink(label, url string, n int, current bool) string {
	text := label + " (" + strconv.Itoa(n) + ")"
	if current {
		return md.Bold(text)
	}
	return md.Link(text, url)
}

func notFound(msg string) string { return md.H1("Not found") + ui.Empty(msg) }

// queryCommand is the gnokey line that evaluates call against this realm.
//
// The remote is looked up in the registry itself, by the chain id this realm is
// running on, so the command a reader copies points at the chain they are
// reading. A chain the registry does not list gets no -remote, rather than a
// guessed one, and so does a chain id two approved zones share (every gnodev
// is "dev"): picking one would be the same guess.
//
// The remote is single-quoted because a reader pastes this into a shell, and a
// URL may legally carry ; & # $, which a shell reads as syntax: an approved
// zone whose RPC ended in ;id;# would otherwise run id on every reader's
// machine. A single quote cannot occur inside it, because the URL validator
// refuses one, so the quoting cannot be closed from within. The call is built
// here from charset-checked slugs and literals only.
func queryCommand(call string) string {
	remote, matches := "", 0
	for _, z := range reg.ZonesByChainID(runtime.ChainID()) {
		if z.Status == zones.Approved {
			remote = " -remote '" + z.RPCURL + "'"
			matches++
		}
	}
	if matches != 1 {
		remote = ""
	}
	return "gnokey query vm/qeval" + remote + " -data '" + pkgPath + "." + call + "'"
}

// para is one paragraph as a Join part. Not md.Paragraph, whose trailing blank
// line plus Join's separator makes two in a row, which an example cannot pin.
func para(s string) string { return s + "\n" }

// zoneLink is a zone's title linking to its page, for a TABLE cell. Built by
// hand rather than with md.Link, whose text escape is for prose and leaves a
// pipe literal, so a title like "Alice|official" would open a column in every
// zone table. ui.Cell escapes the pipe too; the destination is a constant plus
// a slug checked to [a-z0-9-] at write time.
func zoneLink(z zones.Zone) string {
	return "[" + ui.Cell(z.Title) + "](" + realmURL + ":zone/" + z.Slug + ")"
}

func statusBadge(s zones.Status) string {
	switch s {
	case zones.Approved:
		return "✅ " + md.Bold("official")
	case zones.Pending:
		return "⏳ " + md.Bold("pending review")
	case zones.Rejected:
		return "❌ " + md.Bold("rejected")
	case zones.Retired:
		return "⏹️ " + md.Bold("retired")
	}
	return string(s)
}

func endpointStatus(e zones.Endpoint) string {
	s := ""
	switch e.Status {
	case zones.Verified:
		s = "✅ verified"
	case zones.Flagged:
		s = "⚠️ flagged"
	default:
		s = "unverified"
	}
	if e.Reason != "" {
		s += ": " + ui.Cell(e.Reason)
	}
	return s
}

func reviewText(by address, at int64, reason string) string {
	s := "by " + ui.Addr(by) + " at block " + strconv.FormatInt(at, 10)
	if reason != "" {
		s += ": " + ui.Cell(reason)
	}
	return s
}

func curatorList() string {
	out := []string{}
	for _, a := range Curators() {
		out = append(out, ui.Addr(a))
	}
	return strings.Join(out, ", ")
}
