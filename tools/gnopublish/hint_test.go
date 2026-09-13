package main

import (
	"errors"
	"strings"
	"testing"
)

// TestStaleClientHint: the amino decode failure that a stale binary produces
// must carry the actual cause, not just the raw message.
func TestStaleClientHintAnnotates(t *testing.T) {
	raw := errors.New(`unknown JSON field "vesting" for type std.BaseAccount`)
	got := staleClientHint(raw)

	if !errors.Is(got, raw) {
		t.Error("the original error must stay unwrappable")
	}
	for _, want := range []string{"OLDER than the chain", "replace", "chain/mainnet"} {
		if !strings.Contains(got.Error(), want) {
			t.Errorf("hint should mention %q, got:\n%s", want, got)
		}
	}
}

// TestStaleClientHintPassesThrough: unrelated errors must not be dressed up
// with a misleading diagnosis.
func TestStaleClientHintPassesThrough(t *testing.T) {
	for _, e := range []error{
		nil,
		errors.New("connection refused"),
		errors.New("account does not exist"),
	} {
		if got := staleClientHint(e); got != e {
			t.Errorf("staleClientHint(%v) should pass through unchanged, got %v", e, got)
		}
	}
}
