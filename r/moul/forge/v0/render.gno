package forge

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"

	fg "gno.land/p/moul/forge/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/txlink/v0"
)

// pageSize bounds every listing: a Render that walks unbounded state is a
// Render that eventually stops rendering.
const pageSize = 20

// Render routes gnoweb paths:
//
//	/                          the forge: every repo
//	/<ns>/<name>               repo overview
//	/<ns>/<name>/log           the full reference log (?page=N)
//	/<ns>/<name>/issues        issues (?page=N)
//	/<ns>/<name>/issues/<id>   one issue and its replies
//	/<ns>/<name>/changes       change requests (?page=N)
//	/<ns>/<name>/changes/<id>  one change, its reviews and its replies
//	/help                      what this realm is and how to call it
func Render(path string) string {
	req := realmpath.Parse(path)
	parts := req.PathParts()
	page := pageOf(req)

	switch {
	case len(parts) == 0 || parts[0] == "":
		return renderHome()
	case len(parts) == 1 && parts[0] == "help":
		return renderHelp()
	case len(parts) < 2:
		return notFound("no such page")
	}

	id := parts[0] + "/" + parts[1]
	r := f.Repo(id)
	if r == nil {
		return notFound("no repo " + md.InlineCode(id))
	}
	switch {
	case len(parts) == 2:
		return renderRepo(r)
	case len(parts) == 3 && parts[2] == "log":
		return renderLog(r, page)
	case len(parts) == 3 && parts[2] == "issues":
		return renderIssues(r, page)
	case len(parts) == 3 && parts[2] == "changes":
		return renderChanges(r, page)
	case len(parts) == 4 && parts[2] == "issues":
		return renderIssue(r, parts[3])
	case len(parts) == 4 && parts[2] == "changes":
		return renderChange(r, parts[3])
	}
	return notFound("no such page")
}

func renderHome() string {
	var b strings.Builder
	b.WriteString(md.H1("Forge"))
	b.WriteString("\nAn on-chain software forge. The objects stay in git; the chain keeps the part a forge is trusted for: which object a ref points at, in what order, on whose authority, and what was reviewed before it moved.\n")
	b.WriteString("\n**Repos:** " + strconv.Itoa(f.Size()) + "\n")

	if f.Size() == 0 {
		b.WriteString("\nNothing here yet. " + link("Create the first repo", txlink.Call("CreateRepo")) + "\n")
	} else {
		b.WriteString("\n| repo | refs | issues | changes | log |\n")
		b.WriteString("| --- | ---: | ---: | ---: | ---: |\n")
		f.IterateRepos(0, pageSize, func(r *fg.Repo) bool {
			b.WriteString("| " + link(r.ID, repoURL(r.ID)) + " | " +
				strconv.Itoa(r.RefCount()) + " | " +
				strconv.Itoa(r.OpenIssueCount()) + "/" + strconv.Itoa(r.IssueCount()) + " | " +
				strconv.Itoa(r.OpenChangeCount()) + "/" + strconv.Itoa(r.ChangeCount()) + " | " +
				strconv.Itoa(r.LogSize()) + " |\n")
			return false
		})
	}
	b.WriteString("\n" + link("Create a repo", txlink.Call("CreateRepo")) + " · " +
		link("How it works", base()+":help") + "\n")
	return b.String()
}

func renderRepo(r *fg.Repo) string {
	var b strings.Builder
	b.WriteString(md.H1(r.ID))
	if r.Description != "" {
		b.WriteString("\n" + md.EscapeText(r.Description) + "\n")
	}
	if r.Archived {
		b.WriteString("\n**Archived.** No further writes are accepted.\n")
	}

	facts := []string{
		"**Default ref:** " + md.InlineCode(r.DefaultRef) + " → " + oidCode(refOID(r, r.DefaultRef)),
		"**Merge policy:** " + strconv.Itoa(r.RequiredApprovals) + " writer approval(s), self-approval " + onOff(r.AllowSelfApproval),
		"**Members:** " + strconv.Itoa(r.MemberCount()),
		"**Log head:** " + md.InlineCode(shortDigest(r.LogHead())),
	}
	if r.ParentID != "" {
		facts = append(facts, "**Forked from:** "+link(r.ParentID, repoURL(r.ParentID)))
	}
	if len(r.Mirrors) > 0 {
		facts = append(facts, "**Fetch from:** "+md.InlineCode(r.Mirrors[0])+mirrorRest(r.Mirrors))
	} else {
		facts = append(facts, "**Fetch from:** no mirror declared: the objects are wherever the maintainers keep them")
	}
	b.WriteString("\n" + md.BulletList(facts))

	b.WriteString("\n" + md.H2("Refs"))
	if r.RefCount() == 0 {
		b.WriteString("\nNo ref has ever been recorded.\n")
	} else {
		var refs []string
		r.IterateRefs(func(ref *fg.Ref) bool {
			refs = append(refs, md.InlineCode(ref.Name)+" → "+oidCode(ref.OID)+" · block "+strconv.FormatInt(ref.UpdatedAt, 10)+" · "+userLink(ref.UpdatedBy))
			return false
		})
		b.WriteString("\n" + md.BulletList(refs))
	}

	b.WriteString("\n" + md.H2("Recent log"))
	b.WriteString("\n" + logList(r, 0, 5))
	b.WriteString("\n" + link("Full log, "+strconv.Itoa(r.LogSize())+" entries", repoURL(r.ID)+"/log") + "\n")

	b.WriteString("\n" + md.H2("Open change requests"))
	b.WriteString("\n" + changeList(r, 0, 5, true))
	b.WriteString("\n" + link("All changes, "+strconv.Itoa(r.ChangeCount())+" total", repoURL(r.ID)+"/changes") + " · " +
		link("Propose a change", txlink.Call("OpenChange", "repoID", r.ID)) + "\n")

	b.WriteString("\n" + md.H2("Open issues"))
	b.WriteString("\n" + issueList(r, 0, 5, true))
	b.WriteString("\n" + link("All issues, "+strconv.Itoa(r.IssueCount())+" total", repoURL(r.ID)+"/issues") + " · " +
		link("Open an issue", txlink.Call("OpenIssue", "repoID", r.ID)) + "\n")
	return b.String()
}

func renderLog(r *fg.Repo, page int) string {
	var b strings.Builder
	b.WriteString(md.H1(r.ID + ": reference log"))
	b.WriteString("\nAppend-only and hash-chained: every entry commits to the one before it, so pinning the head digest anywhere off chain pins this whole history.\n")
	b.WriteString("\n**Head:** " + md.InlineCode(shortDigest(r.LogHead())) + " · **Entries:** " + strconv.Itoa(r.LogSize()) + "\n")
	b.WriteString("\n" + logList(r, page*pageSize, pageSize))
	b.WriteString("\n" + pager(r.LogSize(), page, repoURL(r.ID)+"/log"))
	return b.String()
}

func renderIssues(r *fg.Repo, page int) string {
	var b strings.Builder
	b.WriteString(md.H1(r.ID + ": issues"))
	b.WriteString("\n**Open:** " + strconv.Itoa(r.OpenIssueCount()) + " / " + strconv.Itoa(r.IssueCount()) + "\n")
	b.WriteString("\n" + issueList(r, page*pageSize, pageSize, false))
	b.WriteString("\n" + pager(r.IssueCount(), page, repoURL(r.ID)+"/issues"))
	b.WriteString("\n" + link("Open an issue", txlink.Call("OpenIssue", "repoID", r.ID)) + "\n")
	return b.String()
}

func renderIssue(r *fg.Repo, raw string) string {
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return notFound("bad issue id")
	}
	i := r.Issue(id)
	if i == nil {
		return notFound("no issue " + raw)
	}

	var b strings.Builder
	b.WriteString(md.H1("#" + raw + " " + md.EscapeText(i.Title)))
	b.WriteString("\n" + state(i.Open, "open", "closed") + " · opened at block " + strconv.FormatInt(i.CreatedAt, 10) + " by " + userLink(i.Author) + "\n")
	if len(i.Labels) > 0 {
		b.WriteString("\n**Labels:** " + codeList(i.Labels) + "\n")
	}
	if i.Body != "" {
		b.WriteString("\n" + md.EscapeText(i.Body) + "\n")
	}
	b.WriteString("\n" + md.H2("Replies ("+strconv.Itoa(i.CommentCount())+")"))
	if i.CommentCount() == 0 {
		b.WriteString("\nNone yet.\n")
	} else {
		var items []string
		i.IterateComments(0, pageSize, func(c *fg.Comment) bool {
			items = append(items, userLink(c.Author)+" at block "+strconv.FormatInt(c.CreatedAt, 10)+": "+md.EscapeText(c.Body))
			return false
		})
		b.WriteString("\n" + md.BulletList(items))
	}
	b.WriteString("\n" + link("Reply", txlink.Call("CommentIssue", "repoID", r.ID, "issueID", raw)) + " · " +
		link("Close", txlink.Call("CloseIssue", "repoID", r.ID, "issueID", raw)) + " · " +
		link("Back to issues", repoURL(r.ID)+"/issues") + "\n")
	return b.String()
}

func renderChanges(r *fg.Repo, page int) string {
	var b strings.Builder
	b.WriteString(md.H1(r.ID + ": change requests"))
	b.WriteString("\n**Open:** " + strconv.Itoa(r.OpenChangeCount()) + " / " + strconv.Itoa(r.ChangeCount()) + "\n")
	b.WriteString("\n" + changeList(r, page*pageSize, pageSize, false))
	b.WriteString("\n" + pager(r.ChangeCount(), page, repoURL(r.ID)+"/changes"))
	b.WriteString("\n" + link("Propose a change", txlink.Call("OpenChange", "repoID", r.ID)) + "\n")
	return b.String()
}

func renderChange(r *fg.Repo, raw string) string {
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return notFound("bad change id")
	}
	c := r.Change(id)
	if c == nil {
		return notFound("no change " + raw)
	}

	var b strings.Builder
	b.WriteString(md.H1("!" + raw + " " + md.EscapeText(c.Title)))
	b.WriteString("\n**" + c.State + "** · opened at block " + strconv.FormatInt(c.CreatedAt, 10) + " by " + userLink(c.Author) + "\n")

	src := "this repo"
	if c.SourceRepo != "" {
		src = md.InlineCode(c.SourceRepo)
	}
	facts := []string{
		"**Head:** " + oidCode(c.HeadOID) + " (from " + src + refSuffix(c.SourceRef) + ")",
		"**Target:** " + md.InlineCode(c.TargetRef) + " → " + oidCode(refOID(r, c.TargetRef)),
		"**Approvals:** " + strconv.Itoa(r.CountApprovals(c)) + " of " + strconv.Itoa(r.RequiredApprovals) + " required",
		"**Blocking:** " + strconv.Itoa(r.CountBlocking(c)),
	}
	if c.State == fg.StateMerged {
		facts = append(facts, "**Merged:** "+oidCode(c.MergedOID)+" at block "+strconv.FormatInt(c.MergedAt, 10)+" by "+userLink(c.MergedBy))
	}
	b.WriteString("\n" + md.BulletList(facts))
	if c.Body != "" {
		b.WriteString("\n" + md.EscapeText(c.Body) + "\n")
	}

	b.WriteString("\n" + md.H2("Reviews ("+strconv.Itoa(c.ReviewCount())+")"))
	if c.ReviewCount() == 0 {
		b.WriteString("\nNone yet.\n")
	} else {
		var items []string
		c.IterateReviews(func(rv *fg.Review) bool {
			line := userLink(rv.Reviewer) + ": **" + rv.Verdict + "** on " + oidCode(rv.OID)
			if c.Stale(rv) {
				line += " (stale: the head moved since)"
			}
			if rv.Body != "" {
				line += ": " + md.EscapeText(rv.Body)
			}
			items = append(items, line)
			return false
		})
		b.WriteString("\n" + md.BulletList(items))
	}

	b.WriteString("\n" + md.H2("Replies ("+strconv.Itoa(c.CommentCount())+")"))
	if c.CommentCount() == 0 {
		b.WriteString("\nNone yet.\n")
	} else {
		var items []string
		c.IterateComments(0, pageSize, func(cm *fg.Comment) bool {
			items = append(items, userLink(cm.Author)+" at block "+strconv.FormatInt(cm.CreatedAt, 10)+": "+md.EscapeText(cm.Body))
			return false
		})
		b.WriteString("\n" + md.BulletList(items))
	}

	b.WriteString("\n" + link("Review", txlink.Call("ReviewChange", "repoID", r.ID, "changeID", raw, "verdict", "approve")) + " · " +
		link("Reply", txlink.Call("CommentChange", "repoID", r.ID, "changeID", raw)) + " · " +
		link("Merge", txlink.Call("MergeChange", "repoID", r.ID, "changeID", raw, "expectedTargetOID", refOID(r, c.TargetRef))) + " · " +
		link("Back to changes", repoURL(r.ID)+"/changes") + "\n")
	return b.String()
}

func renderHelp() string {
	return md.H1("Forge: how it works") + `
A forge is trusted for three things git does not do by itself: saying which
object a branch points at, saying who may move it, and recording that a human
reviewed the move. Those three are what lives here. The objects do not: they
stay in git, behind whatever mirror the repo declares.

## The reference log

Every ref move is one entry in an append-only, hash-chained log. An entry names
the ref, the object it left, the object it reached, the actor, the block and the
kind: create, update, force, delete or merge: and commits to the digest of the
entry before it. Pin the head digest anywhere off chain and the entire history
becomes falsifiable.

Moves are compare-and-swap: the caller states the tip it expected, and a stale
expectation aborts instead of overwriting. That is git's --force-with-lease,
except the lease is held by consensus rather than by the server you push to. A
move that skips the discipline is not forbidden, it is recorded as a force.

The chain has no objects, so it cannot check that a new tip descends from the
old one. It does not pretend to. Ordering, attribution and policy are on chain;
ancestry is verified by a client that has the repo.

## Namespaces

A repo id is "namespace/name". A namespace is either a name you hold in
r/sys/users or your own address, so "g1.../forge" works with nothing registered
and "moul/forge" needs the name. Nobody can claim a namespace they do not own,
and a realm passes the same test a user does, by its address.

## Roles

reader < writer < maintainer < admin < owner. Writers move refs, maintainers
force and merge, admins manage members and policy. A role can be held by
another realm, so a repo owned by a DAO is a repo whose merge button is a vote.

## Reviews

Anyone may open an issue or a change request, and anyone may review one: the
spam gate is that you pay for your own bytes. Only a writer's approval counts
toward the merge policy, and an approval names the object it reviewed: push a
new head and it stops counting, with nothing to remember to dismiss.

## Calling it

` + md.CodeBlock(`gnokey maketx call -pkgpath gno.land/r/moul/forge/v0 \
  -func SetRef -send "" -gas-fee 1000000ugnot -gas-wanted 3000000 \
  -args "moul/forge" -args "refs/heads/main" \
  -args "<expected-oid>" -args "<new-oid>" -args "ship it" \
  -broadcast -chainid <chain> -remote <rpc> <key>`) + `
Read paths are free: ` + md.InlineCode("vm/qeval") + ` on ` + md.InlineCode("RefOID") + `, ` +
		md.InlineCode("LogHead") + ` or ` + md.InlineCode("HasRepo") + `, or just browse the routes above.
`
}

// ---------------------------------------------------------------------------
// Fragments
// ---------------------------------------------------------------------------

func logList(r *fg.Repo, offset, count int) string {
	if r.LogSize() == 0 {
		return "No entry yet.\n"
	}
	var items []string
	r.IterateLogReverse(offset, count, func(e *fg.LogEntry) bool {
		line := "`#" + strconv.FormatInt(e.Seq, 10) + "` **" + e.Kind + "** " + md.InlineCode(e.Ref) + " " +
			oidCode(e.OldOID) + " → " + oidCode(e.NewOID) +
			" · block " + strconv.FormatInt(e.Height, 10) + " · " + userLink(e.Actor)
		if e.Kind == fg.KindMerge {
			line += " · change " + link("!"+strconv.FormatInt(e.ChangeID, 10), changeURL(r.ID, e.ChangeID))
		}
		if e.Note != "" {
			line += " · " + md.EscapeText(e.Note)
		}
		items = append(items, line)
		return false
	})
	if len(items) == 0 {
		return "Nothing on this page.\n"
	}
	return md.BulletList(items)
}

func issueList(r *fg.Repo, offset, count int, openOnly bool) string {
	var items []string
	r.IterateIssues(offset, count, func(i *fg.Issue) bool {
		if openOnly && !i.Open {
			return false
		}
		items = append(items, link("#"+strconv.FormatInt(i.ID, 10)+" "+i.Title, issueURL(r.ID, i.ID))+
			" · "+state(i.Open, "open", "closed")+" · "+userLink(i.Author)+
			" · "+strconv.Itoa(i.CommentCount())+" replies")
		return false
	})
	if len(items) == 0 {
		return "None.\n"
	}
	return md.BulletList(items)
}

func changeList(r *fg.Repo, offset, count int, openOnly bool) string {
	var items []string
	r.IterateChanges(offset, count, func(c *fg.Change) bool {
		if openOnly && c.State != fg.StateOpen {
			return false
		}
		items = append(items, link("!"+strconv.FormatInt(c.ID, 10)+" "+c.Title, changeURL(r.ID, c.ID))+
			" · **"+c.State+"** · "+md.InlineCode(c.TargetRef)+
			" · "+strconv.Itoa(r.CountApprovals(c))+"/"+strconv.Itoa(r.RequiredApprovals)+" approvals")
		return false
	})
	if len(items) == 0 {
		return "None.\n"
	}
	return md.BulletList(items)
}

func pager(total, page int, path string) string {
	if total <= pageSize {
		return ""
	}
	out := "Page " + strconv.Itoa(page+1) + " of " + strconv.Itoa((total+pageSize-1)/pageSize) + " · "
	if page > 0 {
		out += link("previous", path+"?page="+strconv.Itoa(page)) + " "
	}
	if (page+1)*pageSize < total {
		out += link("next", path+"?page="+strconv.Itoa(page+2))
	}
	return out + "\n"
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

func base() string {
	return strings.TrimPrefix(unsafe.CurrentRealm().PkgPath(), runtime.ChainDomain())
}

func repoURL(id string) string { return base() + ":" + id }

func issueURL(id string, n int64) string {
	return repoURL(id) + "/issues/" + strconv.FormatInt(n, 10)
}

func changeURL(id string, n int64) string {
	return repoURL(id) + "/changes/" + strconv.FormatInt(n, 10)
}

// link builds a markdown link. Internal targets are realm paths this file
// built, so only the text needs escaping.
func link(text, url string) string { return "[" + md.EscapeText(text) + "](" + url + ")" }

func userLink(a address) string {
	if l := md.UserLink(a.String()); l != "" {
		return l
	}
	return md.InlineCode(a.String())
}

func notFound(why string) string {
	return md.H1("Not found") + "\n" + why + ".\n\n" + link("Back to the forge", base()) + "\n"
}

func state(ok bool, yes, no string) string {
	if ok {
		return "**" + yes + "**"
	}
	return "**" + no + "**"
}

func onOff(b bool) string {
	if b {
		return "allowed"
	}
	return "off"
}

func refOID(r *fg.Repo, name string) string {
	if ref := r.Ref(name); ref != nil {
		return ref.OID
	}
	return ""
}

// oidCode shows the short object id, code-spanned. An empty id renders as
// "(none)": that is a ref being created or deleted, not a zero object.
func oidCode(oid string) string {
	if oid == "" {
		return "(none)"
	}
	if len(oid) > 12 {
		return md.InlineCode(oid[:12])
	}
	return md.InlineCode(oid)
}

func shortDigest(d string) string {
	if d == "" {
		return "(empty log)"
	}
	if len(d) > 16 {
		return d[:16]
	}
	return d
}

func mirrorRest(mirrors []string) string {
	if len(mirrors) < 2 {
		return ""
	}
	return " (+" + strconv.Itoa(len(mirrors)-1) + " more)"
}

func refSuffix(ref string) string {
	if ref == "" {
		return ""
	}
	return " " + md.InlineCode(ref)
}

func codeList(items []string) string {
	out := ""
	for i, it := range items {
		if i > 0 {
			out += " "
		}
		out += md.InlineCode(it)
	}
	return out
}

func pageOf(req *realmpath.Request) int {
	n, err := strconv.Atoi(req.Query.Get("page"))
	if err != nil || n < 1 {
		return 0
	}
	return n - 1
}

func itoa(n int64) string { return strconv.FormatInt(n, 10) }
