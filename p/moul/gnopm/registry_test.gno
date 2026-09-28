package gnopm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

const pkgA = "gno.land/p/moul/md/v1"

func TestRegisterAndRead(t *testing.T) {
	r := New()
	uassert.Equal(t, 0, r.Size())
	uassert.Equal(t, 0, r.Claims())

	c, err := r.Register(alice, 100, pkgA, "https://github.com/moul/gno-contracts", sha1Zero, "p/moul/md", "refs/heads/main")
	uassert.NoError(t, err)
	uassert.Equal(t, pkgA, c.PkgPath)
	uassert.Equal(t, int64(100), c.Height)
	uassert.Equal(t, int64(100), c.UpdatedAt)
	uassert.Equal(t, 1, r.Size())
	uassert.Equal(t, 1, r.Claims())

	p := r.Package(pkgA)
	uassert.True(t, p != nil, "package exists")
	uassert.Equal(t, 1, p.Count())
	uassert.True(t, p.Claim(alice) != nil, "alice's claim is there")
	uassert.True(t, p.Claim(bob) == nil, "bob has not claimed")
	uassert.True(t, r.Package("gno.land/p/moul/nope/v0") == nil, "unclaimed path is nil")
}

// A claimant re-registering must move their own commit and nothing else, and
// must not restart the clock: Height dates the claim, UpdatedAt dates the edit,
// and telling them apart is how a reader spots a claim nobody has touched since
// the first deploy.
func TestReregisterUpdatesInPlace(t *testing.T) {
	r := New()
	r.Register(alice, 100, pkgA, "https://github.com/moul/gno-contracts", sha1Zero, "p/moul/md", "")
	c, err := r.Register(alice, 250, pkgA, "https://github.com/moul/gno-contracts", sha1One, "p/moul/md", "refs/tags/v1")
	uassert.NoError(t, err)

	uassert.Equal(t, sha1One, c.Commit, "commit moved")
	uassert.Equal(t, "refs/tags/v1", c.Ref, "ref moved")
	uassert.Equal(t, int64(100), c.Height, "height still dates the original claim")
	uassert.Equal(t, int64(250), c.UpdatedAt, "updated at dates the edit")
	uassert.Equal(t, 1, r.Claims(), "still one claim, not two")
	uassert.Equal(t, 1, r.Package(pkgA).Count())
}

// Open but tagged: a second address may claim the same path. The registry has
// no opinion about which is true, and storing both is the point.
func TestSeveralClaimantsCoexist(t *testing.T) {
	r := New()
	r.Register(alice, 100, pkgA, "https://github.com/moul/gno-contracts", sha1Zero, "p/moul/md", "")
	r.Register(bob, 110, pkgA, "https://github.com/someone/fork", sha1One, "md", "")

	p := r.Package(pkgA)
	uassert.Equal(t, 2, p.Count())
	uassert.Equal(t, 2, r.Claims())
	uassert.Equal(t, 1, r.Size(), "still one package path")
	uassert.Equal(t, sha1Zero, p.Claim(alice).Commit)
	uassert.Equal(t, sha1One, p.Claim(bob).Commit)
}

func TestMaxClaimants(t *testing.T) {
	r := New()
	// Fill the path to the cap with distinct claimants.
	base := "g1ubwjz3jmrjwmpuvrsjzgy5qkxf5wrgphzmd2t"
	suffix := "023456789acdefgh"
	for i := 0; i < MaxClaimants; i++ {
		a := address(base + string(suffix[i]))
		_, err := r.Register(a, int64(100+i), pkgA, "https://example.com/x", sha1Zero, "", "")
		uassert.NoError(t, err, "claimant within the cap")
	}
	uassert.Equal(t, MaxClaimants, r.Package(pkgA).Count())

	_, err := r.Register(carol, 999, pkgA, "https://example.com/x", sha1Zero, "", "")
	uassert.ErrorIs(t, err, ErrTooManyClaimants, "one past the cap")

	// An address already at the cap can still update: the cap bounds how many
	// claimants a path carries, never how often one of them corrects itself.
	existing := address(base + string(suffix[0]))
	_, err = r.Register(existing, 999, pkgA, "https://example.com/x", sha1One, "", "")
	uassert.NoError(t, err, "an existing claimant updates at the cap")
}

func TestWithdraw(t *testing.T) {
	r := New()
	r.Register(alice, 100, pkgA, "https://example.com/x", sha1Zero, "", "")
	r.Register(bob, 101, pkgA, "https://example.com/y", sha1One, "", "")

	uassert.ErrorIs(t, r.Withdraw(carol, pkgA), ErrClaimNotFound, "withdrawing what you never said")
	uassert.ErrorIs(t, r.Withdraw(alice, "gno.land/p/moul/nope/v0"), ErrClaimNotFound, "unknown path")

	uassert.NoError(t, r.Withdraw(alice, pkgA))
	uassert.Equal(t, 1, r.Claims())
	uassert.Equal(t, 1, r.Size(), "bob's claim keeps the path alive")
	uassert.True(t, r.Package(pkgA).Claim(alice) == nil, "alice is gone")
	uassert.True(t, r.Package(pkgA).Claim(bob) != nil, "bob is untouched")

	uassert.NoError(t, r.Withdraw(bob, pkgA))
	uassert.Equal(t, 0, r.Claims())
	uassert.Equal(t, 0, r.Size(), "the last withdrawal removes the path")
	uassert.True(t, r.Package(pkgA) == nil)
}

func TestRegisterRejectsInvalidInput(t *testing.T) {
	good := func() (string, string, string, string, string) {
		return pkgA, "https://github.com/moul/gno-contracts", sha1Zero, "p/moul/md", "refs/heads/main"
	}
	cases := []struct {
		name string
		mut  func(p, repo, commit, dir, ref *string)
		want error
	}{
		{"bad path", func(p, _, _, _, _ *string) { *p = "nonsense" }, ErrInvalidPkgPath},
		{"bad repo scheme", func(_, repo, _, _, _ *string) { *repo = "javascript:alert(1)" }, ErrInvalidRepo},
		{"abbreviated commit", func(_, _, c, _, _ *string) { *c = "0123456" }, ErrInvalidCommit},
		{"absolute dir", func(_, _, _, d, _ *string) { *d = "/etc" }, ErrInvalidDir},
		{"unqualified ref", func(_, _, _, _, rf *string) { *rf = "main" }, ErrInvalidRef},
	}
	for _, tc := range cases {
		r := New()
		p, repo, commit, dir, ref := good()
		tc.mut(&p, &repo, &commit, &dir, &ref)
		_, err := r.Register(alice, 100, p, repo, commit, dir, ref)
		uassert.ErrorIs(t, err, tc.want, tc.name)
		uassert.Equal(t, 0, r.Claims(), tc.name+": nothing stored")
	}
}

func TestOwnedBy(t *testing.T) {
	names := resolver(map[string]address{"moul": alice})
	r := New()

	c, _ := r.Register(alice, 100, pkgA, "https://example.com/x", sha1Zero, "", "")
	uassert.True(t, c.OwnedBy(names), "the namespace holder claiming their own package")

	c2, _ := r.Register(bob, 101, pkgA, "https://example.com/y", sha1One, "", "")
	uassert.False(t, c2.OwnedBy(names), "a stranger claiming someone else's package")

	// An address namespace belongs to that account with nothing registered, so
	// it resolves with no name lookup at all.
	own := "gno.land/r/" + addrNS + "/scratch/v0"
	c3, err := r.Register(address(addrNS), 102, own, "https://example.com/z", sha1Zero, "", "")
	uassert.NoError(t, err)
	uassert.True(t, c3.OwnedBy(nil), "an address namespace needs no resolver")

	c4, _ := r.Register(bob, 103, own, "https://example.com/w", sha1One, "", "")
	uassert.False(t, c4.OwnedBy(nil), "a stranger in someone's address namespace")

	// An unregistered name is held by nobody, so nobody owns it.
	other := "gno.land/p/nobody/thing/v0"
	c5, _ := r.Register(alice, 104, other, "https://example.com/v", sha1Zero, "", "")
	uassert.False(t, c5.OwnedBy(names), "an unheld namespace is owned by no one")
	uassert.False(t, c5.OwnedBy(nil), "and a nil resolver never invents ownership")

	// A resolver may return an address AND report the name as not held: that is
	// what r/sys/users does for a name whose record survives but is no longer
	// current. The address matching is not enough, the name has to still be
	// held, and dropping the second half of that test is a silent promotion of
	// a stranger's claim.
	stale := func(string) (address, bool) { return alice, false }
	uassert.False(t, c.OwnedBy(stale), "a resolved but unheld name confers nothing")
}

func TestSourceURL(t *testing.T) {
	r := New()
	c, _ := r.Register(alice, 100, pkgA, "https://github.com/moul/gno-contracts", sha1Zero, "p/moul/md", "")
	uassert.Equal(t, "https://github.com/moul/gno-contracts/tree/"+sha1Zero+"/p/moul/md", c.SourceURL())

	c2, _ := r.Register(bob, 100, pkgA, "https://github.com/x/y/", sha1One, "", "")
	uassert.Equal(t, "https://github.com/x/y/tree/"+sha1One, c2.SourceURL(), "root package, trailing slash trimmed")
}

func TestIteration(t *testing.T) {
	r := New()
	paths := []string{
		"gno.land/p/alice/one/v0",
		"gno.land/p/moul/md/v1",
		"gno.land/p/moul/ulist/v0",
		"gno.land/r/moul/home",
		"gno.land/p/zed/last/v0",
	}
	for i, p := range paths {
		_, err := r.Register(alice, int64(100+i), p, "https://example.com/x", sha1Zero, "", "")
		uassert.NoError(t, err, p)
	}

	var seen []string
	r.IteratePackages(0, 10, func(p *Package) bool {
		seen = append(seen, p.PkgPath)
		return false
	})
	uassert.Equal(t, 5, len(seen))
	uassert.Equal(t, "gno.land/p/alice/one/v0", seen[0], "lexical order")
	uassert.Equal(t, "gno.land/r/moul/home", seen[4], "r sorts after p")

	// A namespace walk must stop at the prefix boundary rather than running to
	// the end of the tree: "moul" is followed by "zed" and by the r/ half.
	var ns []string
	r.IterateNamespace("gno.land", "p", "moul", func(p *Package) bool {
		ns = append(ns, p.PkgPath)
		return false
	})
	uassert.Equal(t, 2, len(ns), "only p/moul")
	uassert.Equal(t, "gno.land/p/moul/md/v1", ns[0])
	uassert.Equal(t, "gno.land/p/moul/ulist/v0", ns[1])

	// Stopping early stops.
	count := 0
	r.IteratePackages(0, 10, func(p *Package) bool {
		count++
		return true
	})
	uassert.Equal(t, 1, count, "returning true stops the walk")
}
