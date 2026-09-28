package forge

import "strings"

// MaxPkgPathLen bounds a published package path. gno.land's own paths are far
// shorter; the cap exists because every stored byte is a storage deposit
// somebody pays.
const MaxPkgPathLen = 256

// Package is the claim that a repo publishes a deployed package path.
//
// This is the join nothing else in the forge could express. A repo id is
// "<namespace>/<name>", exactly two parts, so `r/moul/home` can never be one:
// there was no way to ask "which repo publishes this package path", which is
// the first question a reader arriving from an explorer has.
//
// The claim is deliberately one-directional and unverified. A realm cannot ask
// the chain who deployed a path, so the forge cannot check that the repo really
// is the source of the package. What it can guarantee is that only someone with
// write access to the repo said so, and that the namespace of the repo is
// governed by r/sys/users. A reader weighs the claim the way they weigh a
// go.mod: it says where the author says the source lives.
type Package struct {
	Path        string // "gno.land/r/moul/home", the deployed package path
	RepoID      string
	Ref         string // the ref this was published from, "" if unstated
	OID         string // the object id, "" if unstated
	Tag         string // the release tag, "" if not published as part of one
	PublishedAt int64  // block height
	PublishedBy address
}

// ValidPkgPath reports whether s is a plausible gno package path.
//
// Deliberately shallow: it checks shape, not existence, because a realm cannot
// ask the chain whether a path is deployed and a check that only sometimes
// works is worse than one that never claims to.
func ValidPkgPath(s string) bool {
	if s == "" || len(s) > MaxPkgPathLen {
		return false
	}
	if strings.Contains(s, "..") || strings.HasSuffix(s, "/") {
		return false
	}
	parts := strings.Split(s, "/")
	if len(parts) < 3 {
		return false
	}
	for _, p := range parts {
		if p == "" {
			return false
		}
		for i := 0; i < len(p); i++ {
			c := p[i]
			ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				(c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_'
			if !ok {
				return false
			}
		}
	}
	return true
}

// PublishPackage records that this repo publishes path, and indexes it
// forge-wide so PackageRepo can answer without scanning every repo.
//
// Re-publishing the same path from the same repo overwrites the entry, which is
// what a redeploy is. Publishing a path another repo already claims is refused:
// silently moving it would let any repo owner capture another project's
// package path in an explorer.
func (f *Forge) PublishPackage(actor address, height int64, repoID, path, ref, oid, tag string) (*Package, error) {
	r := f.Repo(repoID)
	if r == nil {
		return nil, ErrRepoNotFound
	}
	if r.Archived {
		return nil, ErrRepoArchived
	}
	if !r.Can(actor, RoleWriter) {
		return nil, ErrUnauthorized
	}
	if !ValidPkgPath(path) {
		return nil, ErrInvalidPkgPath
	}
	if ref != "" && !ValidRefName(ref) {
		return nil, ErrInvalidRefName
	}
	if oid != "" && !ValidOID(oid) {
		return nil, ErrInvalidOID
	}
	if tag != "" && !ValidText(tag, MaxTagLen) {
		return nil, ErrInvalidText
	}
	if owner := f.packages.Get(path); owner != nil {
		if existing := owner.(*Package); existing.RepoID != repoID {
			return nil, ErrPackageClaimed
		}
	}

	p := &Package{
		Path:        path,
		RepoID:      repoID,
		Ref:         ref,
		OID:         oid,
		Tag:         tag,
		PublishedAt: height,
		PublishedBy: actor,
	}
	f.packages.Set(path, p)
	r.packages.Set(path, p)
	return p, nil
}

// UnpublishPackage withdraws the claim. The package stays on chain; only the
// repo's assertion about it goes away.
func (f *Forge) UnpublishPackage(actor address, repoID, path string) error {
	r := f.Repo(repoID)
	if r == nil {
		return ErrRepoNotFound
	}
	if !r.Can(actor, RoleWriter) {
		return ErrUnauthorized
	}
	if _, removed := r.packages.Remove(path); !removed {
		return ErrPackageNotFound
	}
	f.packages.Remove(path)
	return nil
}

// PackageRepo is the lookup an explorer makes: given a deployed path, which
// repo claims to publish it. Returns "" when nobody does.
func (f *Forge) PackageRepo(path string) string {
	v := f.packages.Get(path)
	if v == nil {
		return ""
	}
	return v.(*Package).RepoID
}

// PackageAt returns the full claim for a path, or nil.
func (f *Forge) PackageAt(path string) *Package {
	v := f.packages.Get(path)
	if v == nil {
		return nil
	}
	return v.(*Package)
}

// PackageCount is how many paths the whole forge claims.
func (f *Forge) PackageCount() int { return f.packages.Size() }

// IteratePackages walks every claimed path in the forge, in path order.
func (f *Forge) IteratePackages(offset, count int, cb func(*Package) bool) {
	if count <= 0 {
		count = f.packages.Size()
	}
	f.packages.IterateByOffset(offset, count, func(_ string, v any) bool {
		return cb(v.(*Package))
	})
}

// PackageCount is how many paths this repo claims.
func (r *Repo) PackageCount() int { return r.packages.Size() }

// IteratePackages walks the paths this repo claims, in path order.
func (r *Repo) IteratePackages(offset, count int, cb func(*Package) bool) {
	if count <= 0 {
		count = r.packages.Size()
	}
	r.packages.IterateByOffset(offset, count, func(_ string, v any) bool {
		return cb(v.(*Package))
	})
}
