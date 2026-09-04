package xdao

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"

	"gno.land/p/moul/udao/v2"
)

// WhitelistDAO is a partial implementation: the constructor, ListAdmins and
// Render work; the udao.DAO proposal methods and the admin mutators are still
// `panic("not implemented")`. Pin both halves.

var alice = testutils.TestAddress("alice")

// NewWhitelistDAO reads unsafe.PreviousRealm(), which needs a real realm frame:
// a user realm gives "frame not found: cannot seek beyond origin caller override".
func TestNewWhitelistDAOSeedsCallerAsAdmin(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/test/daoone"))
	d := NewWhitelistDAO()

	admins := d.ListAdmins()
	uassert.Equal(t, 1, len(admins), "the creator is the only admin")
	uassert.True(t, admins[0].IsValid(), "the sole admin is a valid address")
}

// Note: caller-sensitivity of NewWhitelistDAO is NOT asserted here — see the
// same limitation described in p/moul/safe/v2's tests: from a `p/` test package
// unsafe.PreviousRealm() resolves to the origin regardless of SetRealm.

func TestListAdminsReflectsState(t *testing.T) {
	bob := testutils.TestAddress("bob")
	d := &WhitelistDAO{admins: []address{alice, bob}}

	admins := d.ListAdmins()
	uassert.Equal(t, 2, len(admins))
	uassert.Equal(t, alice.String(), admins[0].String())
	uassert.Equal(t, bob.String(), admins[1].String())
}

func TestRenderPlaceholder(t *testing.T) {
	d := &WhitelistDAO{admins: []address{alice}}
	// Still a placeholder — pinned so replacing it is a visible change.
	uassert.Equal(t, "TODO", d.Render(""))
	uassert.Equal(t, "TODO", d.Render("/anything"))
}

// TestImplementsUDAO is the compile-time assertion the source makes with
// `var _ udao.DAO = (*WhitelistDAO)(nil)`, restated as a test.
func TestImplementsUDAO(t *testing.T) {
	var _ udao.DAO = (*WhitelistDAO)(nil)
	uassert.True(t, true, "WhitelistDAO implements udao.DAO")
}

func TestUnimplementedMethodsPanic(cur realm, t *testing.T) {
	d := &WhitelistDAO{admins: []address{alice}}

	uassert.PanicsWithMessage(t, cur, "not implemented", func() { d.Propose(nil) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { d.GetProposalStatus(0) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { d.Execute(0) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { d.GetProposal(0) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { d.AddAdmin(alice) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { d.DelAdmin(alice) })
}
