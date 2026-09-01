package streaks

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	streaks = avl.Tree{}
}

func TestCheckinFirstTimeStartsStreak(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	checkin(alice, 100)

	r, ok := get(alice)
	if !ok {
		t.Fatal("expected a record after first check-in")
	}
	if r.current != 1 || r.longest != 1 || r.total != 1 {
		t.Fatalf("expected current=1 longest=1 total=1, got current=%d longest=%d total=%d", r.current, r.longest, r.total)
	}
}

func TestCheckinWithinGraceExtendsStreak(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	checkin(alice, 100)
	checkin(alice, 150) // gap of 50 <= graceBlocks(100)
	checkin(alice, 200) // gap of 50 again

	r, _ := get(alice)
	if r.current != 3 {
		t.Fatalf("expected streak of 3, got %d", r.current)
	}
	if r.longest != 3 {
		t.Fatalf("expected longest of 3, got %d", r.longest)
	}
}

func TestCheckinAfterGraceResetsStreak(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	checkin(alice, 100)
	checkin(alice, 150)
	checkin(alice, 400) // gap of 250 > graceBlocks(100): lapsed

	r, _ := get(alice)
	if r.current != 1 {
		t.Fatalf("expected streak reset to 1, got %d", r.current)
	}
	if r.longest != 2 {
		t.Fatalf("expected longest to stay at 2, got %d", r.longest)
	}
	if r.total != 3 {
		t.Fatalf("expected total check-ins of 3, got %d", r.total)
	}
}

func TestCheckinSameOrEarlierHeightPanics(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	checkin(alice, 100)

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic checking in at a non-later height")
		}
	}()
	checkin(alice, 100)
}

func TestProjectReportsLapsedWithoutMutating(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	checkin(alice, 100)

	r, _ := get(alice)
	current, alive := project(r, 100+graceBlocks+1)
	if alive || current != 0 {
		t.Fatalf("expected lapsed projection (0, false), got (%d, %v)", current, alive)
	}
	// Stored state must be untouched by a read-only projection.
	if r.current != 1 {
		t.Fatalf("project must not mutate stored state, got current=%d", r.current)
	}
}

func TestCurrentStreakAndLongestStreakQueries(t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	checkin(alice, 100)
	checkin(alice, 150)

	if got := LongestStreak(alice.String()); got != 2 {
		t.Fatalf("LongestStreak() = %d, want 2", got)
	}
	if got := LongestStreak(testutils.TestAddress("bob").String()); got != 0 {
		t.Fatalf("LongestStreak() for unknown address = %d, want 0", got)
	}
}

func TestRenderShowsEmptyThenLeaderboardThenDetail(t *testing.T) {
	resetState()
	if !strings.Contains(Render(""), "Nobody has checked in yet") {
		t.Fatal("expected empty-state placeholder")
	}

	alice := testutils.TestAddress("alice")
	checkin(alice, 100)

	out := Render("")
	if !strings.Contains(out, "Rank") {
		t.Fatal("expected leaderboard table in root render")
	}

	detail := Render(alice.String())
	if !strings.Contains(detail, "Current streak") {
		t.Fatal("expected detail card to show current streak")
	}

	if !strings.Contains(Render(testutils.TestAddress("bob").String()), "No check-ins yet") {
		t.Fatal("expected placeholder for an address with no check-ins")
	}
}

// TestCheckInViaCrossingCall smoke-tests the exported, realm-crossing entry
// point end to end (as an on-chain caller would invoke it).
func TestCheckInViaCrossingCall(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	msg := CheckIn(cross(cur))
	if !strings.Contains(msg, "checked in") {
		t.Fatalf("expected check-in confirmation, got %q", msg)
	}
	if _, ok := get(alice); !ok {
		t.Fatal("expected a record to be persisted for caller")
	}
}
