package bfdemo

import (
	"strings"
	"testing"

	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

const hello = "++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------."

// resetState puts the realm globals back where init() left them. Realm state
// persists for the whole test binary, so every test that asserts on ids or on
// the rendered instance list has to start from here.
func resetState() {
	store = vmkit.NewStore()
	inputs = avl.NewTree()
	idgen = seqid.ID(0)
	count = 0
}

func TestUploadAndRunToCompletion(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	id := Upload(cross(cur), hello, "", 0)
	uassert.Equal(t, "halted", Step(cross(cur), id, 0))

	inst := store.Get(id)
	uassert.Equal(t, "Hello World", string(inst.Output))
	uassert.Equal(t, int64(1), inst.Slices)
	uassert.Equal(t, alice, inst.Owner)
}

// TestOneProgramAcrossManyTransactions is what the realm exists to
// demonstrate: the same computation, finished over several calls, each paying
// for its own slice.
func TestOneProgramAcrossManyTransactions(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	id := Upload(cross(cur), hello, "", 0)
	status := ""
	slices := 0
	for slices < 500 {
		status = Step(cross(cur), id, 7)
		slices++
		if status != "running" {
			break
		}
	}

	inst := store.Get(id)
	uassert.Equal(t, "halted", status)
	uassert.Equal(t, "Hello World", string(inst.Output))
	uassert.True(t, inst.Slices > 1, "took more than one slice")
}

func TestInputIsReadThroughTheHost(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	// ",[.,]" echoes its input back.
	id := Upload(cross(cur), ",[.,]", "gno.land", 0)
	uassert.Equal(t, "halted", Step(cross(cur), id, 0))
	uassert.Equal(t, "gno.land", string(store.Get(id).Output))
}

func TestBudgetStopsAProgram(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	id := Upload(cross(cur), hello, "", 12)
	uassert.Equal(t, "out of fuel", Step(cross(cur), id, 0))
	uassert.Equal(t, int64(12), store.Get(id).FuelUsed)

	// And it stays stopped rather than quietly continuing.
	uassert.AbortsContains(t, cur, "instance is out of fuel", func() {
		Step(cross(cur), id, 0)
	})
}

func TestUploadRejectsAMalformedProgram(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	// Rejected by the transaction that submitted it, not by whoever pays
	// for the first slice later.
	uassert.AbortsContains(t, cur, "unmatched", func() {
		Upload(cross(cur), "+++[", "", 0)
	})
	uassert.Equal(t, 0, count)
}

func TestRemoveIsOwnerOnly(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Upload(cross(cur), hello, "", 0)

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not your instance", func() {
		Remove(cross(cur), id)
	})

	// Anyone may pay for a slice, though: the program and its budget were
	// both fixed at upload.
	uassert.Equal(t, "halted", Step(cross(cur), id, 0))

	testing.SetRealm(testing.NewUserRealm(alice))
	Remove(cross(cur), id)
	uassert.Equal(t, 0, count)
	uassert.True(t, store.Get(id) == nil)
}

func TestOutputIsCappedAndTrapped(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	// A cell set to 1 and printed forever: an infinite writer.
	id := Upload(cross(cur), "+[.]", "", 0)
	status := Step(cross(cur), id, 0)

	inst := store.Get(id)
	uassert.Equal(t, "trapped", status)
	uassert.Equal(t, "output limit reached", inst.Trap)
	uassert.Equal(t, MaxOutput, len(inst.Output))
}

func TestRenderUnknownInstance(t *testing.T) {
	resetState()
	uassert.True(t, strings.Contains(Render("/nope"), "No such instance"))
}

// TestRenderEscapesGuestOutput pins the rule that a realm cannot be fixed in
// place once it is live: everything a caller controls is escaped before it
// reaches the page.
func TestRenderEscapesGuestOutput(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))

	// Print a backtick (96), which would otherwise close the code fence.
	src := strings.Repeat("+", 96) + "."
	id := Upload(cross(cur), src, "", 0)
	Step(cross(cur), id, 0)

	page := Render("/" + id)
	uassert.Equal(t, "`", string(store.Get(id).Output))
	uassert.True(t, strings.Contains(page, "\\x60"), "the backtick is escaped")

	// The comment text in a program never reaches the page at all: only
	// the eight operators do.
	uassert.Equal(t, "+++[-]<>", operatorsOnly("+++ this is a comment [-] </script>"))
}
