package forge

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func TestValidPkgPath(t *testing.T) {
	cases := []struct {
		name string
		path string
		want bool
	}{
		{"a realm", "gno.land/r/moul/home", true},
		{"a pure package", "gno.land/p/moul/forge/v1", true},
		{"deep", "gno.land/r/moul/x/daily/asciiart/v0", true},
		{"an address namespace", "gno.land/r/g1abc/thing", true},
		{"underscores and dashes", "gno.land/r/ns/a-b_c", true},
		// Shape only. A realm cannot ask the chain whether a path is deployed,
		// so anything stricter would be a check that only sometimes works.
		{"not deployed but well formed", "gno.land/r/nobody/nothing", true},
		{"empty", "", false},
		{"two parts", "gno.land/r", false},
		{"a traversal", "gno.land/r/../etc", false},
		{"trailing slash", "gno.land/r/moul/home/", false},
		{"an empty element", "gno.land//r/moul", false},
		{"a space", "gno.land/r/moul/my home", false},
		{"a colon", "gno.land/r/moul/home:tab", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, ValidPkgPath(tc.path))
		})
	}
}

func TestPublishPackageIndexesForgeWide(t *testing.T) {
	f, r := newRepo(t)

	p, err := f.PublishPackage(carol, 200, r.ID, "gno.land/r/moul/home", "refs/heads/main", oid("a"), "")
	urequire.NoError(t, err)
	uassert.Equal(t, "gno.land/r/moul/home", p.Path)
	uassert.Equal(t, r.ID, p.RepoID)
	uassert.Equal(t, int64(200), p.PublishedAt)

	// The lookup an explorer makes: it starts from the path and does not know
	// the repo yet, which is the whole reason the index is forge-wide.
	uassert.Equal(t, r.ID, f.PackageRepo("gno.land/r/moul/home"))
	uassert.Equal(t, "", f.PackageRepo("gno.land/r/someone/else"))
	uassert.Equal(t, 1, f.PackageCount())
	uassert.Equal(t, 1, r.PackageCount())
}

// One repo publishes many paths: gno-contracts publishes 193.
func TestPublishManyPackages(t *testing.T) {
	f, r := newRepo(t)

	paths := []string{
		"gno.land/r/moul/home",
		"gno.land/p/moul/forge/v1",
		"gno.land/r/moul/blog",
	}
	for _, path := range paths {
		_, err := f.PublishPackage(alice, 200, r.ID, path, "", "", "")
		urequire.NoError(t, err)
	}
	uassert.Equal(t, 3, r.PackageCount())

	var seen []string
	r.IteratePackages(0, 0, func(p *Package) bool {
		seen = append(seen, p.Path)
		return false
	})
	// Path order, which is what the tree gives and what a file list wants.
	urequire.Equal(t, 3, len(seen))
	uassert.Equal(t, "gno.land/p/moul/forge/v1", seen[0])
	uassert.Equal(t, "gno.land/r/moul/blog", seen[1])
	uassert.Equal(t, "gno.land/r/moul/home", seen[2])
}

// Re-publishing the same path from the same repo is a redeploy, and overwrites.
func TestRepublishOverwrites(t *testing.T) {
	f, r := newRepo(t)

	_, err := f.PublishPackage(alice, 200, r.ID, "gno.land/r/moul/home", "", oid("a"), "v1.0.0")
	urequire.NoError(t, err)
	_, err = f.PublishPackage(alice, 300, r.ID, "gno.land/r/moul/home", "", oid("b"), "v1.1.0")
	urequire.NoError(t, err)

	uassert.Equal(t, 1, f.PackageCount())
	got := f.PackageAt("gno.land/r/moul/home")
	urequire.True(t, got != nil)
	uassert.Equal(t, oid("b"), got.OID)
	uassert.Equal(t, "v1.1.0", got.Tag)
	uassert.Equal(t, int64(300), got.PublishedAt)
}

// Silently moving a claimed path would let any repo owner capture another
// project's package in every explorer that reads this index.
func TestPublishRefusesAnotherReposPath(t *testing.T) {
	f, r := newRepo(t)
	_, err := f.PublishPackage(alice, 200, r.ID, "gno.land/r/moul/home", "", "", "")
	urequire.NoError(t, err)

	other, err := f.CreateRepo(eve, 210, "eve/squat", "", "")
	urequire.NoError(t, err)

	_, err = f.PublishPackage(eve, 220, other.ID, "gno.land/r/moul/home", "", "", "")
	uassert.ErrorIs(t, err, ErrPackageClaimed)
	uassert.Equal(t, r.ID, f.PackageRepo("gno.land/r/moul/home"))
}

func TestPublishAuthorityAndValidation(t *testing.T) {
	f, r := newRepo(t)

	// dave is a reader, eve is nothing: neither may publish.
	_, err := f.PublishPackage(dave, 200, r.ID, "gno.land/r/moul/home", "", "", "")
	uassert.ErrorIs(t, err, ErrUnauthorized)
	_, err = f.PublishPackage(eve, 200, r.ID, "gno.land/r/moul/home", "", "", "")
	uassert.ErrorIs(t, err, ErrUnauthorized)

	_, err = f.PublishPackage(alice, 200, "nobody/nothing", "gno.land/r/x/y", "", "", "")
	uassert.ErrorIs(t, err, ErrRepoNotFound)

	_, err = f.PublishPackage(alice, 200, r.ID, "not a path", "", "", "")
	uassert.ErrorIs(t, err, ErrInvalidPkgPath)

	_, err = f.PublishPackage(alice, 200, r.ID, "gno.land/r/moul/home", "main", "", "")
	uassert.ErrorIs(t, err, ErrInvalidRefName)

	_, err = f.PublishPackage(alice, 200, r.ID, "gno.land/r/moul/home", "", "nothex", "")
	uassert.ErrorIs(t, err, ErrInvalidOID)

	urequire.NoError(t, r.SetArchived(alice, true))
	_, err = f.PublishPackage(alice, 200, r.ID, "gno.land/r/moul/home", "", "", "")
	uassert.ErrorIs(t, err, ErrRepoArchived)
}

func TestUnpublishClearsBothHalvesOfTheIndex(t *testing.T) {
	f, r := newRepo(t)
	_, err := f.PublishPackage(alice, 200, r.ID, "gno.land/r/moul/home", "", "", "")
	urequire.NoError(t, err)

	uassert.ErrorIs(t, f.UnpublishPackage(dave, r.ID, "gno.land/r/moul/home"), ErrUnauthorized)
	uassert.ErrorIs(t, f.UnpublishPackage(alice, r.ID, "gno.land/r/nothing"), ErrPackageNotFound)

	urequire.NoError(t, f.UnpublishPackage(alice, r.ID, "gno.land/r/moul/home"))
	uassert.Equal(t, 0, f.PackageCount())
	uassert.Equal(t, 0, r.PackageCount())
	uassert.Equal(t, "", f.PackageRepo("gno.land/r/moul/home"))
}

// A fork is not a publisher of its parent's paths.
func TestForkInheritsNoPackages(t *testing.T) {
	f, r := newRepo(t)
	_, err := f.PublishPackage(alice, 200, r.ID, "gno.land/r/moul/home", "", "", "")
	urequire.NoError(t, err)

	child, err := f.Fork(eve, 210, r.ID, "eve/forge")
	urequire.NoError(t, err)
	uassert.Equal(t, 0, child.PackageCount())
	uassert.Equal(t, r.ID, f.PackageRepo("gno.land/r/moul/home"))
}
