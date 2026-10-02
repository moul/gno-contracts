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
// gas-metered (3B per query) and a Render that outgrows it stops answering
// instead of slowing down. At the caps a page reads its 25 records, one lookup
// per URL it may mark flagged (each row's main RPC on the index; the zone's
// RPC and gnoweb on its page), the zone serving this chain for the printed
// command, the curators, and a few index nodes. Escaping free text is
// what dominates: about 97k gas a character on a node, so a page of full-length
// fields costs on the order of a billion, still under the ceiling.
const PageSize = 25

// Render is the whole public surface, three pages: the zone list (official,
// or retired with ?status=retired), one zone (?kind= narrows its endpoints),
// and the proposals (pending, or rejected with ?status=rejected). Every list
// takes ?page=.
func Render(path string) string {
	req := realmpath.Parse(path)
	// Exact paths only: a page that also answers zone/x/approved-by-gno-core
	// lends its content to whatever the extra segment claims.
	parts := len(req.PathParts())
	switch req.PathPart(0) {
	case "":
		if parts <= 1 {
			return renderIndex(req)
		}
	case "zone":
		if parts == 2 {
			return renderZone(req.PathPart(1), req)
		}
	case "proposals":
		if parts == 1 {
			return renderProposals(req)
		}
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
		md.Link(strconv.Itoa(reg.ZoneCount(zones.Pending))+" proposal(s) waiting for review", realmURL+":proposals"))
	// Offered only while it can succeed: a link certain to fail is a dead end,
	// and the note says which cap is full (not what would free it: that
	// depends on who acts, and what frees one cap can fill another). A
	// full review queue still takes a curator's proposal, so the link stays,
	// labelled for them.
	propose := func(title string) string {
		return action(title, "ProposeZone",
			"slug", "", "chainID", "", "title", "", "description", "", "kind", "testnet",
			"gnowebURL", "", "rpcURL", "", "genesisURL", "")
	}
	switch {
	case reg.Live() >= zones.MaxZones:
		links = append(links, "the registry is full at "+strconv.Itoa(zones.MaxZones)+" live zones")
	case reg.Live() >= zones.MaxZones-zones.ReservedForReviewers:
		links = append(links, "the registry's last "+strconv.Itoa(zones.ReservedForReviewers)+" places are kept for curators",
			propose("Propose a zone (curators only)"))
	case reg.ZoneCount(zones.Pending) >= zones.MaxPending:
		links = append(links, "the review queue is full at "+strconv.Itoa(zones.MaxPending)+" proposals",
			propose("Propose a zone (curators only, while full)"))
	default:
		links = append(links, propose("Propose a zone"))
	}

	return ui.Join("\n",
		md.H1("Zones"),
		para("A curated registry of gno.land networks and the endpoints that reach them. "+
			"Anybody can propose a zone, and register endpoints on an official one; a curator approves, "+
			"rejects or retires a zone and verifies or flags its endpoints, and every rejection, "+
			"retirement and flag says why, in public."),
		md.H2(heading),
		table,
		pager("", query, pageNum(req, pages), pages),
		para(strings.Join(links, " · ")),
		md.H2("Read it from a node"),
		para("Every list is a plain function, so a node operator or a script can ask for it directly. "+
			"An empty kind or status matches anything."),
		md.CodeBlock(queryCommand(`ListAddresses("`+exampleSlug()+`", "peer", "verified")`)),
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
	case zones.Rejected:
		t = ui.NewTable("zone", "chain id", "proposed by", "why", "")
	default:
		t = ui.NewTable("zone", "chain id", "proposed by", "why")
	}
	for _, z := range reg.ZonePage(status, pageNum(req, pages), PageSize) {
		switch status {
		case zones.Approved:
			verified, total := reg.Count(z.Slug)
			t.Row(zoneLink(z), md.InlineCode(z.ChainID), string(z.Kind), md.InlineCode(z.RPCURL)+rpcFlag(z),
				strconv.Itoa(verified)+" verified of "+strconv.Itoa(total))
		case zones.Pending:
			// Review on the zone page, which shows what is being approved; the
			// Approve link there carries the revision it was rendered from.
			t.Row(zoneLink(z), md.InlineCode(z.ChainID), string(z.Kind), ui.AddrFull(z.Proposer),
				md.Link("review", realmURL+":zone/"+z.Slug))
		case zones.Rejected:
			t.Row(zoneLink(z), md.InlineCode(z.ChainID), ui.AddrFull(z.Proposer), cell(z.Reason),
				action("Remove", "RemoveZone", "slug", z.Slug, "revision", revStr(z)))
		default:
			t.Row(zoneLink(z), md.InlineCode(z.ChainID), ui.AddrFull(z.Proposer), cell(z.Reason))
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
	kind := zones.EndpointKind(req.Query.Get("kind"))
	if kind != "" && !isKind(kind) {
		return notFound("No such endpoint kind.")
	}

	facts := []string{
		md.Bold("chain id") + ": " + md.InlineCode(z.ChainID),
		md.Bold("kind") + ": " + string(z.Kind),
		md.Bold("rpc") + ": " + md.InlineCode(z.RPCURL) + rpcFlag(z),
	}
	if z.GnowebURL != "" {
		facts = append(facts, md.Bold("gnoweb")+": "+urlFact(z, zones.Gnoweb, z.GnowebURL))
	}
	if z.GenesisURL != "" {
		facts = append(facts, md.Bold("genesis")+": "+urlFact(z, "", z.GenesisURL))
	}
	// Addresses in full, here and on every page: an 8+4 shortening is about 50
	// bits, within reach of a vanity grinder who wants to look like a curator.
	facts = append(facts, md.Bold("proposed")+" by "+ui.AddrFull(z.Proposer)+" at block "+strconv.FormatInt(z.ProposedAt, 10))
	if z.EditedBy != "" {
		facts = append(facts, md.Bold("edited")+" by "+ui.AddrFull(z.EditedBy)+" at block "+strconv.FormatInt(z.EditedAt, 10))
	}
	facts = append(facts, md.Bold("revision")+": "+strconv.FormatInt(z.Revision, 10))
	if z.Reviewed() {
		facts = append(facts, md.Bold("last reviewed")+" "+reviewText(z.ReviewedBy, z.ReviewedAt, z.Reason))
	}

	parts := []string{
		md.H1(prose(z.Title)),
		para(statusBadge(z.Status) + " · " + md.InlineCode(z.Slug)),
	}
	if z.Description != "" {
		parts = append(parts, para(prose(z.Description)))
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
	// The revision column is what a verdict or a removal names; a verification
	// also names the zone's revision, shown above.
	t := ui.NewTable("#", "revision", "kind", "address", "label", "status", "registered by")
	for _, e := range reg.EndpointPage(z.Slug, kind, pageNum(req, pages), PageSize) {
		t.Row(
			strconv.FormatInt(e.ID, 10),
			strconv.FormatInt(e.Revision, 10),
			string(e.Kind),
			md.InlineCode(e.Address),
			cell(e.Label),
			endpointStatus(e),
			ui.AddrFull(e.Registrant),
		)
	}
	query := ""
	if kind != "" {
		query = "kind=" + string(kind) + "&"
	}
	empty := "No endpoint registered yet."
	if kind != "" {
		empty = "No " + string(kind) + " endpoint registered yet."
	}
	parts = append(parts, t.OrEmpty(empty), pager("zone/"+z.Slug, query, pageNum(req, pages), pages))

	actions := []string{}
	open := z.Status == zones.Approved || z.Status == zones.Pending
	switch {
	case open && reg.EndpointCount(z.Slug, "") >= zones.MaxEndpointsPerZone:
		actions = append(actions, "endpoints are full at "+strconv.Itoa(zones.MaxEndpointsPerZone))
	case open && reg.EndpointCount(z.Slug, "") >= zones.MaxEndpointsPerZone-zones.ReservedForReviewers:
		actions = append(actions, "the last "+strconv.Itoa(zones.ReservedForReviewers)+" endpoint places are kept for curators",
			action("Register an endpoint (curators only)", "RegisterEndpoint",
				"slug", z.Slug, "kind", "rpc", "addr", "", "label", ""))
	case open && reg.Awaiting(z.Slug) >= zones.MaxUnverifiedPerZone:
		actions = append(actions, "the review queue is full at "+strconv.Itoa(zones.MaxUnverifiedPerZone)+" endpoints awaiting review",
			action("Register an endpoint (curators only, while full)", "RegisterEndpoint",
				"slug", z.Slug, "kind", "rpc", "addr", "", "label", ""))
	case z.Status == zones.Approved:
		actions = append(actions, action("Register an endpoint", "RegisterEndpoint",
			"slug", z.Slug, "kind", "rpc", "addr", "", "label", ""))
	case z.Status == zones.Pending && !curators.Has(z.Proposer) && reg.OwnerCount(z.Slug, z.Proposer) >= zones.MaxEndpointsPerAddress:
		// On a pending zone the proposer is the one gated registrant.
		actions = append(actions, "the proposer has registered "+strconv.Itoa(zones.MaxEndpointsPerAddress)+" endpoints here, the limit per address",
			action("Register an endpoint (curators only)", "RegisterEndpoint",
				"slug", z.Slug, "kind", "rpc", "addr", "", "label", ""))
	case z.Status == zones.Pending:
		actions = append(actions, action("Register an endpoint (proposer or curator)", "RegisterEndpoint",
			"slug", z.Slug, "kind", "rpc", "addr", "", "label", ""))
	}
	// A flood clears in one call, on any zone the call takes (a rejected or
	// retired zone's records are a curator's to remove too). The call reaches
	// every page and every kind, so it is offered only on the unfiltered view,
	// only while it would clear something (the clearable count, no endpoint
	// read), labelled with its real scope, and bounded in time: an endpoint
	// registered after this page was rendered has a later revision and is kept.
	if n := reg.Clearable(z.Slug); kind == "" && n > 0 {
		actions = append(actions, action("Clear "+strconv.Itoa(n)+" never-reviewed endpoint(s) registered through the review queue, all pages and kinds (curators only)", "ClearUnreviewed",
			"slug", z.Slug, "throughRevision", strconv.FormatInt(reg.Revision(), 10)))
	}
	// Every decision carries the revision this page was rendered from, so acting
	// on what you read here fails if the zone changed after you read it.
	rev := revStr(z)
	approve := action("Approve revision "+rev, "ApproveZone", "slug", z.Slug, "revision", rev, "reason", "")
	remove := action("Remove", "RemoveZone", "slug", z.Slug, "revision", rev)
	switch z.Status {
	case zones.Pending:
		actions = append(actions, approve,
			action("Reject", "RejectZone", "slug", z.Slug, "revision", rev, "reason", ""), remove)
		if reg.ZoneCount(zones.Rejected) >= zones.MaxRejected {
			actions = append(actions, "rejecting it drops the zone rejected longest ago, endpoints and all")
		}
	case zones.Approved:
		actions = append(actions, action("Retire", "RetireZone", "slug", z.Slug, "revision", rev, "reason", ""))
		if reg.ZoneCount(zones.Retired) >= zones.MaxRetired {
			actions = append(actions, "retiring it drops the zone retired longest ago, endpoints and all")
		}
	case zones.Rejected, zones.Retired:
		// Back into the live registry only while it has room.
		if reg.Live() < zones.MaxZones {
			actions = append(actions, approve)
		} else {
			actions = append(actions, "approving it waits for a free place: the registry is full at "+strconv.Itoa(zones.MaxZones)+" live zones")
		}
		if z.Status == zones.Rejected {
			actions = append(actions, remove)
		}
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
	} else if digits := strings.TrimPrefix(raw, "+"); digits != "" && strings.Trim(digits, "0123456789") == "" {
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
// A reader pastes this into a shell, so the remote must never carry shell
// syntax. Two layers make sure: the main RPC is validated down to
// <scheme>://<host>[:<port>], host [A-Za-z0-9.-] and port digits, which leaves
// nothing a shell reads as syntax; and it is single-quoted anyway, a quote being
// the one character no URL here can contain, so a later, wider validator does
// not reopen it. The call is built from charset-checked slugs and literals.
func queryCommand(call string) string {
	remote := ""
	if z, ok := reg.SoleApproved(runtime.ChainID()); ok && !rpcFlagged(z) {
		// Not one the same page flags: printing a remote the endpoint table says
		// not to use would contradict the page.
		remote = " -remote '" + z.RPCURL + "'"
	}
	return "gnokey query vm/qeval" + remote + " -data '" + pkgPath + "." + call + "'"
}

// exampleSlug is the zone the index's example asks for peers of: the one
// serving the chain this page is read on, when there is exactly one and it
// lists a peer, else onyx (one zone and an index count read).
func exampleSlug() string {
	if z, ok := reg.SoleApproved(runtime.ChainID()); ok && reg.EndpointCount(z.Slug, zones.Peer) > 0 {
		return z.Slug
	}
	return "onyx"
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
	return "[" + cell(z.Title) + "](" + realmURL + ":zone/" + z.Slug + ")"
}

// urlFact shows a zone's URL as its own text, never behind a label, so a
// reader sees where it goes: a proposal's "genesis.json" link could otherwise
// open anything, a pre-filled transaction form included, right under the
// Approve button. Only an approved zone's URLs are links; a proposal's are
// code, to copy and check, not to click.
//
// A URL the zone also lists, under the kind it is shown as, as a flagged
// endpoint is code and marked, never a link: the page does not offer what its
// own endpoint table says not to use. kind is what the URL is shown as, ""
// for the genesis URL, which no endpoint kind lists (flaggedAs).
func urlFact(z zones.Zone, kind zones.EndpointKind, url string) string {
	if kind != "" && flaggedAs(z, kind, url) {
		return md.InlineCode(url) + " ⚠️ flagged"
	}
	if z.Status == zones.Approved {
		return md.Link(url, url)
	}
	return md.InlineCode(url)
}

// prose and cell escape a caller's free text for a sentence and a table cell,
// plus what ui.Inline and ui.Cell leave alone: gnoweb turns an @name, and a
// bare g1 address after a space or at the start, into a user-profile link with
// an icon, so "run by @gnocore" or "run by g1…" would vouch for an account the
// registrant chose.
func prose(s string) string { return escapeMentions(ui.Inline(s)) }

func cell(s string) string { return escapeMentions(ui.Cell(s)) }

// escapeMentions backslash-escapes every @, and writes the 1 of every g1 as a
// character reference. It runs after ui.Inline or ui.Cell, which escape every
// & the caller typed, so the only reference in the output is this one; goldmark
// decodes it back to "1" after the mention parser has looked and not matched.
//
// One pass, and none at all when there is nothing to escape: it runs on every
// free-text field of every page.
func escapeMentions(s string) string {
	if !strings.Contains(s, "@") && !strings.Contains(s, "g1") {
		return s
	}
	// Copy the runs between matches in one piece each: a byte at a time costs a
	// native call per byte, every page, on text a stranger chose.
	var b strings.Builder
	n, last := len(s), 0
	for i := 0; i < n; i++ {
		switch {
		case s[i] == '@':
			b.WriteString(s[last:i])
			b.WriteString("\\@")
			last = i + 1
		case s[i] == 'g' && i+1 < n && s[i+1] == '1':
			b.WriteString(s[last:i])
			b.WriteString("g&#49;")
			i++
			last = i + 1
		}
	}
	b.WriteString(s[last:])
	return b.String()
}

// rpcFlag marks a zone's main RPC when the endpoint table flags it, so the
// table, the zone page and the printed command never disagree.
func rpcFlag(z zones.Zone) string {
	if rpcFlagged(z) {
		return " ⚠️ flagged"
	}
	return ""
}

func rpcFlagged(z zones.Zone) bool { return flaggedAs(z, zones.RPC, z.RPCURL) }

// flaggedAs reports whether a URL the page shows as a kind (the main RPC as
// rpc, the gnoweb URL as gnoweb) is listed under that kind and flagged. Only
// that kind's verdict counts. A listing under another kind is anybody's to
// make on an approved zone, so letting its flag mark the zone's own URL would
// let a stranger's mis-kinded entry, flagged as mis-kinded, mark an official
// URL; a curator who means the zone's URL flags it under its own kind. The
// lookup compares in Canonical form, which reads an rpc tcp:// as the http://
// gnokey dials, so either spelling finds the other.
func flaggedAs(z zones.Zone, shown zones.EndpointKind, url string) bool {
	e, ok := reg.EndpointByAddress(z.Slug, shown, url)
	return ok && e.Status == zones.Flagged
}

func revStr(z zones.Zone) string { return strconv.FormatInt(z.Revision, 10) }

func isKind(k zones.EndpointKind) bool {
	for _, x := range zones.EndpointKinds() {
		if k == x {
			return true
		}
	}
	return false
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
		s += ": " + cell(e.Reason)
	}
	if e.ReviewedBy != "" {
		s += " (" + ui.AddrFull(e.ReviewedBy) + ", block " + strconv.FormatInt(e.ReviewedAt, 10) + ")"
	}
	return s
}

func reviewText(by address, at int64, reason string) string {
	s := "by " + ui.AddrFull(by) + " at block " + strconv.FormatInt(at, 10)
	if reason != "" {
		s += ": " + prose(reason)
	}
	return s
}

func curatorList() string {
	out := []string{}
	for _, a := range Curators() {
		out = append(out, ui.AddrFull(a))
	}
	return strings.Join(out, ", ")
}
