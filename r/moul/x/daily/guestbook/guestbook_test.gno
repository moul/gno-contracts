package guestbook

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
)

// resetState clears package globals between tests (globals persist across
// test functions in the same package binary).
func resetState() {
	entries = avl.NewTree()
	count = 0
}

func TestAddEntryAppendsAndCounts(t *testing.T) {
	resetState()

	addEntry("g1alice", "hello world", 100)
	addEntry("g1bob", "second entry", 101)

	if got := Count(); got != 2 {
		t.Fatalf("Count() = %d, want 2", got)
	}

	out := Render("")
	if !strings.Contains(out, "**Total signatures:** 2") {
		t.Errorf("Render missing total; got:\n%s", out)
	}
	if !strings.Contains(out, "hello world") {
		t.Errorf("Render missing first message; got:\n%s", out)
	}
	if !strings.Contains(out, "second entry") {
		t.Errorf("Render missing second message; got:\n%s", out)
	}
	if !strings.Contains(out, "100") || !strings.Contains(out, "101") {
		t.Errorf("Render missing heights; got:\n%s", out)
	}
}

func TestRenderNewestFirst(t *testing.T) {
	resetState()

	addEntry("g1alice", "AAA-oldest", 1)
	addEntry("g1alice", "BBB-newest", 2)

	out := Render("")
	iNew := strings.Index(out, "BBB-newest")
	iOld := strings.Index(out, "AAA-oldest")
	if iNew < 0 || iOld < 0 {
		t.Fatalf("both messages must appear; got:\n%s", out)
	}
	if iNew > iOld {
		t.Errorf("newest entry should render before oldest; got:\n%s", out)
	}
}

func TestRenderEmpty(t *testing.T) {
	resetState()

	out := Render("")
	if !strings.Contains(out, "No one has signed yet") {
		t.Errorf("empty render should invite signing; got:\n%s", out)
	}
}

func TestEmptyMessagePanics(t *testing.T) {
	resetState()

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("signing an empty message should panic")
		}
	}()
	addEntry("g1alice", "   ", 1)
}

func TestEscapeCell(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"plain", "plain"},
		{"a|b", "a\\|b"},
		{"line1\nline2", "line1 line2"},
	}
	for _, tc := range cases {
		if got := escapeCell(tc.in); got != tc.want {
			t.Errorf("escapeCell(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestSeqKeyOrders(t *testing.T) {
	if a, b := seqKey(2), seqKey(10); !(a < b) {
		t.Errorf("seqKey(2)=%q should sort before seqKey(10)=%q", a, b)
	}
}
