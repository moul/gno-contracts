package forge

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/urequire/v0"
)

// Deterministic, checksum-valid test addresses.
var (
	alice = testutils.TestAddress("alice") // owner
	bob   = testutils.TestAddress("bob")   // maintainer
	carol = testutils.TestAddress("carol") // writer
	dave  = testutils.TestAddress("dave")  // reader
	eve   = testutils.TestAddress("eve")   // stranger
)

// oid builds a well-formed 40-hex object id out of one hex digit.
func oid(c string) string { return strings.Repeat(c, 40) }

// newRepo returns a repo owned by alice with the standard cast: bob
// maintainer, carol writer, dave reader, eve nothing.
func newRepo(t *testing.T) (*Forge, *Repo) {
	t.Helper()
	f := New()
	r, err := f.CreateRepo(alice, 100, "moul/forge", "an on-chain forge", "")
	urequire.NoError(t, err)
	urequire.NoError(t, r.SetMember(alice, bob, RoleMaintainer))
	urequire.NoError(t, r.SetMember(alice, carol, RoleWriter))
	urequire.NoError(t, r.SetMember(alice, dave, RoleReader))
	return f, r
}
