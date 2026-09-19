package guestbook

import (
	"strings"
	"testing"

	"gno.land/p/moul/kit/store/v0"
)

// resetState clears package globals between tests (globals persist across
// test functions in the same package binary).
func resetState() {
	entries = store.Named("guestbook: entry")
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

	addEntry("g1alice", "AAA oldest", 1)
	addEntry("g1alice", "BBB newest", 2)

	out := Render("")
	iNew := strings.Index(out, "BBB newest")
	iOld := strings.Index(out, "AAA oldest")
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

// A message must not be able to break out of its table cell. The escaping now
// lives in ui.Cell, so this asserts the realm's rendered output rather than a
// local helper.
func TestRenderEscapesMessage(t *testing.T) {
	resetState()
	defer resetState()
	addEntry("g1manfred47kzduec920z88wfr64ylksmdcedlf5", "a|b", 1)
	out := Render("")
	if strings.Contains(out, "| a|b |") {
		t.Errorf("an unescaped pipe would open a column:\n%s", out)
	}
	if !strings.Contains(out, `a\|b`) {
		t.Errorf("message should appear escaped:\n%s", out)
	}
}

// v1 asserted that its own seqKey() ordered numerically. That held only below
// its width of 16: seqKey(10^16) is 17 characters and sorts before
// seqKey(10^16-1). The store key is 8 bytes for every id, so there is no
// ceiling to reach.
func TestSeqKeyOrders(t *testing.T) {
	if a, b := store.ID(2).Key(), store.ID(10).Key(); !(a < b) {
		t.Error("id 2 should sort before id 10")
	}
	if a, b := store.ID(9999999999999999).Key(), store.ID(10000000000000000).Key(); !(a < b) {
		t.Error("ordering should survive one past v1's width-16 ceiling")
	}
}
