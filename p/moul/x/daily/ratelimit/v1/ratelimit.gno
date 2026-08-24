// Package ratelimit is a deterministic token-bucket rate limiter — a port of
// golang.org/x/time/rate with the wall clock replaced by a caller-supplied
// monotonic tick (on-chain, that tick is the block height).
//
// It is a pure library: it imports no chain APIs and reads no ambient state.
// A [Limiter] owns a set of per-key token buckets sharing one rate/burst
// config; the caller decides what a key is (typically an address string) and
// supplies the current tick on every call. Between two observations at ticks
// `last` and `now`, a bucket gains (now-last)*rate tokens, capped at `burst`.
// Everything is integer/float arithmetic over persistent avl state, hence
// deterministic and replayable.
//
// A realm wires it up by holding a *Limiter in a package-level var and feeding
// it runtime.ChainHeight() as the tick. For a complete, live example see the
// demo realm [r/moul/x/daily/ratelimitdemo](/r/moul/x/daily/ratelimitdemo/v1).
package ratelimit

import "gno.land/p/nt/avl/v0"

// bucket is the per-key state persisted in the avl tree.
type bucket struct {
	tokens float64 // tokens available as of `last`
	last   int64   // tick at which `tokens` was computed
}

// Limiter is a set of per-key token buckets sharing one rate/burst config.
// The zero value is not usable; construct one with [New].
type Limiter struct {
	rate    float64   // tokens replenished per tick
	burst   float64   // bucket capacity (max tokens, largest single burst)
	buckets *avl.Tree // key string -> *bucket, ordered by key (deterministic)
}

// New returns a Limiter replenishing `rate` tokens per tick, each bucket capped
// at `burst`. rate is clamped to >= 0, burst to >= 1.
func New(rate, burst float64) *Limiter {
	l := &Limiter{buckets: avl.NewTree()}
	l.SetConfig(rate, burst)
	return l
}

// SetConfig updates the shared rate and burst. rate is clamped to >= 0, burst
// to >= 1. Existing buckets keep their stored tokens; the new config applies
// from the next refill.
func (l *Limiter) SetConfig(rate, burst float64) {
	if rate < 0 {
		rate = 0
	}
	if burst < 1 {
		burst = 1
	}
	l.rate = rate
	l.burst = burst
}

// Config returns the current rate (tokens/tick) and burst (capacity).
func (l *Limiter) Config() (rate, burst float64) { return l.rate, l.burst }

// Allow consumes one token for `key` at tick `now` and reports whether the
// request is permitted. When the bucket is empty it returns false and consumes
// nothing. Equivalent to AllowN(key, now, 1).
func (l *Limiter) Allow(key string, now int64) bool {
	return l.AllowN(key, now, 1)
}

// AllowN consumes `n` tokens for `key` at tick `now` and reports whether the
// request is permitted. When fewer than `n` tokens are available it returns
// false and consumes nothing. A key is seen for the first time with a full
// bucket of `burst` tokens.
func (l *Limiter) AllowN(key string, now int64, n float64) bool {
	b := l.load(key, now)
	ok := b.tokens >= n
	if ok {
		b.tokens -= n
	}
	l.buckets.Set(key, b)
	return ok
}

// Tokens is a read-only view of how many whole tokens `key` has available at
// tick `now`, without mutating any state.
func (l *Limiter) Tokens(key string, now int64) int {
	if !l.buckets.Has(key) {
		return tokensToInt(l.burst)
	}
	b := l.buckets.Get(key).(*bucket)
	return tokensToInt(refill(b.tokens, b.last, now, l.rate, l.burst))
}

// Len returns the number of keys the limiter has seen.
func (l *Limiter) Len() int { return l.buckets.Size() }

// Iterate calls fn for every known key in ascending order, passing the whole
// tokens available at tick `now` and the last tick the key was observed.
// Returning true from fn stops the iteration early; Iterate reports whether it
// was stopped that way.
func (l *Limiter) Iterate(now int64, fn func(key string, tokens int, last int64) bool) bool {
	return l.buckets.Iterate("", "", func(key string, value any) bool {
		b := value.(*bucket)
		return fn(key, tokensToInt(refill(b.tokens, b.last, now, l.rate, l.burst)), b.last)
	})
}

// load returns the live bucket for key, refilled to `now`, creating a full
// bucket the first time a key is seen. The returned bucket is not yet stored;
// callers that mutate it must Set it back.
func (l *Limiter) load(key string, now int64) *bucket {
	if l.buckets.Has(key) {
		b := l.buckets.Get(key).(*bucket)
		b.tokens = refill(b.tokens, b.last, now, l.rate, l.burst)
		b.last = now
		return b
	}
	return &bucket{tokens: l.burst, last: now}
}

// --- pure helpers (unit-tested) -------------------------------------------

// fmin returns the smaller of two float64 values.
func fmin(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

// refill returns the token count at tick `now` given `tokens` observed at tick
// `last`, replenishing at `r` tokens/tick up to capacity `cap`. It never
// decreases below the stored value and never exceeds `cap`.
func refill(tokens float64, last, now int64, r, cap float64) float64 {
	if now <= last {
		return fmin(tokens, cap)
	}
	elapsed := float64(now - last)
	return fmin(cap, tokens+elapsed*r)
}

// tokensToInt floors a token count to a whole, non-negative token.
func tokensToInt(t float64) int {
	if t < 0 {
		return 0
	}
	return int(t)
}
