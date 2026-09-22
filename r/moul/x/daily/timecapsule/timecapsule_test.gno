package timecapsule

import (
	"strings"
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func resetState() {
	capsules = store.Named("capsule")
}

func TestLeaveAndReveal(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	// v1 ids start at 1: the store never assigns 0, so the zero id stays
	// usable as "absent". v0 handed out 0 for the first capsule.
	id := Leave(cross(cur), "hello, future", 5)
	uassert.Equal(t, int64(1), id)

	if got := Render(""); !strings.Contains(got, "1 still sealed") {
		t.Fatalf("expected capsule to still be sealed, got: %s", got)
	}
	if got := Render("sealed"); !strings.Contains(got, "capsule/1") {
		t.Fatalf("expected capsule 1 listed as sealed, got: %s", got)
	}

	testing.SkipHeights(5)

	if got := Render(""); !strings.Contains(got, "hello, future") {
		t.Fatalf("expected capsule to be revealed, got: %s", got)
	}
	if got := Render("capsule/1"); !strings.Contains(got, "hello, future") {
		t.Fatalf("expected capsule detail to reveal message, got: %s", got)
	}

	// Id 0 is never assigned, so the path is rejected rather than looked up.
	if got := Render("capsule/0"); !strings.Contains(got, "Invalid capsule id") {
		t.Fatalf("expected capsule/0 to be rejected, got: %s", got)
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
