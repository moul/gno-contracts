package registry

import (
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"

	pm "gno.land/p/moul/gnopm/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/txlink/v0"
)

// untrusted-render: every STORED field is charset-validated at write time by
// gno.land/p/moul/gnopm/v0 (ValidPkgPath, ValidRepo, ValidCommit, ValidDir,
// ValidRef). Each is an allowlist, so a stored field cannot hold a backtick, a
// pipe, a bracket, a control character or a bidi override, and therefore needs
// no escaping at any of the several places one claim is shown. Validating once
// at the write beats escaping at every read, and it is why ValidRef is narrower
// than git's own rule: one denylist field would have undone it for all of them.
//
// The one string here that is NOT validated is the render path itself, which
// arrives from the URL and is echoed back by notFound. That one is escaped.

// pageSize bounds every listing: a Render that walks unbounded state is a
// Render that eventually stops rendering.
const pageSize = 20

// Render routes gnoweb paths:
//
//	/                    every claimed package path
//	/<package path>      the claims about one package
//	/help                what this realm is, and how to write to it
func Render(path string) string {
	req := realmpath.Parse(path)
	parts := req.PathParts()

	if len(parts) == 0 || parts[0] == "" {
		return renderHome(pageOf(req))
	}
	if len(parts) == 1 && parts[0] == "help" {
		return renderHelp()
	}
	// A package path contains slashes, so it arrives split. Rejoining is the
	// whole of the routing: anything that reassembles into a valid path is a
	// package page, anything else is a miss.
	pkgPath := strings.Join(parts, "/")
	if !pm.ValidPkgPath(pkgPath) {
		return notFound(pkgPath + " is not a package path")
	}
	return renderPackage(pkgPath)
}

func base() string {
	return strings.TrimPrefix(unsafe.CurrentRealm().PkgPath(), runtime.ChainDomain())
}

func pkgURL(pkgPath string) string { return base() + ":" + pkgPath }

// link does not escape its text, because every call site passes a field that is
// charset-validated at write time (see the note above). Escaping here would
// turn "gno.land/p/moul/md/v1" into "gno\.land/p/moul/md/v1" on every row of
// every listing, for no safety anyone gains.
func link(text, url string) string { return "[" + text + "](" + url + ")" }

// join glues blocks with exactly one blank line between them.
//
// gno collapses two consecutive blank lines inside an example's // Output:
// block, exactly as Go does, so a Render that ever emits them cannot be pinned
// by an example at all. Appending "\n" by hand as sections are built is how a
// Render acquires them; assembling a list of blocks and joining once is how it
// stops. Every block arrives without its own leading or trailing blank.
func join(blocks []string) string {
	for i, b := range blocks {
		blocks[i] = strings.Trim(b, "\n")
	}
	return strings.Join(blocks, "\n\n") + "\n"
}

func pageOf(req *realmpath.Request) int {
	n, err := strconv.Atoi(req.Query.Get("page"))
	if err != nil || n < 1 {
		return 1
	}
	return n
}

// notFound echoes the requested path, which is the only untrusted string this
// file handles: it comes from the URL and has already failed validation by the
// time we are here. It is escaped rather than dropped, because "that is not a
// package path" without saying which one is an unhelpful error.
func notFound(why string) string {
	return md.H1("Not found") + "\n" + md.EscapeText(why) + ".\n\n" + link("Back to the registry", base()) + "\n"
}

func renderHome(page int) string {
	var b strings.Builder
	b.WriteString(md.H1("gnopm source registry"))
	b.WriteString("\nWhere a deployed package says it came from. Every entry is a claim made by whoever signed it, never a verified fact: this realm cannot clone a repository, so it records testimony in the shape a verifier needs and labels who said it.\n")
	b.WriteString("\n**Packages:** " + strconv.Itoa(reg.Size()) + " · **Claims:** " + strconv.Itoa(reg.Claims()) + "\n")

	if reg.Size() == 0 {
		b.WriteString("\nNothing claimed yet. " + link("Register the first package", txlink.Call("Register")) + "\n")
		b.WriteString("\n" + link("How this works", base()+":help") + "\n")
		return b.String()
	}

	b.WriteString("\n| package | claims | owner has claimed |\n")
	b.WriteString("| --- | ---: | --- |\n")
	rows := 0
	reg.IteratePackages((page-1)*pageSize, pageSize, func(p *pm.Package) bool {
		rows++
		owner := "no"
		if _, _, _, ok := OwnerClaim(p.PkgPath); ok {
			owner = "yes"
		}
		b.WriteString("| " + link(p.PkgPath, pkgURL(p.PkgPath)) +
			" | " + strconv.Itoa(p.Count()) +
			" | " + owner + " |\n")
		return false
	})

	if p := pager(page, rows); p != "" {
		b.WriteString("\n" + p + "\n")
	}
	b.WriteString("\n" + link("How this works", base()+":help") + "\n")
	return b.String()
}

func pager(page, rows int) string {
	var parts []string
	if page > 1 {
		parts = append(parts, link("previous", base()+"?page="+strconv.Itoa(page-1)))
	}
	if rows == pageSize {
		parts = append(parts, link("next", base()+"?page="+strconv.Itoa(page+1)))
	}
	return strings.Join(parts, " · ")
}

func renderPackage(pkgPath string) string {
	p := reg.Package(pkgPath)
	if p == nil {
		return join([]string{
			md.H1(pkgPath),
			"Nobody has claimed a source for this package.",
			link("Claim it", txlink.Call("Register", "pkgPath", pkgPath)),
			link("Back to the registry", base()),
		})
	}

	// The namespace owner first, then everyone else. The ordering IS the
	// tagging: no ranking is stored, it is recomputed here from the one thing
	// about a claim that the chain can actually prove.
	var owner, others []*pm.Claim
	p.IterateClaims(func(c *pm.Claim) bool {
		if c.OwnedBy(resolveName) {
			owner = append(owner, c)
		} else {
			others = append(others, c)
		}
		return false
	})

	ns := md.InlineCode(pm.Namespace(pkgPath))
	blocks := []string{
		md.H1(pkgPath),
		strconv.Itoa(p.Count()) + " claim(s). A claim is what an address said, not what anyone checked.",
	}
	if len(owner) > 0 {
		blocks = append(blocks,
			md.H2("Claimed by the namespace owner"),
			"The signer owns "+ns+", so this claim comes from the party that controls the path. That is not a proof the source matches. It is a proof of who is speaking.")
		for _, c := range owner {
			blocks = append(blocks, claimBlock(c))
		}
	}
	if len(others) > 0 {
		blocks = append(blocks,
			md.H2("Claimed by others"),
			"These addresses do not own "+ns+". A third party may be filling in the map honestly, or pointing at a repository that has nothing to do with this package. Read the source before trusting either.")
		for _, c := range others {
			blocks = append(blocks, claimBlock(c))
		}
	}
	return join(append(blocks, link("Back to the registry", base())))
}

func claimBlock(c *pm.Claim) string {
	var b strings.Builder
	b.WriteString("| field | value |\n| --- | --- |\n")
	b.WriteString("| claimant | " + md.InlineCode(c.Claimant.String()) + " |\n")
	b.WriteString("| commit | " + link(c.Commit[:12], c.SourceURL()) + " |\n")
	b.WriteString("| repository | " + link(c.Repo, c.Repo) + " |\n")
	dir := c.Dir
	if dir == "" {
		dir = "(repository root)"
	}
	b.WriteString("| directory | " + md.InlineCode(dir) + " |\n")
	if c.Ref != "" {
		b.WriteString("| ref | " + md.InlineCode(c.Ref) + " |\n")
	}
	b.WriteString("| claimed at | block " + strconv.FormatInt(c.Height, 10) + " |\n")
	updated := "never"
	if c.UpdatedAt != c.Height {
		updated = "block " + strconv.FormatInt(c.UpdatedAt, 10)
	}
	b.WriteString("| last updated | " + updated + " |")
	return b.String()
}

func renderHelp() string {
	var b strings.Builder
	b.WriteString(md.H1("How this registry works"))
	b.WriteString("\nA gno import path is a chain address, not a repository URL, so nothing on chain says where a deployed package came from. This realm is where an address can say so.\n")

	b.WriteString("\n" + md.H2("What it proves"))
	b.WriteString("\nNothing on its own, and that is the honest answer. A realm cannot clone a repository, so it cannot check that the code at a commit is the code at a path. Three claims get confused with each other and only two of them can ever be settled:\n\n")
	b.WriteString("| claim | provable |\n| --- | --- |\n")
	b.WriteString("| this package came from that repository | no. Not here and not anywhere: anyone may deploy any bytes and claim any repository |\n")
	b.WriteString("| the deployed bytes equal the addpkg payload of that directory at that commit | yes, by hashing both sides. Off chain, by anything that can clone |\n")
	b.WriteString("| the claimant owns this path's namespace | yes, from chain data, and it is recomputed on every read |\n")

	b.WriteString("\n" + md.H2("Writing to it"))
	b.WriteString("\nRegister the source of a package you deployed. Calling it again replaces your own claim and nobody else's, which is how you move a claim to a new commit after a redeploy.\n\n")
	b.WriteString(link("Register", txlink.Call("Register")) + " · " + link("Withdraw", txlink.Call("Withdraw")) + "\n")
	b.WriteString("\nFields: the full package path, an https repository URL, a 40 or 64 character lowercase hex commit, the subdirectory holding the package (empty for the repository root), and optionally a fully-qualified ref such as " + md.InlineCode("refs/tags/v1.2.0") + ".\n")
	b.WriteString("\nAnyone may claim any path. A claim from an address that does not own the namespace is not hidden: it is shown under its own heading and ranked below the owner's.\n")

	b.WriteString("\n" + link("Back to the registry", base()) + "\n")
	return b.String()
}
