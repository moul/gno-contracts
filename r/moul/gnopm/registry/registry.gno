// Package registry is an open, on-chain map from a deployed gno package path
// back to the source that produced it: repository, commit, directory.
//
// It is the realm half of gno.land/p/moul/gnopm/v0, which holds the domain
// model and the whole of the reasoning; this file is wiring. Every exported
// mutation is a crossing function that resolves the caller, forwards to the
// library, aborts on error (the only way to revert state in gno) and emits an
// event for indexers.
//
// # It cannot promise, and does not pretend to
//
// Nothing here is verified and nothing here can be. A realm cannot clone a
// repository, so it cannot check that the bytes at the claimed commit are the
// bytes deployed at the claimed path. What it stores is testimony under a
// signature: this address says this package came from that source.
//
// That is still worth storing, for two reasons.
//
// First, it is testimony in the exact shape a verifier needs. Path, repository,
// commit and directory are precisely the four inputs to "hash the addpkg
// payload of that directory and compare it with what the chain hands back",
// which gnopm already does against a local tree (`gnopm verify -deployed`). The
// registry does not answer the question; it makes the question answerable by
// anything that can clone.
//
// Second, the chain knows who signed. A claim from the address that owns the
// package path's namespace comes from the party that controls the path, and
// OwnedBy reports that. It is computed on every read, never stored, because a
// name can be transferred and a stored answer would rot into exactly the kind
// of stale claim this realm exists to distinguish from a live one.
//
// # Open, and tagged
//
// Anyone may claim any path, including one they had nothing to do with. That is
// deliberate: gating registration on namespace ownership would leave the map
// empty on day one, when almost nothing has been registered by its own
// deployer, and an empty registry teaches nobody anything. A stranger's claim
// is not suppressed, it is labelled and ranked below the owner's, and Render
// never presents an unverified claim as a fact.
//
// A claimant may always withdraw their own claim, and may never touch anyone
// else's.
package registry

import (
	"chain"
	"chain/runtime"

	pm "gno.land/p/moul/gnopm/v0"
	"gno.land/r/sys/users"
)

var reg = pm.New()

// caller is the address that crossed into this realm. Deliberately not
// restricted to end users: a realm may hold a namespace, and a DAO registering
// the source of the packages it governs is the same operation.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("gnopm/registry: spoofed realm")
	}
	return cur.Previous().Address()
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

// resolveName is the r/sys/users half of the ownership rule, passed to the
// library so the library stays pure.
//
// isCurrent is deliberately ignored, matching r/moul/forge: a name that
// resolves through an alias still resolves to the same holder, so a namespace
// survives its owner renaming. IsDeleted folds the nil check in, which is what
// its own doc comment asks call sites to rely on.
func resolveName(name string) (address, bool) {
	data, _ := users.ResolveName(name)
	if data.IsDeleted() {
		return "", false
	}
	return data.Addr(), true
}

// Register records that pkgPath was built from dir of repo at commit.
//
// Calling it again for the same path replaces the caller's own claim and
// nobody else's, so moving a claim to a new commit after a redeploy is one
// call with no read first.
//
// ref is optional and is never the thing verified: a ref moves, a commit does
// not. It is recorded so a reader can tell a claim pinned to a released tag
// from one pinned to a commit on nobody's branch, and so a verifier can report
// a commit that has since been orphaned by a force-push.
//
// dir is empty when the package sits at the repository root.
func Register(cur realm, pkgPath, repo, commit, dir, ref string) {
	a := caller(cur)
	_, err := reg.Register(a, runtime.ChainHeight(), pkgPath, repo, commit, dir, ref)
	must(err)
	chain.Emit("SourceClaimed",
		"pkgpath", pkgPath,
		"claimant", a.String(),
		"repo", repo,
		"commit", commit,
	)
}

// Withdraw removes the caller's own claim about pkgPath.
func Withdraw(cur realm, pkgPath string) {
	a := caller(cur)
	must(reg.Withdraw(a, pkgPath))
	chain.Emit("SourceWithdrawn", "pkgpath", pkgPath, "claimant", a.String())
}

// PackageCount is how many package paths carry at least one claim.
func PackageCount() int { return reg.Size() }

// ClaimCount is the total number of claims across every path.
func ClaimCount() int { return reg.Claims() }

// HasClaims reports whether anything has been said about pkgPath. Cheap enough
// for another realm or an indexer to ask per package.
func HasClaims(pkgPath string) bool { return reg.Package(pkgPath) != nil }

// OwnerClaim returns the repository, commit and directory claimed by the party
// that owns pkgPath's namespace, and whether such a claim exists.
//
// This is the only read that filters, and it filters on the one signal the
// chain can actually prove. Everything else a caller wants is in Render or in
// the events.
func OwnerClaim(pkgPath string) (repo, commit, dir string, ok bool) {
	p := reg.Package(pkgPath)
	if p == nil {
		return "", "", "", false
	}
	p.IterateClaims(func(c *pm.Claim) bool {
		if c.OwnedBy(resolveName) {
			repo, commit, dir, ok = c.Repo, c.Commit, c.Dir, true
			return true // stop
		}
		return false
	})
	return repo, commit, dir, ok
}
