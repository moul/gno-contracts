package ratelimit

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRefill(t *testing.T) {
	// Start with 1 token, 4 ticks elapse at 0.5 tokens/tick, cap 5.
	// 1 + 4*0.5 = 3.
	got := refill(1.0, 10, 14, 0.5, 5.0)
	uassert.True(t, got == 3.0, "expected 3 tokens after refill")

	// No time elapsed -> unchanged (but clamped to cap).
	got = refill(2.0, 10, 10, 0.5, 5.0)
	uassert.True(t, got == 2.0, "no elapsed ticks should not add tokens")

	// Going backwards (now < last) never adds tokens.
	got = refill(2.0, 10, 5, 0.5, 5.0)
	uassert.True(t, got == 2.0, "negative elapsed should not add tokens")
}

func TestRefillCap(t *testing.T) {
	// Long idle period must saturate at burst capacity.
	got := refill(0.0, 0, 1000, 0.5, 5.0)
	uassert.True(t, got == 5.0, "refill must cap at burst")

	// Already-full bucket stays full.
	got = refill(5.0, 0, 100, 0.5, 5.0)
	uassert.True(t, got == 5.0, "full bucket stays capped")
}

func TestTokensToInt(t *testing.T) {
	uassert.Equal(t, 3, tokensToInt(3.9))
	uassert.Equal(t, 0, tokensToInt(0.4))
	uassert.Equal(t, 0, tokensToInt(-2.0))
	uassert.Equal(t, 5, tokensToInt(5.0))
}

func TestFmin(t *testing.T) {
	uassert.True(t, fmin(1.0, 2.0) == 1.0, "fmin picks smaller")
	uassert.True(t, fmin(4.0, 2.5) == 2.5, "fmin picks smaller")
	uassert.True(t, fmin(3.0, 3.0) == 3.0, "fmin on equals")
}

func TestNewClampsConfig(t *testing.T) {
	l := New(-1, 0) // rate < 0 -> 0, burst < 1 -> 1
	r, b := l.Config()
	uassert.True(t, r == 0.0, "rate clamped to 0")
	uassert.True(t, b == 1.0, "burst clamped to 1")
}

func TestAllowConsumesAndDenies(t *testing.T) {
	l := New(0.5, 5.0)
	const k = "g1caller"
	// A fresh key starts full (burst=5): first 5 Allow succeed, 6th fails.
	for i := 0; i < 5; i++ {
		uassert.True(t, l.Allow(k, 0), "burst token should be granted")
	}
	uassert.False(t, l.Allow(k, 0), "6th call at same tick must be denied")

	// After 4 ticks at 0.5/tick, 2 whole tokens refilled -> 2 more allowed.
	uassert.True(t, l.Allow(k, 4), "refilled token granted")
	uassert.True(t, l.Allow(k, 4), "refilled token granted")
	uassert.False(t, l.Allow(k, 4), "empty again")
}

func TestAllowNAtomic(t *testing.T) {
	l := New(1, 5.0)
	const k = "g1caller"
	uassert.False(t, l.AllowN(k, 0, 6), "cannot take more than burst")
	uassert.Equal(t, 5, l.Tokens(k, 0), "denied AllowN consumes nothing")
	uassert.True(t, l.AllowN(k, 0, 3), "3 of 5 taken")
	uassert.Equal(t, 2, l.Tokens(k, 0), "2 remain")
}

func TestTokensReadOnly(t *testing.T) {
	l := New(0.5, 5.0)
	const k = "g1caller"
	// Unseen key reports a full bucket without creating it.
	uassert.Equal(t, 5, l.Tokens(k, 100), "unseen key is full")
	uassert.Equal(t, 0, l.Len(), "Tokens must not create a bucket")
	// Reading does not consume.
	uassert.Equal(t, 5, l.Tokens(k, 200), "still full on second read")
}

func TestPerKeyIsolation(t *testing.T) {
	l := New(0.5, 5.0)
	l.Allow("g1a", 0)
	uassert.Equal(t, 4, l.Tokens("g1a", 0), "a spent one")
	uassert.Equal(t, 5, l.Tokens("g1b", 0), "b untouched")
	uassert.Equal(t, 1, l.Len(), "only a exists")
}

func TestIterate(t *testing.T) {
	l := New(0.5, 5.0)
	l.Allow("g1a", 0)
	l.Allow("g1b", 0)
	seen := 0
	stopped := l.Iterate(0, func(key string, tokens int, last int64) bool {
		seen++
		return false
	})
	uassert.Equal(t, 2, seen, "iterate visits every key")
	uassert.False(t, stopped, "not stopped early")

	// Early stop.
	count := 0
	stopped = l.Iterate(0, func(key string, tokens int, last int64) bool {
		count++
		return true
	})
	uassert.Equal(t, 1, count, "stops after first")
	uassert.True(t, stopped, "reported as stopped")
}
