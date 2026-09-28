// Package accrual is stock that fills at a rate while nobody is playing: the
// resource field of an idle game, the warehouse of a 4X, anything whose state
// is a function of how long it has been left alone.
//
// The shape is always the same. Store what you had and when, and compute the
// rest on demand; a player who does nothing for a month costs nothing, and the
// realm needs no cron, no keeper and no per-block hook. That much is obvious.
// What is not obvious is that the obvious implementation is wrong in three
// ways, each of which has been observed in this repository rather than
// reasoned about.
//
// # 1. Re-anchoring to now makes acting more often pay
//
// Written naively, a claim advances the anchor to now and computes
// elapsed/Period whole periods of production. The division truncates, so every
// claim silently forfeits the part-period it lands in, and a player who claims
// twice forfeits twice. Run in reverse on a decaying stat it is worse than
// unfair, it is free: [r/moul/x/daily/tamagotchi] decayed by elapsed/2 and
// elapsed/3, so at elapsed == 1 it decayed by nothing at all, and feeding once
// per block made the pet immortal while every other cadence died inside 240
// blocks. It was fixed in #221.
//
// The invariant that rules it out is worth stating on its own, because it is
// the whole contract of this package:
//
//	Advance(s, a, c) == Advance(Advance(s, a, b), b, c)   for a <= b <= c
//
// How often you call must not change where you end up. [Rate.Advance] gets
// there by advancing the anchor only by the WHOLE periods it paid for, leaving
// the remainder on the clock rather than throwing it away. TestSplitInvariant
// asserts it over pseudo-random partitions rather than over a handful of
// hand-picked spans, because the hand-picked spans are exactly the ones a
// wrong implementation already passes.
//
// # 2. A view that does not share the write path's arithmetic drifts from it
//
// The same realm had a second copy of the decay for its Render, so the page
// showed a pet the next call would not honour. Two implementations of one rule
// means one of them is the stale one somebody acts on. Here there is one
// function: [Rate.At] is [Rate.Advance] with the anchor discarded, so a view
// cannot disagree with a write even in principle.
//
// # 3. A projection that is not closed form cannot be rendered at all
//
// Render runs under a query gas limit and may not write, so whatever it
// computes has to be bounded however long the player was away. Anything
// iterative, stepping a simulation once per block, is fine in a transaction
// and unusable in a page: the player who comes back after a month is exactly
// the one whose page times out. Everything here is O(1) in elapsed time, which
// is the property that makes a live-updating page possible, not an
// optimisation.
//
// Times are int64 and the unit is the caller's, block heights or unix seconds,
// as long as it is consistent. Prefer a timestamp: a block-height rate drifts
// in wall-clock terms every time the chain's block time moves, and gno.land's
// has moved from about 4.1s to 3.405s inside one month. Nothing here reads the
// chain, so a realm can test a year of its own economy without one.
//
// A game built on this package is at
// [r/moul/x/games/idle](/r/moul/x/games/idle/v0).
//
// [r/moul/x/daily/tamagotchi]: /r/moul/x/daily/tamagotchi/v0
package accrual

import "errors"

const maxInt64 = int64(9223372036854775807)

var (
	// ErrBadAmount is returned when the amount produced per period is not
	// positive. A zero rate is a bug in the caller, not a valid still life:
	// it makes Full unanswerable and every Advance a no-op.
	ErrBadAmount = errors.New("accrual: amount must be positive")
	// ErrBadPeriod is returned when the period is not positive.
	ErrBadPeriod = errors.New("accrual: period must be positive")
	// ErrBadCap is returned when the cap is negative. Zero is legal and
	// means unbounded.
	ErrBadCap = errors.New("accrual: cap must not be negative")
	// ErrNegativeStock is returned when the stock handed in is negative,
	// which would let a caller mint by going through zero.
	ErrNegativeStock = errors.New("accrual: stock must not be negative")
	// ErrBackwards is returned when now falls before the anchor. Time moving
	// backwards is a caller bug (a stored anchor from another clock, a test
	// that rewound), and silently treating it as zero elapsed would hide it.
	ErrBackwards = errors.New("accrual: now must not fall before the anchor")
	// ErrOverflow is returned when the arithmetic would wrap int64.
	ErrOverflow = errors.New("accrual: int64 overflow")
)

// Rate is production per unit of time, against a ceiling. Construct with New
// so the invariants are checked once instead of on every call.
type Rate struct {
	Amount int64 // produced each whole Period
	Period int64 // time units in one period
	Cap    int64 // ceiling on the stock; zero means unbounded
}

// New validates and returns a Rate. A zero cap means unbounded.
func New(amount, period, capacity int64) (Rate, error) {
	if amount <= 0 {
		return Rate{}, ErrBadAmount
	}
	if period <= 0 {
		return Rate{}, ErrBadPeriod
	}
	if capacity < 0 {
		return Rate{}, ErrBadCap
	}
	return Rate{Amount: amount, Period: period, Cap: capacity}, nil
}

// Advance returns the stock and the new anchor at time now, given stock held
// since anchor.
//
// The new anchor is NOT now. It is the anchor plus the whole periods actually
// paid out, so the part-period in progress stays on the clock and splitting a
// span into pieces yields exactly what advancing it in one go would:
//
//	Advance(s, a, c) == Advance(Advance(s, a, b), b, c)   for a <= b <= c
//
// Production past the cap is lost, which is what a cap is for. Saturation is
// idempotent, so it does not break the equality above, and it means a CAPPED
// rate can never return ErrOverflow: the answer is the cap however long the
// player was away. Only an uncapped rate can run out of int64.
func (r Rate) Advance(stock, anchor, now int64) (int64, int64, error) {
	if err := r.check(); err != nil {
		return 0, 0, err
	}
	if stock < 0 {
		return 0, 0, ErrNegativeStock
	}
	if now < anchor {
		return 0, 0, ErrBackwards
	}
	// now-anchor wraps only when the anchor is negative and now is far
	// enough above it. maxInt64+anchor is safe to compute precisely because
	// anchor is negative there.
	if anchor < 0 && now > maxInt64+anchor {
		return 0, 0, ErrOverflow
	}

	periods := (now - anchor) / r.Period

	// The anchor only moves by what was paid for. periods*r.Period cannot
	// overflow, it is at most now-anchor, and adding it back cannot pass now.
	newAnchor := anchor + periods*r.Period

	if r.Cap > 0 && stock >= r.Cap {
		return stock, newAnchor, nil
	}

	// Production is only computed when its exact value can matter. A capped
	// rate whose payout would wrap int64 has an answer regardless of what
	// that payout is, so it gets one instead of an error.
	if periods > maxInt64/r.Amount {
		return r.saturate(newAnchor)
	}
	produced := periods * r.Amount
	if produced > maxInt64-stock {
		return r.saturate(newAnchor)
	}

	total := stock + produced
	if r.Cap > 0 && total > r.Cap {
		total = r.Cap
	}
	return total, newAnchor, nil
}

// saturate answers an accrual too large for int64: the cap if there is one,
// and an error if there is not. A capped Rate therefore never overflows,
// which is the property that lets a realm size a warehouse without also
// having to bound its own lifetime.
func (r Rate) saturate(newAnchor int64) (int64, int64, error) {
	if r.Cap == 0 {
		return 0, 0, ErrOverflow
	}
	return r.Cap, newAnchor, nil
}

// At is Advance with the anchor discarded: the read-only view of the same
// arithmetic, for a Render that must not write. It is defined in terms of
// Advance on purpose, so a page can never show a number a write would not
// honour.
func (r Rate) At(stock, anchor, now int64) (int64, error) {
	got, _, err := r.Advance(stock, anchor, now)
	return got, err
}

// Full returns the time at which the stock first reaches the cap, for a realm
// that wants to tell a player when their production starts being wasted.
//
// An uncapped rate returns zero, meaning never. A stock already at or past the
// cap returns the anchor, meaning now.
func (r Rate) Full(stock, anchor int64) (int64, error) {
	if err := r.check(); err != nil {
		return 0, err
	}
	if stock < 0 {
		return 0, ErrNegativeStock
	}
	if r.Cap == 0 {
		return 0, nil
	}
	if stock >= r.Cap {
		return anchor, nil
	}

	// Whole periods needed to cover the shortfall, rounded UP: the cap is
	// reached by the payout that crosses it, not by the one before.
	need := r.Cap - stock
	periods := need / r.Amount
	if need%r.Amount != 0 {
		periods++
	}
	if periods > maxInt64/r.Period {
		return 0, ErrOverflow
	}
	span := periods * r.Period
	if span > maxInt64-anchor {
		return 0, ErrOverflow
	}
	return anchor + span, nil
}

// check rejects a zero Rate built by struct literal instead of New, so a
// caller that skipped the constructor gets the same error it would have.
func (r Rate) check() error {
	if r.Amount <= 0 {
		return ErrBadAmount
	}
	if r.Period <= 0 {
		return ErrBadPeriod
	}
	if r.Cap < 0 {
		return ErrBadCap
	}
	return nil
}
