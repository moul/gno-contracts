// Package clock is a deadline that actions push forward, with the two guards a
// naive "extend on every action" clock lacks.
//
// Any last-action-wins game has the same clock: every action buys more time, so
// the game ends only when nobody acts. Written naively it has two failure modes,
// and both have been observed on chain rather than reasoned about.
//
// The first is that it never ends. If the grant per action is constant, a
// contested pot is extended forever and the prize is always worth one more
// action. Life is the terminator: an absolute end, fixed when the clock opens,
// that no bump can pass. A game with real money in it needs one.
//
// The second is the opposite, and it shows up as soon as the grant decays to
// relieve the pressure of the first: a grant that is a share of the life left
// shrinks toward zero near the end, so the last stretch becomes too short for a
// transaction to land in, and whoever is holding when that happens simply wins.
// Floor is the anti-snipe: a bump always leaves at least that much on the
// clock, however little is left to share.
//
// Times are int64 and the unit is the caller's: block heights or unix seconds,
// as long as it is consistent. Nothing here reads the chain, so a realm can
// test its whole endgame without one.
//
// A game built on this package is at
// [r/moul/x/games/lastwords](/r/moul/x/games/lastwords/v0).
package clock

import "errors"

const maxInt64 = int64(9223372036854775807)

var (
	// ErrBadWindow is returned when the opening grant is not positive.
	ErrBadWindow = errors.New("clock: window must be positive")
	// ErrBadFloor is returned when the floor is negative or exceeds the window.
	ErrBadFloor = errors.New("clock: floor must be between zero and the window")
	// ErrBadLife is returned when the life is negative, or positive but shorter
	// than the opening window, which would close the clock before it opened.
	ErrBadLife = errors.New("clock: life must be zero (unbounded) or at least the window")
	// ErrBadShare is returned when a share is outside 0..100.
	ErrBadShare = errors.New("clock: share must be a percentage between 0 and 100")
	// ErrUnbounded is returned when a share of the remaining life is asked of a
	// clock that has no hard end to measure against.
	ErrUnbounded = errors.New("clock: a share of the life needs a bounded clock")
	// ErrOverflow is returned when the requested times do not fit in an int64.
	ErrOverflow = errors.New("clock: times overflow int64")
)

// Clock is a deadline plus the three bounds that make it terminate: the window
// a bump grants, the floor a bump always leaves, and the life it can never pass.
//
// The zero Clock is not usable; build one with New.
type Clock struct {
	start    int64
	deadline int64
	window   int64
	floor    int64
	life     int64 // 0 means unbounded
}

// New opens a clock at now, due now+window.
//
// window is what a plain Bump grants. floor is the minimum a bump leaves on the
// clock, and must not exceed the window (a floor above the window would mean
// every bump granting more than the window, which is not a floor). life is the
// total lifetime from now, after which the deadline can no longer move; zero
// leaves the clock unbounded, which is the shape that never terminates, so pass
// it deliberately.
func New(now, window, floor, life int64) (*Clock, error) {
	if window <= 0 {
		return nil, ErrBadWindow
	}
	if floor < 0 || floor > window {
		return nil, ErrBadFloor
	}
	if life < 0 || (life > 0 && life < window) {
		return nil, ErrBadLife
	}
	if window > maxInt64-now || life > maxInt64-now {
		return nil, ErrOverflow
	}
	return &Clock{
		start:    now,
		deadline: now + window,
		window:   window,
		floor:    floor,
		life:     life,
	}, nil
}

// Start returns when the clock opened.
func (c *Clock) Start() int64 { return c.start }

// Deadline returns the time the clock currently expires at.
func (c *Clock) Deadline() int64 { return c.deadline }

// Window returns the grant a plain Bump aims for.
func (c *Clock) Window() int64 { return c.window }

// Floor returns the minimum a bump leaves on the clock.
func (c *Clock) Floor() int64 { return c.floor }

// Life returns the configured lifetime, zero when unbounded.
func (c *Clock) Life() int64 { return c.life }

// HardEnd returns the time no bump can push the deadline past, or zero when the
// clock is unbounded.
func (c *Clock) HardEnd() int64 {
	if c.life == 0 {
		return 0
	}
	return c.start + c.life
}

// Expired reports whether the clock has run out at now. The deadline itself is
// past it: a clock due at 100 is expired at 100, so an action and an expiry can
// never both be valid at the same instant.
func (c *Clock) Expired(now int64) bool { return now >= c.deadline }

// Remaining returns how much time is left at now, never negative.
func (c *Clock) Remaining(now int64) int64 {
	if now >= c.deadline {
		return 0
	}
	return c.deadline - now
}

// Elapsed returns how long the clock has been open at now, never negative.
func (c *Clock) Elapsed(now int64) int64 {
	if now <= c.start {
		return 0
	}
	return now - c.start
}

// Final reports whether the deadline has reached the hard end, so no further
// bump can move it. A game should say so on its page: it is the only moment at
// which holding is worth more than acting.
func (c *Clock) Final() bool { return c.life > 0 && c.deadline >= c.HardEnd() }

// Bump extends the deadline by the window. See BumpBy for the guards.
func (c *Clock) Bump(now int64) int64 { return c.BumpBy(now, c.window) }

// BumpBy extends the deadline to now+grant and returns the new deadline.
//
// The caller owns the policy, so grant is whatever it wants: a constant, a share
// of what is left, a function of the amount paid. The clock owns the four
// invariants that policy keeps getting wrong:
//
//   - An expired clock never restarts. Once it has run out the deadline is
//     frozen, so a late action cannot reopen a settled game.
//   - The deadline never moves backwards. A small grant late in the game leaves
//     the existing deadline alone rather than shortening it.
//   - A bump always leaves at least the floor on the clock, so a decaying grant
//     cannot be shaved below the time a transaction needs to land.
//   - The deadline never passes the hard end.
func (c *Clock) BumpBy(now, grant int64) int64 {
	if c.Expired(now) {
		return c.deadline
	}
	if grant < c.floor {
		grant = c.floor
	}
	want := c.deadline
	if grant <= maxInt64-now && now+grant > want {
		want = now + grant
	} else if grant > maxInt64-now {
		want = maxInt64
	}
	if end := c.HardEnd(); c.life > 0 && want > end {
		want = end
	}
	c.deadline = want
	return c.deadline
}

// BumpShare grants pct percent of the time left until the hard end, and is the
// decaying grant a converging game wants.
//
// A grant that is a share of what is left on the DEADLINE cannot extend
// anything: now+(deadline-now)*pct/100 is always before the deadline itself. A
// share of the distance to the hard end is the one that works. Each action
// closes a fraction of the gap, so the deadline crawls toward the hard end and
// the grants shrink as it does, which is exactly the "the pot is worth one more
// action" pressure a fixed grant never relieves. The floor is what stops the
// tail of that curve from becoming too short to act in.
//
// It requires a bounded clock: there is no distance to share without one.
func (c *Clock) BumpShare(now, pct int64) (int64, error) {
	if c.life == 0 {
		return c.deadline, ErrUnbounded
	}
	if pct < 0 || pct > 100 {
		return c.deadline, ErrBadShare
	}
	left := c.HardEnd() - now
	if left < 0 {
		left = 0
	}
	var grant int64
	if left > maxInt64/100 {
		grant = left / 100 * pct // lossy, but only where exactness is meaningless
	} else {
		grant = left * pct / 100 // multiply first, so a small gap still grants
	}
	return c.BumpBy(now, grant), nil
}
