package timelock

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestStateOf(t *testing.T) {
	base := &Operation{ID: 1, Action: "upgrade", ReadyHeight: 100}

	// Before ready height -> Pending.
	uassert.Equal(t, StatePending, StateOf(base, 50))
	// At/after ready height -> Ready.
	uassert.Equal(t, StateReady, StateOf(base, 100))
	uassert.Equal(t, StateReady, StateOf(base, 150))

	// Executed and cancelled are terminal regardless of height.
	done := &Operation{ID: 2, ReadyHeight: 10, Done: true}
	uassert.Equal(t, StateExecuted, StateOf(done, 5))
	uassert.Equal(t, StateExecuted, StateOf(done, 999))

	cancelled := &Operation{ID: 3, ReadyHeight: 10, Cancelled: true}
	uassert.Equal(t, StateCancelled, StateOf(cancelled, 5))
	uassert.Equal(t, StateCancelled, StateOf(cancelled, 999))
}

func TestBlocksRemaining(t *testing.T) {
	op := &Operation{ID: 1, ReadyHeight: 100}

	uassert.Equal(t, int64(100), BlocksRemaining(op, 0))
	uassert.Equal(t, int64(40), BlocksRemaining(op, 60))
	// At ready height and beyond -> 0.
	uassert.Equal(t, int64(0), BlocksRemaining(op, 100))
	uassert.Equal(t, int64(0), BlocksRemaining(op, 250))
}

func TestPaddedKeyOrdering(t *testing.T) {
	// Keys must be fixed-width so lexical order matches numeric id order.
	uassert.True(t, paddedKey(2) < paddedKey(10))
	uassert.True(t, paddedKey(9) < paddedKey(100))
	uassert.Equal(t, len(paddedKey(1)), len(paddedKey(123456)))
}
