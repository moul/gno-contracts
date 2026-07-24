package timecapsule

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func resetState() {
	capsules = avl.Tree{}
	nextID = 0
}

func TestLeaveAndReveal(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	id := Leave(cross(cur), "hello, future", 5)
	uassert.Equal(t, int64(0), id)

	if got := Render(""); !strings.Contains(got, "1 still sealed") {
		t.Fatalf("expected capsule to still be sealed, got: %s", got)
	}
	if got := Render("sealed"); !strings.Contains(got, "capsule/0") {
		t.Fatalf("expected capsule 0 listed as sealed, got: %s", got)
	}

	testing.SkipHeights(5)

	if got := Render(""); !strings.Contains(got, "hello, future") {
		t.Fatalf("expected capsule to be revealed, got: %s", got)
	}
	if got := Render("capsule/0"); !strings.Contains(got, "hello, future") {
		t.Fatalf("expected capsule detail to reveal message, got: %s", got)
	}
}

func TestLeaveRejectsEmptyMessage(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	uassert.AbortsWithMessage(t, cur, "message must not be empty", func() {
		Leave(cross(cur), "   ", 5)
	})
}

func TestLeaveRejectsBadDelay(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	uassert.AbortsWithMessage(t, cur, "delayBlocks out of range", func() {
		Leave(cross(cur), "hi", 0)
	})
}

// Regression: an intermediate realm (not a direct EOA call) must never be
// able to seal a capsule as if it were a user.
func TestLeaveRejectsCodeRealm(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/some/attacker"))

	uassert.AbortsWithMessage(t, cur, "only direct user calls can leave a capsule", func() {
		Leave(cross(cur), "hi", 5)
	})
}

func TestRenderNotFound(t *testing.T) {
	resetState()
	if got := Render("nope"); !strings.Contains(got, "not found") {
		t.Fatalf("expected 404-ish message, got: %s", got)
	}
}
