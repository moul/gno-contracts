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

// Render is the whole public surface, three pages: the official list, one zone,
// and the proposals.
func Render(path string) string {
	req := realmpath.Parse(path)
	switch req.PathPart(0) {
	case "":
		return renderIndex()
	case "zone":
		return renderZone(req.PathPart(1))
	case "proposals":
		return renderProposals()
	default:
		return md.H1("Not found") + ui.Empty("No such page.")
	}
}

func renderIndex() string {
	official := ui.NewTable("zone", "chain id", "kind", "rpc", "endpoints")
	for _, z := range reg.Zones(zones.ZoneFilter{Status: zones.Approved}) {
		verified, total := reg.Count(z.Slug)
		official.Row(
			zoneLink(z),
			md.InlineCode(z.ChainID),
			string(z.Kind),
			md.InlineCode(z.RPCURL),
			strconv.Itoa(verified)+" verified of "+strconv.Itoa(total),
		)
	}

	retired := ui.NewTable("zone", "chain id", "why")
	for _, z := range reg.Zones(zones.ZoneFilter{Status: zones.Retired}) {
		retired.Row(zoneLink(z), md.InlineCode(z.ChainID), ui.Cell(z.Reason))
	}
	retiredSection := ""
	if retired.Len() > 0 {
		retiredSection = md.H2("Retired") + "\n" + retired.String()
	}

	pending := len(reg.Zones(zones.ZoneFilter{Status: zones.Pending}))
	return ui.Join("\n",
		md.H1("Zones"),
		para("A curated registry of gno.land networks and the endpoints that reach them. "+
			"Anybody can propose a zone or register an endpoint; a curator approves, rejects, "+
			"verifies or flags it, and every decision carries a public reason."),
		md.H2("Official"),
		official.OrEmpty("No official zone yet."),
		retiredSection,
		para(md.Link(strconv.Itoa(pending)+" proposal(s) waiting for review", realmURL+":proposals")+
			" · "+ui.Action("Propose a zone", "ProposeZone",
			"slug", "", "chainID", "", "title", "", "description", "", "kind", "testnet",
			"gnowebURL", "", "rpcURL", "", "genesisURL", "")),
		md.H2("Read it from a node"),
		para("Every list is a plain function, so a node operator or a script can ask for it directly. "+
			"An empty argument matches anything."),
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

func renderZone(slug string) string {
	z, ok := reg.Zone(slug)
	if !ok {
		return md.H1("Not found") + ui.Empty("No such zone.")
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

	listed := false
	for _, k := range zones.EndpointKinds() {
		t := ui.NewTable("#", "address", "label", "status", "registered by")
		for _, e := range reg.Endpoints(zones.EndpointFilter{Zone: z.Slug, Kind: k}) {
			t.Row(
				strconv.FormatInt(e.ID, 10),
				md.InlineCode(e.Address),
				ui.Cell(e.Label),
				endpointStatus(e),
				ui.Addr(e.Registrant),
			)
		}
		if t.Len() > 0 {
			listed = true
			parts = append(parts, md.H3(string(k)), t.String())
		}
	}
	if !listed {
		parts = append(parts, ui.Empty("No endpoint registered yet."))
	}

	actions := []string{}
	if z.Status == zones.Pending || z.Status == zones.Approved {
		actions = append(actions, ui.Action("Register an endpoint", "RegisterEndpoint",
			"slug", z.Slug, "kind", "rpc", "addr", "", "label", ""))
	}
	switch z.Status {
	case zones.Pending:
		actions = append(actions,
			ui.Action("Approve", "ApproveZone", "slug", z.Slug, "reason", ""),
			ui.Action("Reject", "RejectZone", "slug", z.Slug, "reason", ""))
	case zones.Approved:
		actions = append(actions, ui.Action("Retire", "RetireZone", "slug", z.Slug, "reason", ""))
	case zones.Rejected, zones.Retired:
		actions = append(actions, ui.Action("Approve", "ApproveZone", "slug", z.Slug, "reason", ""))
	}
	parts = append(parts,
		para(strings.Join(actions, " · ")),
		md.CodeBlock(queryCommand(`GetZone("`+z.Slug+`")`)),
		para(md.Link("All zones", realmURL)),
	)
	return ui.Join("\n", parts...)
}

func renderProposals() string {
	pending := ui.NewTable("zone", "chain id", "kind", "proposed by", "review")
	for _, z := range reg.Zones(zones.ZoneFilter{Status: zones.Pending}) {
		pending.Row(
			zoneLink(z),
			md.InlineCode(z.ChainID),
			string(z.Kind),
			ui.Addr(z.Proposer),
			ui.Action("Approve", "ApproveZone", "slug", z.Slug, "reason", "")+" · "+
				ui.Action("Reject", "RejectZone", "slug", z.Slug, "reason", ""),
		)
	}
	rejected := ui.NewTable("zone", "chain id", "proposed by", "why")
	for _, z := range reg.Zones(zones.ZoneFilter{Status: zones.Rejected}) {
		rejected.Row(zoneLink(z), md.InlineCode(z.ChainID), ui.Addr(z.Proposer), ui.Cell(z.Reason))
	}
	return ui.Join("\n",
		md.H1("Proposals"),
		para("Zones somebody proposed and no curator has approved. Only an approved zone is official."),
		md.H2("Pending"),
		pending.OrEmpty("Nothing waiting for review."),
		md.H2("Rejected"),
		rejected.OrEmpty("Nothing rejected."),
		para(md.Link("All zones", realmURL)),
	)
}

// queryCommand is the gnokey line that evaluates call against this realm.
//
// The remote is looked up in the registry itself, by the chain id this realm is
// running on, so the command a reader copies points at the chain they are
// reading. A chain the registry does not list gets no -remote, rather than a
// guessed one.
//
// The remote is single-quoted because a reader pastes this into a shell, and a
// URL may legally carry ; & # $, which a shell reads as syntax: an approved
// zone whose RPC ended in ;id;# would otherwise run id on every reader's
// machine. A single quote cannot occur inside it, because the URL validator
// refuses one, so the quoting cannot be closed from within. The call is built
// here from charset-checked slugs and literals only.
func queryCommand(call string) string {
	remote := ""
	for _, z := range reg.Zones(zones.ZoneFilter{Status: zones.Approved}) {
		if z.ChainID == runtime.ChainID() {
			remote = " -remote '" + z.RPCURL + "'"
			break
		}
	}
	return "gnokey query vm/qeval" + remote + " -data '" + "gno.land" + realmURL + "." + call + "'"
}

// para is one paragraph as a Join part. Not md.Paragraph, whose trailing blank
// line plus Join's separator makes two in a row, which an example cannot pin.
func para(s string) string { return s + "\n" }

func zoneLink(z zones.Zone) string {
	return md.Link(z.Title, realmURL+":zone/"+z.Slug)
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
