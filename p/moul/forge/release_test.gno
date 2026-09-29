package forge

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func TestValidTag(t *testing.T) {
	cases := []struct {
		name string
		tag  string
		want bool
	}{
		{"semver", "v1.2.0", true},
		// gno.land's own packages are v0 and v1 with no minor or patch. A tag
		// rule that refused those would refuse the ecosystem it serves.
		{"a gno version", "v0", true},
		{"a prerelease", "v1.0.0-rc.1", true},
		{"build metadata", "v1.0.0+build.5", true},
		{"not version shaped at all", "genesis-snapshot", true},
		{"empty", "", false},
		{"a slash", "release/v1", false},
		{"a traversal", "v1..0", false},
		{"a space", "v1 0", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, ValidTag(tc.tag))
		})
	}
}

func TestCutRelease(t *testing.T) {
	_, r := newRepo(t)

	rel, err := r.CutRelease(carol, 300, "v1.0.0", "First", "it works", oid("a"), "refs/tags/v1.0.0", false)
	urequire.NoError(t, err)
	uassert.Equal(t, "v1.0.0", rel.Tag)
	uassert.Equal(t, "First", rel.Name)
	uassert.Equal(t, int64(300), rel.CreatedAt)
	uassert.False(t, rel.Prerelease)
	uassert.Equal(t, 1, r.ReleaseCount())

	got := r.Release("v1.0.0")
	urequire.True(t, got != nil)
	uassert.Equal(t, "it works", got.Notes)
	uassert.True(t, r.Release("v9.9.9") == nil)
}

// A consumer who pinned v1.2.0 and later got different bytes has been lied to.
// The whole point of a tag is that it does not move.
func TestCutReleaseIsImmutable(t *testing.T) {
	_, r := newRepo(t)

	_, err := r.CutRelease(alice, 300, "v1.0.0", "First", "", oid("a"), "", false)
	urequire.NoError(t, err)
	_, err = r.CutRelease(alice, 400, "v1.0.0", "Second", "", oid("b"), "", false)
	uassert.ErrorIs(t, err, ErrReleaseExists)
	uassert.Equal(t, oid("a"), r.Release("v1.0.0").OID)
}

// Cut order, never tag order: a lexical sort presents v10 before v2 and calls
// it newest, and there is no semver to sort by because the tags are not
// required to be semver.
func TestIterateReleasesIsCutOrderNotTagOrder(t *testing.T) {
	_, r := newRepo(t)

	for i, tag := range []string{"v2.0.0", "v10.0.0", "v3.0.0"} {
		_, err := r.CutRelease(alice, int64(300+i), tag, "", "", "", "", false)
		urequire.NoError(t, err)
	}

	var seen []string
	r.IterateReleases(0, 0, func(rel *Release) bool {
		seen = append(seen, rel.Tag)
		return false
	})
	urequire.Equal(t, 3, len(seen))
	uassert.Equal(t, "v3.0.0", seen[0])
	uassert.Equal(t, "v10.0.0", seen[1])
	uassert.Equal(t, "v2.0.0", seen[2])
}

func TestLatestReleaseSkipsPrereleaseAndYanked(t *testing.T) {
	_, r := newRepo(t)

	_, err := r.CutRelease(alice, 300, "v1.0.0", "", "", "", "", false)
	urequire.NoError(t, err)
	uassert.Equal(t, "v1.0.0", r.LatestRelease().Tag)

	// A prerelease is cut later and is still not the latest.
	_, err = r.CutRelease(alice, 310, "v2.0.0-rc.1", "", "", "", "", true)
	urequire.NoError(t, err)
	uassert.Equal(t, "v1.0.0", r.LatestRelease().Tag)

	_, err = r.CutRelease(alice, 320, "v2.0.0", "", "", "", "", false)
	urequire.NoError(t, err)
	uassert.Equal(t, "v2.0.0", r.LatestRelease().Tag)

	// Yanking moves it back, and does not delete it.
	urequire.NoError(t, r.YankRelease(alice, "v2.0.0", "broken migration"))
	uassert.Equal(t, "v1.0.0", r.LatestRelease().Tag)
	uassert.Equal(t, 3, r.ReleaseCount())
	yanked := r.Release("v2.0.0")
	urequire.True(t, yanked != nil)
	uassert.True(t, yanked.Yanked)
	uassert.Equal(t, "broken migration", yanked.YankReason)
}

func TestLatestReleaseIsNilWhenThereIsNone(t *testing.T) {
	_, r := newRepo(t)
	uassert.True(t, r.LatestRelease() == nil)

	_, err := r.CutRelease(alice, 300, "v1.0.0-rc.1", "", "", "", "", true)
	urequire.NoError(t, err)
	uassert.True(t, r.LatestRelease() == nil)
}

func TestReleaseAuthorityAndValidation(t *testing.T) {
	_, r := newRepo(t)

	_, err := r.CutRelease(dave, 300, "v1.0.0", "", "", "", "", false)
	uassert.ErrorIs(t, err, ErrUnauthorized)
	_, err = r.CutRelease(eve, 300, "v1.0.0", "", "", "", "", false)
	uassert.ErrorIs(t, err, ErrUnauthorized)

	_, err = r.CutRelease(alice, 300, "release/v1", "", "", "", "", false)
	uassert.ErrorIs(t, err, ErrInvalidTag)

	_, err = r.CutRelease(alice, 300, "v1.0.0", "", "", "nothex", "", false)
	uassert.ErrorIs(t, err, ErrInvalidOID)

	_, err = r.CutRelease(alice, 300, "v1.0.0", "", "", "", "v1.0.0", false)
	uassert.ErrorIs(t, err, ErrInvalidRefName)

	uassert.ErrorIs(t, r.YankRelease(dave, "v1.0.0", ""), ErrUnauthorized)
	uassert.ErrorIs(t, r.YankRelease(alice, "v9.9.9", ""), ErrReleaseNotFound)

	urequire.NoError(t, r.SetArchived(alice, true))
	_, err = r.CutRelease(alice, 300, "v1.0.0", "", "", "", "", false)
	uassert.ErrorIs(t, err, ErrRepoArchived)
}

func TestForkInheritsNoReleases(t *testing.T) {
	f, r := newRepo(t)
	_, err := r.CutRelease(alice, 300, "v1.0.0", "", "", "", "", false)
	urequire.NoError(t, err)

	child, err := f.Fork(eve, 310, r.ID, "eve/forge")
	urequire.NoError(t, err)
	uassert.Equal(t, 0, child.ReleaseCount())
	uassert.True(t, child.LatestRelease() == nil)
}
