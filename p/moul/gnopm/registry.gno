// Package gnopm is the domain model of a source registry for gno packages: a
// map from a deployed package path back to the repository, commit and directory
// that produced it.
//
// It exists because gno deliberately broke the link Go gets for free. A Go
// import path IS a repository URL, so pkg.go.dev needs no registry; a gno
// import path is a chain address, so nothing anywhere says which source
// produced the bytes running at gno.land/p/nt/tinyavl/v0.
//
// # What this can and cannot promise
//
// It cannot promise anything, and the design is built around saying so rather
// than around hiding it. Two claims look alike and are not the same:
//
//  1. "this package came from that repository". UNPROVABLE, here or anywhere.
//     Anyone may deploy any bytes and anyone may claim any repository. No
//     registry design fixes this, and one that implies otherwise is worse than
//     none.
//  2. "the bytes live at path P equal the addpkg payload of directory D in
//     repository R at commit C". Mechanically provable, by hashing both sides.
//     It is NOT provable here: a realm cannot clone a repository. It is
//     provable off chain by anything that can, and gnopm already does exactly
//     this against a local tree (`gnopm verify -deployed`).
//
// So this package stores (1), labelled as the claim it is, in the form (2)
// needs to be checkable. A Claim is testimony under a signature. It becomes
// evidence only once something outside the chain has gone and looked.
//
// # What a signature does buy
//
// The chain knows who signed a claim, and that is not nothing. A claim whose
// claimant owns the package path's namespace comes from the party that controls
// the path, which is the closest thing to a promise available without a
// chain-level feature. OwnedBy reports that relationship; it is deliberately
// computed on demand from a caller-supplied resolver and never stored, because
// a name can be transferred and a stored answer would be a claim of its own.
//
// Anyone may still claim any path. That is the "open but tagged" choice, and it
// is made on purpose: gating registration on namespace ownership would mean
// that on day one, when almost nothing is registered by its own deployer, the
// registry is empty and teaches nobody anything. The defence against a
// misleading claim is that it renders as a stranger's claim, ranked below, and
// never as a fact.
package gnopm

import (
	"strings"

	"gno.land/p/nt/avl/v0"
)

// Registry maps a package path to the claims made about its source.
//
// One path may carry several claims, at most one per claimant. That is not a
// flaw to be resolved: a fork is a legitimate second answer, and so is a third
// party filling in the map for a package whose author never will.
type Registry struct {
	packages *avl.Tree // package path -> *Package
	claims   int
}

// New returns an empty registry.
func New() *Registry {
	return &Registry{packages: avl.NewTree()}
}

// Package is every claim made about one package path.
type Package struct {
	PkgPath string
	claims  *avl.Tree // claimant address string -> *Claim
}

// Claim is one address's statement about where a package came from.
//
// Every field except Claimant, Height and UpdatedAt is attacker-controlled.
// They are charset-validated at write time rather than escaped at read time, so
// that a consumer which forgets to escape is still safe: the fields cannot hold
// a byte that means anything to markdown, to a terminal or to a URL parser.
type Claim struct {
	PkgPath  string
	Repo     string // https:// URL of the repository
	Commit   string // 40 or 64 lowercase hex
	Dir      string // subdirectory holding the package, "" for the repo root
	Ref      string // fully-qualified ref the commit was on, optional
	Claimant address
	Height   int64 // block height of the first claim by this claimant
	// UpdatedAt is the height of the most recent write. Equal to Height until
	// the claimant re-registers, which is how a reader tells a claim that has
	// been kept current from one made once and abandoned.
	UpdatedAt int64
}

// Register records or replaces claimant's claim about pkgPath.
//
// Re-registering the same path overwrites that claimant's own previous claim
// and nobody else's, so the ordinary "I deployed a new commit" flow is one call
// with no read first. Height is preserved across an update: it dates the claim,
// not the edit.
func (r *Registry) Register(claimant address, height int64, pkgPath, repo, commit, dir, ref string) (*Claim, error) {
	if !ValidPkgPath(pkgPath) {
		return nil, ErrInvalidPkgPath
	}
	if !ValidRepo(repo) {
		return nil, ErrInvalidRepo
	}
	if !ValidCommit(commit) {
		return nil, ErrInvalidCommit
	}
	if !ValidDir(dir) {
		return nil, ErrInvalidDir
	}
	if !ValidRef(ref) {
		return nil, ErrInvalidRef
	}

	p := r.Package(pkgPath)
	if p == nil {
		p = &Package{PkgPath: pkgPath, claims: avl.NewTree()}
		r.packages.Set(pkgPath, p)
	}

	key := claimant.String()
	c := &Claim{
		PkgPath:   pkgPath,
		Repo:      repo,
		Commit:    commit,
		Dir:       dir,
		Ref:       ref,
		Claimant:  claimant,
		Height:    height,
		UpdatedAt: height,
	}
	if prev := p.Claim(claimant); prev != nil {
		c.Height = prev.Height
	} else {
		if p.claims.Size() >= MaxClaimants {
			return nil, ErrTooManyClaimants
		}
		r.claims++
	}
	p.claims.Set(key, c)
	return c, nil
}

// Withdraw removes claimant's own claim about pkgPath. A claimant can always
// take back what they said; nobody can remove anyone else's.
func (r *Registry) Withdraw(claimant address, pkgPath string) error {
	p := r.Package(pkgPath)
	if p == nil {
		return ErrClaimNotFound
	}
	if _, removed := p.claims.Remove(claimant.String()); !removed {
		return ErrClaimNotFound
	}
	r.claims--
	if p.claims.Size() == 0 {
		r.packages.Remove(pkgPath)
	}
	return nil
}

// Package returns every claim about a path, or nil.
func (r *Registry) Package(pkgPath string) *Package {
	v := r.packages.Get(pkgPath)
	if v == nil {
		return nil
	}
	return v.(*Package)
}

// Size is the number of package paths carrying at least one claim.
func (r *Registry) Size() int { return r.packages.Size() }

// Claims is the total number of claims across every path.
func (r *Registry) Claims() int { return r.claims }

// IteratePackages walks paths in lexical order, which groups a namespace's
// packages together without needing a second index. The callback returns true
// to STOP, following avl's own convention rather than inverting it here.
func (r *Registry) IteratePackages(offset, count int, cb func(*Package) bool) {
	r.packages.IterateByOffset(offset, count, func(_ string, v any) bool {
		return cb(v.(*Package))
	})
}

// IterateNamespace walks every claimed path under "<domain>/<kind>/<ns>/".
func (r *Registry) IterateNamespace(domain, kind, ns string, cb func(*Package) bool) {
	prefix := domain + "/" + kind + "/" + ns + "/"
	r.packages.Iterate(prefix, "", func(k string, v any) bool {
		if !strings.HasPrefix(k, prefix) {
			return true // past the prefix: stop
		}
		return cb(v.(*Package))
	})
}

// Claim returns claimant's claim about this package, or nil.
func (p *Package) Claim(claimant address) *Claim {
	v := p.claims.Get(claimant.String())
	if v == nil {
		return nil
	}
	return v.(*Claim)
}

// Count is how many addresses have claimed this package.
func (p *Package) Count() int { return p.claims.Size() }

// IterateClaims walks the claims in claimant-address order. Order is not
// significance: a caller that wants the owner's claim first must ask OwnedBy,
// because the registry has no opinion about which claim is true.
func (p *Package) IterateClaims(cb func(*Claim) bool) {
	p.claims.Iterate("", "", func(_ string, v any) bool {
		return cb(v.(*Claim))
	})
}

// OwnedBy reports whether c comes from the party that controls the package
// path's namespace: either the address whose own namespace it is, or whoever
// resolve says holds the registered name.
//
// resolve maps a namespace name to the address holding it and whether that name
// is held at all. It is a parameter rather than an import because this package
// stays pure: the realm supplies r/sys/users, and a test supplies a table.
//
// This is the one label in the whole design that is derived rather than
// declared, so it is computed here and never stored. A name can be transferred;
// a stored answer would age into a lie of exactly the kind this package exists
// to avoid.
func (c *Claim) OwnedBy(resolve func(name string) (address, bool)) bool {
	_, _, ns, _, ok := SplitPkgPath(c.PkgPath)
	if !ok {
		return false
	}
	if AddressNamespace(ns) {
		return ns == c.Claimant.String()
	}
	if resolve == nil {
		return false
	}
	addr, held := resolve(ns)
	return held && addr == c.Claimant
}

// SourceURL builds a browsable link to the claimed source: the commit, plus the
// directory when the package is not at the repository root.
//
// GitHub's "/tree/<commit>/<dir>" layout is also GitLab's, Gitea's, Forgejo's
// and Codeberg's, so one construction covers every forge this registry is
// likely to meet. It is a convenience, not a promise the link resolves: the
// repository may be gone, private or renamed since the claim was made, which is
// itself something a verifier reports rather than something a realm can know.
func (c *Claim) SourceURL() string {
	u := strings.TrimSuffix(c.Repo, "/") + "/tree/" + c.Commit
	if c.Dir != "" {
		u += "/" + c.Dir
	}
	return u
}
