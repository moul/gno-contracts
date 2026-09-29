package forge

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The path an explorer walks: it arrives holding a deployed package path, knows
// no repo, and needs the issues and releases that belong to it.
func TestPackageLookupFromAPathAlone(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), demoID, "a demo repo", "")

	uassert.Equal(t, "", PackageRepo("gno.land/r/moul/home"), "nobody claims it yet")
	uassert.Equal(t, 0, PackageCount())

	testing.SetRealm(testing.NewUserRealm(alice))
	PublishPackage(cross(cur), demoID, "gno.land/r/moul/home", "refs/heads/main", oid("a"), "")

	uassert.Equal(t, demoID, PackageRepo("gno.land/r/moul/home"))
	uassert.Equal(t, 1, PackageCount())

	// One repo publishes many paths, which is the normal case: gno-contracts
	// publishes 193.
	testing.SetRealm(testing.NewUserRealm(alice))
	PublishPackage(cross(cur), demoID, "gno.land/p/moul/forge/v1", "", "", "")
	uassert.Equal(t, 2, PackageCount())
	uassert.Equal(t, demoID, PackageRepo("gno.land/p/moul/forge/v1"))

	testing.SetRealm(testing.NewUserRealm(alice))
	UnpublishPackage(cross(cur), demoID, "gno.land/r/moul/home")
	uassert.Equal(t, "", PackageRepo("gno.land/r/moul/home"))
	uassert.Equal(t, 1, PackageCount())
}

// Capturing another project's package path in every explorer that reads this
// index has to be impossible, not merely discouraged.
func TestPublishCannotCaptureAnotherReposPath(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), demoID, "", "")
	PublishPackage(cross(cur), demoID, "gno.land/r/moul/home", "", "", "")

	squatID := eve.String() + "/squat"
	testing.SetRealm(testing.NewUserRealm(eve))
	CreateRepo(cross(cur), squatID, "", "")
	testing.SetRealm(testing.NewUserRealm(eve))
	uassert.AbortsContains(t, cur, "claimed by another repo", func() {
		PublishPackage(cross(cur), squatID, "gno.land/r/moul/home", "", "", "")
	})
	uassert.Equal(t, demoID, PackageRepo("gno.land/r/moul/home"))
}

func TestPublishNeedsWriteAccess(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), demoID, "", "")

	testing.SetRealm(testing.NewUserRealm(eve))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		PublishPackage(cross(cur), demoID, "gno.land/r/moul/home", "", "", "")
	})
}

func TestReleaseLifecycle(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), demoID, "", "")

	uassert.Equal(t, 0, ReleaseCount(demoID))
	uassert.Equal(t, "", LatestReleaseTag(demoID))

	testing.SetRealm(testing.NewUserRealm(alice))
	CutRelease(cross(cur), demoID, "v1.0.0", "First", "it works", oid("a"), "", false)
	uassert.Equal(t, 1, ReleaseCount(demoID))
	uassert.Equal(t, "v1.0.0", LatestReleaseTag(demoID))

	// A prerelease is cut later and is still not the latest.
	testing.SetRealm(testing.NewUserRealm(alice))
	CutRelease(cross(cur), demoID, "v2.0.0-rc.1", "", "", "", "", true)
	uassert.Equal(t, "v1.0.0", LatestReleaseTag(demoID))

	// A tag never moves.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "release already exists", func() {
		CutRelease(cross(cur), demoID, "v1.0.0", "Again", "", oid("b"), "", false)
	})

	// Yanking withdraws it without deleting it: a version that vanished reads
	// as never published rather than as do-not-use.
	testing.SetRealm(testing.NewUserRealm(alice))
	CutRelease(cross(cur), demoID, "v2.0.0", "", "", "", "", false)
	uassert.Equal(t, "v2.0.0", LatestReleaseTag(demoID))
	testing.SetRealm(testing.NewUserRealm(alice))
	YankRelease(cross(cur), demoID, "v2.0.0", "broken migration")
	uassert.Equal(t, "v1.0.0", LatestReleaseTag(demoID))
	uassert.Equal(t, 3, ReleaseCount(demoID), "a yank keeps the release")
}

func TestReleaseNeedsWriteAccess(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	CreateRepo(cross(cur), demoID, "", "")

	testing.SetRealm(testing.NewUserRealm(eve))
	uassert.AbortsContains(t, cur, "unauthorized", func() {
		CutRelease(cross(cur), demoID, "v1.0.0", "", "", "", "", false)
	})
}

// A read against a repo that does not exist answers emptily rather than
// aborting: vm/qeval is how an explorer asks, and a panic there is a 500 the
// caller cannot tell from a broken node.
func TestReadsOnAnUnknownRepoAreEmpty(t *testing.T) {
	reset()

	uassert.Equal(t, "", PackageRepo("gno.land/r/nobody/nothing"))
	uassert.Equal(t, 0, ReleaseCount("nobody/nothing"))
	uassert.Equal(t, "", LatestReleaseTag("nobody/nothing"))
}
