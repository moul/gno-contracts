package gns

import (
	"testing"
)

// Local assertion helpers.
//
// We deliberately avoid gno.land/p/nt/uassert here: when this realm is compiled
// as an EXTERNAL package (outside the gno examples module) the working-tree copy
// of uassert/v0 fails to preprocess with the pinned gno binary. These helpers
// depend only on the standard testing package.
//
// GNS mutations PANIC with stable error values (see the error_* set) to revert
// state, per gno semantics. A recover() inside this same realm package cannot
// catch a crossing-boundary abort (only a pure p/ package frame can). Rejection
// invariants are therefore unit-tested against the internal, non-crossing
// helpers that produce the errors (authorize, priceFor, available, ...), and a
// few end-to-end abort behaviours are covered by filetests.

func eqStr(t *testing.T, want, got, ctx string) {
	t.Helper()
	if want != got {
		t.Errorf("%s: want %q, got %q", ctx, want, got)
	}
}

func eqInt(t *testing.T, want, got int64, ctx string) {
	t.Helper()
	if want != got {
		t.Errorf("%s: want %d, got %d", ctx, want, got)
	}
}

func isTrue(t *testing.T, v bool, ctx string) {
	t.Helper()
	if !v {
		t.Errorf("%s: want true", ctx)
	}
}

func isFalse(t *testing.T, v bool, ctx string) {
	t.Helper()
	if v {
		t.Errorf("%s: want false", ctx)
	}
}

func noErr(t *testing.T, err error, ctx string) {
	t.Helper()
	if err != nil {
		t.Errorf("%s: unexpected error %v", ctx, err)
	}
}

func isErr(t *testing.T, err error, ctx string) {
	t.Helper()
	if err == nil {
		t.Errorf("%s: expected error, got nil", ctx)
	}
}

// errIs asserts err matches want by stable code (Error() string).
func errIs(t *testing.T, err, want error, ctx string) {
	t.Helper()
	if err == nil {
		t.Errorf("%s: expected error %v, got nil", ctx, want)
		return
	}
	if err.Error() != want.Error() {
		t.Errorf("%s: expected %q, got %q", ctx, want.Error(), err.Error())
	}
}
