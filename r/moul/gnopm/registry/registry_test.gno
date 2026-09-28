package registry

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRegisterAndWithdraw(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), otherPkg, repoURL, sha1Zero, "p/moul/md", "refs/heads/main")

	uassert.Equal(t, 1, PackageCount())
	uassert.Equal(t, 1, ClaimCount())
	uassert.True(t, HasClaims(otherPkg))
	uassert.False(t, HasClaims("gno.land/p/moul/nope/v0"))

	testing.SetRealm(testing.NewUserRealm(alice))
	Withdraw(cross(cur), otherPkg)
	uassert.Equal(t, 0, PackageCount())
	uassert.False(t, HasClaims(otherPkg))
}

// A claim is the claimant's own. Nobody else may take it back, and the refusal
// has to abort rather than silently do nothing: a Withdraw that quietly did
// nothing reads to the caller exactly like one that worked.
func TestWithdrawIsNotTransferable(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), otherPkg, repoURL, sha1Zero, "", "")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no such claim", func() {
		Withdraw(cross(cur), otherPkg)
	})
	uassert.True(t, HasClaims(otherPkg), "alice's claim survived bob")
}

func TestRegisterAborts(cur realm, t *testing.T) {
	reset()
	cases := []struct {
		name                            string
		pkgPath, repo, commit, dir, ref string
		contains                        string
	}{
		{"bad path", "nonsense", repoURL, sha1Zero, "", "", "invalid package path"},
		{"non-https repo", otherPkg, "javascript:alert(1)", sha1Zero, "", "", "invalid repository URL"},
		{"abbreviated commit", otherPkg, repoURL, "0123456", "", "", "invalid commit id"},
		{"absolute dir", otherPkg, repoURL, sha1Zero, "/etc", "", "invalid directory"},
		{"unqualified ref", otherPkg, repoURL, sha1Zero, "", "main", "invalid ref name"},
	}
	for _, tc := range cases {
		testing.SetRealm(testing.NewUserRealm(alice))
		uassert.AbortsContains(t, cur, tc.contains, func() {
			Register(cross(cur), tc.pkgPath, tc.repo, tc.commit, tc.dir, tc.ref)
		}, tc.name)
	}
	uassert.Equal(t, 0, ClaimCount(), "nothing was stored")
}

// OwnerClaim is the only read that filters, and it filters on the one thing
// about a claim the chain can prove. An address namespace belongs to that
// account with nothing registered anywhere, so it is testable without
// r/sys/users, which a test cannot write to.
func TestOwnerClaim(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(bob))
	Register(cross(cur), alicePkg, "https://github.com/bob/impostor", sha1One, "", "")
	_, _, _, ok := OwnerClaim(alicePkg)
	uassert.False(t, ok, "a stranger's claim is not the owner's")

	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), alicePkg, repoURL, sha1Zero, "scratch", "")
	repo, commit, dir, ok := OwnerClaim(alicePkg)
	uassert.True(t, ok, "the namespace holder's claim is found")
	uassert.Equal(t, repoURL, repo)
	uassert.Equal(t, sha1Zero, commit)
	uassert.Equal(t, "scratch", dir)

	_, _, _, ok = OwnerClaim("gno.land/p/moul/nothing/v0")
	uassert.False(t, ok, "an unclaimed path has no owner claim")
}

// Re-registering moves the caller's own claim and creates no second one.
func TestReregister(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), otherPkg, repoURL, sha1Zero, "p/moul/md", "")
	testing.SkipHeights(10)
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), otherPkg, repoURL, sha1One, "p/moul/md", "refs/tags/v1")

	uassert.Equal(t, 1, ClaimCount())
	got := Render(otherPkg)
	uassert.True(t, strings.Contains(got, sha1One[:12]), "the new commit renders")
	uassert.False(t, strings.Contains(got, sha1Zero[:12]), "the old one is gone")
	uassert.True(t, strings.Contains(got, "| last updated | block"), "an updated claim says when")
}

// A package path arrives at Render already split on "/", so the routing is the
// rejoin. Anything that does not reassemble into a path is a miss, and a miss
// must not render as an empty package page.
func TestRenderRouting(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render("nonsense"), "Not found"), "one bad element")
	uassert.True(t, strings.Contains(Render("a/b/c"), "Not found"), "too few elements")
	uassert.True(t, strings.Contains(Render("help"), "How this registry works"), "help page")
	uassert.True(t, strings.Contains(Render(""), "gnopm source registry"), "home")
	uassert.True(t, strings.Contains(Render(otherPkg), "Nobody has claimed"), "valid but unclaimed")
}

// The page ranks the owner's claim above a stranger's and says which is which.
// Rendering them identically is the whole mistake this realm exists to avoid,
// so the separation is pinned rather than left to review.
func TestRenderSeparatesOwnerFromStranger(t *testing.T) {
	seedFixture()

	got := Render(alicePkg)
	iOwner := strings.Index(got, "Claimed by the namespace owner")
	iOthers := strings.Index(got, "Claimed by others")
	uassert.True(t, iOwner >= 0, "the owner section exists")
	uassert.True(t, iOthers >= 0, "the others section exists")
	uassert.True(t, iOwner < iOthers, "the owner is ranked first")
	uassert.True(t, strings.Contains(got, "impostor"), "a stranger's claim is shown, not hidden")
	uassert.True(t, strings.Contains(got, "do not own"), "and is labelled as not the owner's")
}
