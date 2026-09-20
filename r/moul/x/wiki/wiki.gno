// Package wiki is an open, on-chain encyclopedia: anyone can create and edit
// a page, every edit is a signed revision, and the whole history is public.
//
// It is a thin realm over gno.land/p/moul/x/wiki/v0. The library owns content
// (titles, revisions, wikilinks, categories, diffs, rendering); this realm
// owns authority (who may edit what) and the chain wiring (block height, block
// time, the calling address, transaction links).
//
// The split matters for reading the code: there is no policy in the library
// and no content logic here.
package wiki

import (
	"strings"
	"time"

	"chain/runtime"

	"gno.land/p/moul/addrset/v1"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/txlink/v0"
	"gno.land/p/moul/x/wiki/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ownable/v0"
	"gno.land/p/nt/ufmt/v0"
)

// basePath is this realm's render path. It is a constant rather than a lookup
// so link building stays a pure string operation, and it is asserted against
// the real path by TestBasePathMatchesTheRealm.
const basePath = "/r/moul/x/wiki/v0"

// steward is the address that starts out able to protect, move, blank and
// purge pages. Ownable makes it transferable, so the wiki can be handed to a
// DAO realm without redeploying.
const steward address = "g1manfred47kzduec920z88wfr64ylksmdcedlf5" // @moul

var (
	site    *wiki.Wiki
	Ownable *ownable.Ownable

	// editors may write to semi-protected pages; banned may write nowhere.
	editors addrset.Set
	banned  addrset.Set

	// cooldown is the minimum number of blocks between two writes by the same
	// address, 0 to disable.
	//
	// The storage deposit makes ADDING bytes cost the adder, but it does not
	// make removing them cost anything: the chain refunds released storage to
	// the caller of the transaction that frees it, at the realm's blended
	// deposit rate, not to whoever originally paid (processStorageDeposit in
	// gno.land/pkg/sdk/vm/keeper.go). So replacing a long article with a short
	// one can pay the editor who does it. Blank and Purge are steward-gated
	// for that reason, and this cooldown plus the ban list and the protection
	// levels are what is left for ordinary edits. See #140 Q2.
	cooldown  int64
	lastEdit  avl.Tree // address -> the height of that address's last edit
	editCount int
)

func init() {
	Ownable = ownable.NewWithAddress(steward)
	site = wiki.New(wiki.DefaultRetention, wiki.DefaultMaxBody)
	seed()
}

// Edit creates or updates a page and returns the new revision id.
func Edit(cur realm, title, body, summary string) int {
	caller := cur.Previous().Address()
	assertMayEdit(caller, title)
	rev, err := site.Edit(caller, time.Now(), runtime.ChainHeight(), title, body, summary, false)
	if err != nil {
		panic(err)
	}
	noteEdit(caller)
	return int(rev.ID)
}

// Revert restores an earlier revision of a page as a new revision.
func Revert(cur realm, title string, rev int, summary string) int {
	caller := cur.Previous().Address()
	assertMayEdit(caller, title)
	r, err := site.Revert(caller, time.Now(), runtime.ChainHeight(), title, uint64(rev), summary)
	if err != nil {
		panic(err)
	}
	noteEdit(caller)
	return int(r.ID)
}

// Comment appends a message to a page's discussion and returns its id. Pass
// replyTo = 0 for a new thread, or the id of a top-level message to reply to.
//
// Commenting deliberately ignores the page's protection level: locking an
// article is how a steward stops an edit war, and the discussion is where that
// war is supposed to move. A banned address still cannot comment, and the
// cooldown still applies.
func Comment(cur realm, title, body string, replyTo int) int {
	caller := cur.Previous().Address()
	assertNotBanned(caller)
	c, err := site.Comment(caller, time.Now(), runtime.ChainHeight(), title, body, uint64(replyTo))
	if err != nil {
		panic(err)
	}
	noteEdit(caller)
	return int(c.ID)
}

// HideComment clears one message's body and returns the bytes released. The
// message stays in the thread, marked as removed.
func HideComment(cur realm, title string, id int) int {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	n, err := site.HideComment(title, uint64(id))
	if err != nil {
		panic(err)
	}
	return n
}

// Protect sets a page's edit gate: "open", "semi" or "locked".
func Protect(cur realm, title, level string) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	if err := site.SetProtection(cur.Previous().Address(), time.Now(), runtime.ChainHeight(), title, level); err != nil {
		panic(err)
	}
}

// Move renames a page, keeping its history and leaving a redirect behind.
func Move(cur realm, from, to, reason string) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	if err := site.Move(cur.Previous().Address(), time.Now(), runtime.ChainHeight(), from, to, reason); err != nil {
		panic(err)
	}
}

// Blank replaces a page's content with a tombstone revision. The history stays.
func Blank(cur realm, title, reason string) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	if _, err := site.Blank(cur.Previous().Address(), time.Now(), runtime.ChainHeight(), title, reason); err != nil {
		panic(err)
	}
}

// Purge drops every body this realm still holds for a page and returns the
// number of bytes released. Use it for content that must stop being served
// from realm state; it cannot remove the transactions that wrote it.
func Purge(cur realm, title string) int {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	n, err := site.Purge(title)
	if err != nil {
		panic(err)
	}
	return n
}

// AddEditor lets an address write to semi-protected pages.
func AddEditor(cur realm, addr address) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	editors.Add(addr)
}

// RemoveEditor revokes semi-protected write access.
func RemoveEditor(cur realm, addr address) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	editors.Remove(addr)
}

// Ban stops an address from editing anything.
func Ban(cur realm, addr address) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	banned.Add(addr)
}

// Unban lifts a ban.
func Unban(cur realm, addr address) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	banned.Remove(addr)
}

// SetCooldown sets the minimum number of blocks between two edits by the same
// address; 0 disables it.
func SetCooldown(cur realm, blocks int) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	if blocks < 0 {
		panic("cooldown must not be negative")
	}
	cooldown = int64(blocks)
}

// assertNotBanned is the floor every write shares: the ban list and the
// per-address cooldown.
func assertNotBanned(caller address) {
	if banned.Has(caller) {
		panic("this address is banned from editing")
	}
	if cooldown > 0 {
		if v := lastEdit.Get(caller.String()); v != nil {
			if wait := cooldown - (runtime.ChainHeight() - v.(int64)); wait > 0 {
				panic(ufmt.Sprintf("edit cooldown: wait %d more blocks", wait))
			}
		}
	}
}

// assertMayEdit is the whole authority model of this wiki, in one function.
func assertMayEdit(caller address, title string) {
	assertNotBanned(caller)

	p, err := site.Page(title)
	if err != nil {
		return // a page that does not exist yet is open to anyone
	}
	switch p.Protection {
	case wiki.Locked:
		Ownable.AssertOwnedBy(caller)
	case wiki.SemiProtected:
		if !editors.Has(caller) && !Ownable.OwnedBy(caller) {
			panic("this page is semi-protected: ask a steward for edit access")
		}
	}
}

func noteEdit(caller address) {
	lastEdit.Set(caller.String(), runtime.ChainHeight())
	editCount++
}

// ctx is the render context handed to the library on every read.
func ctx() wiki.Ctx {
	return wiki.Ctx{Base: basePath, Exists: site.Exists}
}

// Render is the whole read surface of the wiki.
//
// Routes:
//
//	                          the front page
//	Title                     an article
//	Title/history[?offset=]   its revisions, newest first
//	Title/raw                 the current source, with its hash
//	Title/rev/<id>            one stored revision
//	Title/diff?from=&to=      a line diff between two revisions
//	Title/talk[?offset=]      the page's discussion
//	Category:Name             a category page and its members
//	Special:AllPages[?ns=]    the page index for a namespace
//	Special:Categories        every category with at least one member
//	Special:RecentChanges     the change feed
//	Special:Backlinks?page=   what links to a page
//	Special:Stats             size and storage cost
func Render(path string) string {
	req := realmpath.Parse(path)
	c := ctx()

	first := req.PathPart(0)
	if first == "" {
		return wiki.RenderIndex(c, site, 20)
	}

	t, err := wiki.ParseTitle(first)
	if err != nil {
		return "400: " + err.Error()
	}
	if t.NS == wiki.NSSpecial {
		return renderSpecial(c, t.Name, req)
	}

	p, perr := site.PageByTitle(t)

	// A category renders its members even with no description page of its
	// own: membership is an index, not a page, so "the page does not exist"
	// would hide every member.
	if t.NS == wiki.NSCategory && req.PathPart(1) == "" {
		if perr != nil {
			p = nil
		}
		return wiki.RenderCategory(c, site, t, p, txlink.Call)
	}
	if perr != nil {
		return wiki.RenderMissing(c, site, t, txlink.Call)
	}

	switch req.PathPart(1) {
	case "":
		// Follow a redirect only for a bare read, so history and source
		// always address the page that was asked for.
		if dest, _, rerr := site.Resolve(first); rerr == nil {
			p = dest
		}
		return wiki.RenderArticle(c, site, p, txlink.Call)

	case "history":
		offset := intParam(req.Query.Get("offset"), 0)
		return wiki.RenderHistory(c, p, offset, 20, txlink.Call)

	case "raw":
		if p.Head() == nil {
			return "404: no revision"
		}
		return wiki.RenderRaw(c, p, p.Head())

	case "rev":
		r := p.Revision(uint64(intParam(req.PathPart(2), 0)))
		if r == nil {
			return "404: no such revision"
		}
		return wiki.RenderRevision(c, p, r)

	case "talk":
		offset := intParam(req.Query.Get("offset"), 0)
		return wiki.RenderTalk(c, site, p, offset, 20, txlink.Call)

	case "diff":
		from := p.Revision(uint64(intParam(req.Query.Get("from"), 0)))
		to := p.Revision(uint64(intParam(req.Query.Get("to"), 0)))
		if from == nil || to == nil {
			return "404: no such revision"
		}
		return wiki.RenderDiff(c, p, from, to)
	}
	return "404: unknown route"
}

func renderSpecial(c wiki.Ctx, name string, req *realmpath.Request) string {
	switch strings.ToLower(name) {
	case "allpages":
		ns := wiki.Namespace(intParam(req.Query.Get("ns"), 0))
		offset := intParam(req.Query.Get("offset"), 0)
		return wiki.RenderAllPages(c, site, ns, offset, 50)
	case "categories":
		return wiki.RenderCategories(c, site)
	case "recentchanges":
		return wiki.RenderRecent(c, site, 50)
	case "backlinks":
		t, err := wiki.ParseTitle(req.Query.Get("page"))
		if err != nil {
			return "400: " + err.Error()
		}
		return wiki.RenderBacklinks(c, site, t)
	case "stats":
		return wiki.RenderStats(c, site) + md.BulletList([]string{
			ufmt.Sprintf("edits since deploy: %d", editCount),
			ufmt.Sprintf("editors on the semi-protected list: %d", editors.Size()),
			ufmt.Sprintf("banned addresses: %d", banned.Size()),
			ufmt.Sprintf("edit cooldown: %d blocks", cooldown),
			ufmt.Sprintf("max comment length: %d bytes", wiki.MaxCommentLen),
			"steward: `" + Ownable.Owner().String() + "`",
		})
	}
	return "404: unknown special page"
}

// intParam parses a decimal parameter, falling back to def. It never panics:
// Render is reached from a URL, and a malformed query must render a page, not
// abort the query.
func intParam(s string, def int) int {
	if s == "" {
		return def
	}
	n := 0
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return def
		}
		n = n*10 + int(s[i]-'0')
	}
	return n
}

// seed writes the pages the wiki starts with, so a fresh deploy renders
// something a reader can follow instead of an empty index.
func seed() {
	pages := []struct{ title, body, summary string }{
		{
			"Gno land",
			"gno.land is a smart-contract platform that runs [[Gno]], a deterministic " +
				"interpretation of Go, on top of [[Tendermint2]].\n\n" +
				"Realms keep their state as live objects rather than as a key-value blob, " +
				"which is what lets this wiki store its articles in the contract itself.\n\n" +
				"[[Category:Chains]]\n",
			"seed",
		},
		{
			"Gno",
			"Gno is the language realms are written in: Go's syntax and semantics, minus " +
				"the sources of non-determinism a chain cannot tolerate.\n\n" +
				"See [[Gno land]].\n\n[[Category:Languages]]\n",
			"seed",
		},
		{
			"Tendermint2",
			"Tendermint2 is the consensus engine under [[Gno land]].\n\n[[Category:Chains]]\n",
			"seed",
		},
		{
			"Help:Editing",
			"Anyone may create or edit a page by calling `Edit(title, body, summary)`.\n\n" +
				"The body is markdown with two additions:\n\n" +
				"- `[[Target]]` or `[[Target|label]]` links to another page. A link to a " +
				"page that does not exist yet is marked, and creating that page turns every " +
				"such link live.\n" +
				"- `[[Category:Name]]` puts the page in a category instead of rendering inline.\n\n" +
				"A page whose first line is `#REDIRECT [[Target]]` redirects.\n\n" +
				"Every page has a discussion thread at `<Title>/talk`, written with " +
				"`Comment(title, body, replyTo)`. It stays open even when the article " +
				"itself is locked, because that is where a disagreement should go.\n\n" +
				"Your transaction locks a storage deposit for the bytes you add, and releases " +
				"it when they are removed, so the wiki charges the author of a page rather " +
				"than its readers.\n\n[[Category:Help]]\n",
			"seed",
		},
	}
	now := time.Now()
	h := runtime.ChainHeight()
	for _, p := range pages {
		if _, err := site.Edit(steward, now, h, p.title, p.body, p.summary, false); err != nil {
			panic(err)
		}
	}
}
