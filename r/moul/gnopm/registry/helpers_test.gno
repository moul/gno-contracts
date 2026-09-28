package registry

import (
	pm "gno.land/p/moul/gnopm/v0"
	"gno.land/p/nt/testutils/v0"
)

// Deterministic, checksum-valid test addresses. Made rather than typed: the
// address-namespace rule turns on the bech32 alphabet, which drops 1, b, i and
// o, so a plausible-looking hand-written "g1..." fails the check for a reason
// that has nothing to do with what is under test.
var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")

	// alicePkg sits in alice's OWN address namespace, which is the only
	// ownership a test can create: r/sys/users is not writable from a unit
	// test, so a name namespace can never resolve to a test account.
	alicePkg = "gno.land/r/" + alice.String() + "/scratch/v0"
)

const (
	repoURL  = "https://github.com/moul/gno-contracts"
	sha1Zero = "0000000000000000000000000000000000000000"
	sha1One  = "1111111111111111111111111111111111111111"
	otherPkg = "gno.land/p/moul/md/v1"
)

// reset puts the realm back to its initial state. Realm globals persist for the
// whole test binary and examples run after every Test, so anything that renders
// starts from a known tree or its pinned output silently depends on test order.
func reset() { reg = pm.New() }

// seedFixture builds a deterministic registry straight through the library: no
// chain context needed, which is what lets an Example use it. Going through the
// library rather than through Register also skips the crossing call, which an
// example cannot make.
func seedFixture() {
	reset()
	reg.Register(alice, 100, alicePkg, repoURL, sha1Zero, "scratch", "refs/tags/v0.1.0")
	reg.Register(bob, 110, alicePkg, "https://github.com/bob/impostor", sha1One, "", "")
	reg.Register(alice, 120, otherPkg, repoURL, sha1One, "p/moul/md", "")
}
