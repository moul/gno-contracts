// Package pairreg is the registry every AMM pair instance announces itself to,
// and the unified frontend over all of them.
//
// It is the third artifact of the instance-per-realm pattern: one shared
// p/moul/x/pair/v0 holding the logic, N tiny realms holding one pair each, and
// this realm knowing all of them.
//
// # Why registration cannot be faked, and code cannot be trusted
//
// Register keys an instance by cur.Previous().PkgPath(), which the runtime
// supplies, so an instance cannot claim a path that is not its own. That is
// the whole on-chain guarantee. It is NOT a guarantee about the code at that
// path: gno has no way to read another package's source from inside a realm,
// so nothing here can check that an instance really runs the shared template.
// The mirror image of Ethereum's CREATE2, which proves the code and says
// nothing legible about who deployed it.
//
// Consequences a reader of the index must keep in mind:
//
//   - Reserves shown here are CLAIMED. They are read live from the instance's
//     own struct, which is honest for an instance running the template and
//     arbitrary for one that does not.
//   - Several instances may exist for the same token couple. That is allowed
//     on purpose; there is no canonical pair and no factory to enforce one.
//   - Approving tokens to an instance risks exactly what was approved. Read
//     the instance's source (vm/qfile on its path) before funding it.
//
// # Why the registry can read live state at all
//
// Instances register a *pair.Pair pointer, not an address, the way grc20reg
// registers a *grc20.Token. One vm/qrender here therefore renders the real
// state of every instance, with no indexer and no multicall. It is safe
// because pair.Pair holds only concrete types: an interface or a func field
// would let a hostile instance hand foreign code to this realm's frame.
package pairreg

import (
	"chain"
	"chain/runtime"
	"strings"

	"gno.land/p/moul/x/pair/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Entry is one registered instance.
type Entry struct {
	Path   string     // the instance realm's package path, supplied by the runtime
	Pair   *pair.Pair // live pointer into the instance's own storage
	Height int64      // chain height at registration
}

// entries maps instance path -> *Entry. couples maps a pair ID
// ("keyA~keyB") -> int, how many instances claim that couple.
var (
	entries avl.Tree
	couples avl.Tree
)

// Register records the calling realm as an instance. Call it from the
// instance's init, so that deploying and listing are one transaction:
//
//	func init(cur realm) {
//		p = pair.New(keyA, keyB, grc20reg.MustGet(keyA), grc20reg.MustGet(keyB))
//		pairreg.Register(cross(cur), p)
//	}
//
// Permissionless by design: anyone may deploy an instance under their own
// address namespace and land here. Spam is self funded, since the registering
// transaction pays for the storage it adds.
func Register(cur realm, p *pair.Pair) {
	caller := cur.Previous()
	path := caller.PkgPath()
	if path == "" {
		panic("pairreg: only a realm can register")
	}
	if p == nil {
		panic("pairreg: nil pair")
	}
	if entries.Has(path) {
		panic("pairreg: already registered: " + path)
	}

	entries.Set(path, &Entry{Path: path, Pair: p, Height: runtime.ChainHeight()})
	couples.Set(p.ID(), countFor(p.ID())+1)

	chain.Emit("RegisterPair",
		"path", path,
		"pair", p.ID(),
	)
}

// Get returns the entry for an instance path, or nil.
func Get(path string) *Entry {
	v := entries.Get(path)
	if v == nil {
		return nil
	}
	return v.(*Entry)
}

// Size returns how many instances are registered.
func Size() int { return entries.Size() }

// Couples returns how many distinct token couples are represented.
func Couples() int { return couples.Size() }

// InstancesFor returns the instance paths claiming a given couple id.
func InstancesFor(id string) []string {
	out := []string{}
	entries.Iterate("", "", func(_ string, value any) bool {
		e := value.(*Entry)
		if e.Pair.ID() == id {
			out = append(out, e.Path)
		}
		return false
	})
	return out
}

// Render is the unified frontend: the index of every instance with its live
// state, or one instance's own page when path is an instance path.
func Render(path string) string {
	if path != "" {
		e := Get(path)
		if e == nil {
			return "# 404\n\nNo instance registered at `" + path + "`.\n"
		}
		out := e.Pair.Render("")
		out += "\n---\n\n"
		out += ufmt.Sprintf("Instance: [`%s`](%s) · registered at height %d · %d instance(s) claim this couple.\n",
			e.Path, webPath(e.Path), e.Height, countFor(e.Pair.ID()))
		return out
	}

	out := "# AMM pairs\n\n"
	out += "One realm per token couple, all running [p/moul/x/pair/v0](/p/moul/x/pair/v0). "
	out += "Anyone can deploy one under their own namespace and it lands here.\n\n"

	if entries.Size() == 0 {
		out += "_No instance yet._\n"
		return out
	}

	out += ufmt.Sprintf("%d instance(s), %d couple(s).\n\n", entries.Size(), couples.Size())
	out += "**Reserves below are claimed by each instance, not verified.** "
	out += "Nothing on chain can check that an instance runs the shared template; read its source before funding it.\n\n"
	out += "| pair | reserves | LP shares | providers | instance |\n"
	out += "|---|---|---|---|---|\n"
	entries.Iterate("", "", func(key string, value any) bool {
		e := value.(*Entry)
		symA, symB := e.Pair.Symbols()
		resA, resB := e.Pair.Reserves()
		out += ufmt.Sprintf("| [%s/%s](/r/moul/x/pairreg/v0:%s) | %d %s / %d %s | %d | %d | [`%s`](%s) |\n",
			symA, symB, key,
			resA, symA, resB, symB,
			e.Pair.TotalShares(), e.Pair.Providers(),
			shortPath(e.Path), webPath(e.Path))
		return false
	})
	return out
}

//
// Internals.
//

func countFor(id string) int {
	v := couples.Get(id)
	if v == nil {
		return 0
	}
	return v.(int)
}

// webPath turns a package path into a gnoweb link.
func webPath(pkgPath string) string {
	if i := strings.Index(pkgPath, "/"); i >= 0 {
		return pkgPath[i:]
	}
	return "/" + pkgPath
}

// shortPath drops the chain domain, which is the same on every row.
func shortPath(pkgPath string) string {
	if i := strings.Index(pkgPath, "/"); i >= 0 {
		return pkgPath[i+1:]
	}
	return pkgPath
}
