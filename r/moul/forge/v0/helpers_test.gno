package forge

import (
	"strings"

	fg "gno.land/p/moul/forge/v0"
	"gno.land/p/nt/testutils/v0"
)

// Deterministic, checksum-valid test addresses.
var (
	alice = testutils.TestAddress("alice") // owner
	bob   = testutils.TestAddress("bob")   // maintainer
	carol = testutils.TestAddress("carol") // writer
	eve   = testutils.TestAddress("eve")   // stranger
)

// Repo ids used by the crossing tests. The realm only lets an address create
// under a namespace it owns, and no user name is registered in a unit test, so
// these are all address namespaces.
var (
	demoID    = alice.String() + "/demo"
	heightsID = alice.String() + "/heights"
	rolesID   = alice.String() + "/roles"
	ghostID   = alice.String() + "/ghost"
)

func oid(c string) string { return strings.Repeat(c, 40) }

// reset restores realm state to empty. Realm globals persist for the whole test
// binary and examples run after every Test, so anything that pins Render output
// must reset and re-seed first.
func reset() { f = fg.New() }

// seedFixture builds one deterministic repo straight through the library: no
// chain context needed, which is what lets an Example use it. It can use a name
// namespace because namespace ownership is a realm rule (it needs a chain to
// resolve a name); the library validates the shape and nothing more.
func seedFixture() {
	reset()
	r, err := f.CreateRepo(alice, 100, "moul/forge", "an on chain software forge", "")
	if err != nil {
		panic(err)
	}
	if err := r.SetMember(alice, bob, fg.RoleMaintainer); err != nil {
		panic(err)
	}
	if err := r.SetMember(alice, carol, fg.RoleWriter); err != nil {
		panic(err)
	}
	if err := r.SetMirrors(alice, []string{"https://github.com/moul/gno-contracts.git"}); err != nil {
		panic(err)
	}
	if _, err := r.SetRef(carol, 101, "refs/heads/main", "", oid("a"), "initial import"); err != nil {
		panic(err)
	}
	if _, err := r.SetRef(carol, 102, "refs/heads/main", oid("a"), oid("b"), "add the log"); err != nil {
		panic(err)
	}
	if _, err := r.OpenIssue(eve, 103, "force pushes are invisible", "A maintainer can rewrite a branch and nothing records it.", []string{"bug"}); err != nil {
		panic(err)
	}
	if _, err := r.CommentIssue(bob, 104, 0, "that is what the log is for"); err != nil {
		panic(err)
	}
	c, err := r.OpenChange(carol, 105, "record every ref move", "closes 0", "", "refs/heads/feat", oid("c"), "refs/heads/main")
	if err != nil {
		panic(err)
	}
	if err := r.ReviewChange(bob, 106, c.ID, fg.VerdictApprove, "lgtm"); err != nil {
		panic(err)
	}
}
