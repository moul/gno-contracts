// Package toolbox is the directory of moul's small gno.land utilities: one
// page listing every tool, each tool a realm of its own at
// `r/moul/toolbox/<slug>`.
//
// It holds no logic. A tool composes other contracts (resolve a username,
// read a DAO, decode a denom) and renders the answer; this realm only says
// which tools exist and where they are. The model, the rendering and the
// query-form builder are
// [p/moul/toolbox](/p/moul/toolbox/v0).
//
// # Why the catalog is compiled in and not registered
//
// The obvious design is the opposite one: each tool calls `Register` on this
// realm from its own init, and the directory assembles itself. That design is
// unavailable here, and the reason is worth stating because it is not a
// preference.
//
// `private = true` buys redeploy-in-place at the same path and costs the
// ability to be imported: the type checker refuses any realm importing a
// private one (`ImportPrivateError`, `gnovm/pkg/gnolang/gotypecheck.go`). So a
// private hub cannot be imported by its tools, and a hub that accepts
// registration has to be public. A public realm can never be redeployed, which
// would freeze this path at v0 and move the directory's URL on the first bug
// in it.
//
// A stable URL is the whole point of a directory, so the trade goes the other
// way: everything here is private and redeployable, and adding a tool is one
// entry in [tools] plus a redeploy. The catalog is rebuilt from source every
// time, so the redeploy wipe costs nothing: there is no state to lose.
//
// [p/moul/toolbox.Catalog] stays mutable for whoever wants the other trade.
package toolbox

import "gno.land/p/moul/toolbox/v0"

// hubPath is this realm's own path. A realm can ask the chain for it, but a
// constant is what [p/moul/toolbox.SlugOf] is checked against in tests, where
// there is no chain frame to ask.
const hubPath = "gno.land/r/moul/toolbox/v0"

// hubURL is the gnoweb path of this realm, which every tool page links back
// to. A tool cannot import this realm to read it, so each one repeats it; this
// is the copy that is authoritative.
const hubURL = "/r/moul/toolbox/v0"

// tools is the directory. Adding one here and redeploying is how the toolbox
// grows; see the package doc for why it is not a registration call.
//
// Every entry must be a realm under this one: [buildCatalog] refuses an entry
// whose slug does not match its path, so a copy-paste that keeps the wrong
// path fails the deploy rather than publishing a dead link.
var tools = []toolbox.Tool{
	{
		Slug:  "usernames",
		Path:  "gno.land/r/moul/toolbox/usernames/v0",
		Title: "Usernames",
		Desc:  "Resolve a gno.land username to an address, or an address to a username.",
		Tags:  []string{"identity", "read"},
	},
}

// catalog is the directory, sorted and checked once at deploy.
var catalog = buildCatalog()

func buildCatalog() *toolbox.Catalog {
	c := &toolbox.Catalog{}
	for _, t := range tools {
		if err := c.Set(t); err != nil {
			panic(err)
		}
		if got := toolbox.SlugOf(hubPath, t.Path); got != t.Slug {
			panic("toolbox: " + t.Slug + " is declared at " + t.Path +
				", which is not gno.land/r/moul/toolbox/" + t.Slug)
		}
	}
	return c
}

// Count is how many tools the directory holds.
func Count() int { return catalog.Len() }

// Slugs lists every tool's slug, in directory order.
//
//	gnokey query vm/qeval -data 'gno.land/r/moul/toolbox/v0.Slugs()'
func Slugs() []string {
	out := make([]string, 0, catalog.Len())
	for _, t := range catalog.List() {
		out = append(out, t.Slug)
	}
	return out
}

// PathOf returns the package path of one tool, or "" when there is no such
// tool. Flat strings rather than the struct: a nested value inside a persisted
// object prints as an opaque `ref(...)` over `vm/qeval`, so a read API that is
// meant to be queried returns scalars.
//
//	gnokey query vm/qeval -data 'gno.land/r/moul/toolbox/v0.PathOf("usernames")'
func PathOf(slug string) string {
	t, ok := catalog.Get(slug)
	if !ok {
		return ""
	}
	return t.Path
}

// TitleOf returns the human name of one tool, or "".
func TitleOf(slug string) string {
	t, ok := catalog.Get(slug)
	if !ok {
		return ""
	}
	return t.Title
}

// DescOf returns the one-line description of one tool, or "".
func DescOf(slug string) string {
	t, ok := catalog.Get(slug)
	if !ok {
		return ""
	}
	return t.Desc
}

// Has reports whether a tool with that slug is listed.
func Has(slug string) bool { return catalog.Has(slug) }

// Tags lists every tag any tool carries, each once.
func Tags() []string { return catalog.Tags() }
