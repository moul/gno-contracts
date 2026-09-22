package clock

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func mustNew(t *testing.T, now, window, floor, life int64) *Clock {
	t.Helper()
	c, err := New(now, window, floor, life)
	uassert.NoError(t, err)
	return c
}

func TestNewValidation(t *testing.T) {
	cases := []struct {
		name                     string
		now, window, floor, life int64
		want                     error
	}{
		{"zero window", 0, 0, 0, 0, ErrBadWindow},
		{"negative window", 0, -1, 0, 0, ErrBadWindow},
		{"negative floor", 0, 100, -1, 0, ErrBadFloor},
		{"floor above window", 0, 100, 101, 0, ErrBadFloor},
		{"negative life", 0, 100, 10, -1, ErrBadLife},
		{"life shorter than window", 0, 100, 10, 99, ErrBadLife},
		{"window overflows", maxInt64 - 5, 100, 0, 0, ErrOverflow},
		{"life overflows", maxInt64 - 500, 100, 0, 1000, ErrOverflow},
		{"unbounded is legal", 0, 100, 10, 0, nil},
		{"life equal to window is legal", 0, 100, 10, 100, nil},
		{"floor equal to window is legal", 0, 100, 100, 0, nil},
	}
	for _, tc := range cases {
		_, err := New(tc.now, tc.window, tc.floor, tc.life)
		if tc.want == nil {
			uassert.NoError(t, err, tc.name)
			continue
		}
		uassert.ErrorIs(t, err, tc.want, tc.name)
	}
}

func TestOpensDueAtWindow(t *testing.T) {
	c := mustNew(t, 1000, 100, 10, 500)
	uassert.Equal(t, int64(1000), c.Start())
	uassert.Equal(t, int64(1100), c.Deadline())
	uassert.Equal(t, int64(1500), c.HardEnd())
	uassert.Equal(t, int64(100), c.Remaining(1000))
	uassert.Equal(t, int64(0), c.Elapsed(1000))
	uassert.False(t, c.Expired(1099))
	uassert.True(t, c.Expired(1100), "the deadline itself is expired")
	uassert.False(t, c.Final())
}

func TestUnboundedHasNoHardEnd(t *testing.T) {
	c := mustNew(t, 0, 100, 0, 0)
	uassert.Equal(t, int64(0), c.HardEnd())
	uassert.False(t, c.Final(), "an unbounded clock is never final")
	c.Bump(90)
	c.Bump(180)
	uassert.Equal(t, int64(280), c.Deadline(), "nothing caps it")
}

// TestBumpNeverMovesBackwards is the invariant a caller supplying its own grant
// gets wrong first: a late, small grant must not shorten the clock.
func TestBumpNeverMovesBackwards(t *testing.T) {
	c := mustNew(t, 0, 1000, 0, 0)
	uassert.Equal(t, int64(1000), c.Deadline())

	uassert.Equal(t, int64(1000), c.BumpBy(10, 5), "now+5 is before the deadline")
	uassert.Equal(t, int64(1000), c.BumpBy(900, 0), "a zero grant leaves it alone")
	uassert.Equal(t, int64(1100), c.BumpBy(900, 200), "a grant past the deadline moves it")
}

// TestFloorSurvivesATinyGrant is the anti-snipe: whatever the policy grants, a
// bump leaves at least the floor, so the last stretch stays reachable.
func TestFloorSurvivesATinyGrant(t *testing.T) {
	c := mustNew(t, 0, 1000, 50, 0)
	c.BumpBy(990, 1)
	uassert.Equal(t, int64(1040), c.Deadline(), "1 was raised to the floor of 50")
	uassert.Equal(t, int64(50), c.Remaining(990))

	c2 := mustNew(t, 0, 1000, 50, 0)
	c2.BumpBy(990, 0)
	uassert.Equal(t, int64(50), c2.Remaining(990), "even a zero grant leaves the floor")
}

// TestHardEndCapsEveryBump is the terminator: without it a contested clock is
// extended forever and the game has no end.
func TestHardEndCapsEveryBump(t *testing.T) {
	c := mustNew(t, 0, 100, 10, 250)
	uassert.Equal(t, int64(250), c.HardEnd())

	c.BumpBy(90, 100)
	uassert.Equal(t, int64(190), c.Deadline())
	c.BumpBy(180, 100)
	uassert.Equal(t, int64(250), c.Deadline(), "capped at the hard end, not 280")
	uassert.True(t, c.Final())

	c.BumpBy(240, 1000000)
	uassert.Equal(t, int64(250), c.Deadline(), "the cap holds against any grant")
	uassert.Equal(t, int64(10), c.Remaining(240), "and it beats the floor")
}

// TestExpiredClockNeverRestarts stops a late action from reopening a settled
// game, which is the difference between a closed pot and a stolen one.
func TestExpiredClockNeverRestarts(t *testing.T) {
	c := mustNew(t, 0, 100, 10, 0)
	uassert.True(t, c.Expired(100))
	uassert.Equal(t, int64(100), c.BumpBy(100, 500), "exactly at the deadline")
	uassert.Equal(t, int64(100), c.Bump(5000), "long after")
	uassert.Equal(t, int64(0), c.Remaining(100))

	settled := mustNew(t, 0, 100, 10, 1000)
	uassert.True(t, settled.Expired(100))
	got, err := settled.BumpShare(200, 50)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(100), got, "not even a large share reopens it")
}

func TestBumpShareValidation(t *testing.T) {
	c := mustNew(t, 0, 100, 0, 500)
	_, err := c.BumpShare(10, -1)
	uassert.ErrorIs(t, err, ErrBadShare)
	_, err = c.BumpShare(10, 101)
	uassert.ErrorIs(t, err, ErrBadShare)
	uassert.Equal(t, int64(100), c.Deadline(), "a rejected share changes nothing")

	unbounded := mustNew(t, 0, 100, 0, 0)
	_, err = unbounded.BumpShare(10, 50)
	uassert.ErrorIs(t, err, ErrUnbounded, "no hard end, nothing to take a share of")
}

// TestBumpShareDecays is why the share grant exists: each action closes a
// fraction of the gap to the hard end, so the grants shrink as the game runs
// and the pressure to act one more time is relieved instead of compounding.
func TestBumpShareDecays(t *testing.T) {
	c := mustNew(t, 0, 100, 1, 1000)
	first, err := c.BumpShare(10, 50)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(505), first, "half the 990 left to the hard end")

	second, err := c.BumpShare(500, 50)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(750), second, "half of the 500 now left, a smaller grant")

	third, err := c.BumpShare(700, 50)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(850), third, "smaller again")
	uassert.True(t, third < c.HardEnd(), "it approaches the hard end without reaching it")
}

// TestBumpShareRoundingStillGrants is the multiply-first lesson: a share of a
// gap smaller than the divisor must not truncate to a zero grant.
func TestBumpShareRoundingStillGrants(t *testing.T) {
	// 52 due, 50 left to the hard end: a tenth of that is 5, and dividing
	// before multiplying would truncate it to a grant of zero.
	c := mustNew(t, 0, 52, 0, 100)
	got, err := c.BumpShare(50, 10)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(55), got, "a tenth of the 50 left is 5, not 0")
}

func TestBumpShareRespectsFloorAndCap(t *testing.T) {
	c := mustNew(t, 0, 100, 20, 150)
	got, err := c.BumpShare(95, 10) // a tenth of the 55 left is 5, floored to 20
	uassert.NoError(t, err)
	uassert.Equal(t, int64(115), got)

	got, err = c.BumpShare(110, 100) // would be 150 exactly, and never past it
	uassert.NoError(t, err)
	uassert.Equal(t, int64(150), got)
	uassert.True(t, c.Final())
}

// TestHugeGrantDoesNotWrap keeps a bump total at the extremes: a wrapped
// deadline would land in the past and settle the game instantly.
func TestHugeGrantDoesNotWrap(t *testing.T) {
	c := mustNew(t, 0, 100, 0, 0)
	uassert.Equal(t, maxInt64, c.BumpBy(50, maxInt64), "clamped, not wrapped")
	uassert.True(t, c.Deadline() > 0)

	big := mustNew(t, maxInt64/2, 1000, 0, maxInt64/4)
	got, err := big.BumpShare(maxInt64/2+1, 100)
	uassert.NoError(t, err)
	uassert.True(t, got > maxInt64/2, "a huge remaining share does not wrap")
}

func TestElapsedAndRemainingAreNeverNegative(t *testing.T) {
	c := mustNew(t, 100, 100, 0, 0)
	uassert.Equal(t, int64(0), c.Elapsed(50), "before the start")
	uassert.Equal(t, int64(100), c.Remaining(100))
	uassert.Equal(t, int64(0), c.Remaining(9999), "long past the deadline")
	uassert.Equal(t, int64(9899), c.Elapsed(9999))
}
