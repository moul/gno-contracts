package ringlog

import (
	"strconv"
	"strings"
	"testing"
)

func resetState() {
	buf = [Cap]Entry{}
	head = 0
	count = 0
}

func TestPostAndRetrieve(t *testing.T) {
	resetState()

	Post("hello world")

	if count != 1 {
		t.Errorf("want count=1, got %d", count)
	}
	entries := Entries()
	if len(entries) != 1 {
		t.Fatalf("want 1 entry, got %d", len(entries))
	}
	if entries[0].Message != "hello world" {
		t.Errorf("want 'hello world', got %q", entries[0].Message)
	}
}

func TestLen(t *testing.T) {
	resetState()

	if Len() != 0 {
		t.Errorf("want Len()=0, got %d", Len())
	}
	Post("a")
	Post("b")
	Post("c")
	if Len() != 3 {
		t.Errorf("want Len()=3, got %d", Len())
	}
}

func TestRingWrap(t *testing.T) {
	resetState()

	// Write Cap+3 messages — the first 3 should be evicted.
	for i := 0; i < Cap+3; i++ {
		Post("msg" + strconv.Itoa(i))
	}

	if count != Cap {
		t.Errorf("want count=%d after overflow, got %d", Cap, count)
	}

	entries := Entries()
	if len(entries) != Cap {
		t.Fatalf("want %d entries, got %d", Cap, len(entries))
	}

	// Oldest surviving message should be msg3 (msg0..msg2 were overwritten).
	if entries[0].Message != "msg3" {
		t.Errorf("oldest entry should be 'msg3', got %q", entries[0].Message)
	}
	// Newest message should be msg(Cap+2).
	want := "msg" + strconv.Itoa(Cap+2)
	if entries[Cap-1].Message != want {
		t.Errorf("newest entry should be %q, got %q", want, entries[Cap-1].Message)
	}
}

func TestChronologicalOrder(t *testing.T) {
	resetState()

	msgs := []string{"first", "second", "third"}
	for _, m := range msgs {
		Post(m)
	}

	entries := Entries()
	for i, m := range msgs {
		if entries[i].Message != m {
			t.Errorf("entry[%d]: want %q, got %q", i, m, entries[i].Message)
		}
	}
}

func TestEmptyPanicsOnEmpty(t *testing.T) {
	resetState()
	defer func() {
		if r := recover(); r == nil {
			t.Error("expected panic on empty message, got none")
		}
	}()
	Post("   ")
}

func TestTooLongPanics(t *testing.T) {
	resetState()
	defer func() {
		if r := recover(); r == nil {
			t.Error("expected panic on too-long message, got none")
		}
	}()
	Post(strings.Repeat("x", 281))
}

func TestRender(t *testing.T) {
	resetState()

	r := Render("")
	if !strings.Contains(r, "No messages yet") {
		t.Error("empty ring should show 'No messages yet'")
	}

	Post("first message")
	r = Render("")
	if !strings.Contains(r, "first message") {
		t.Error("render should include 'first message'")
	}
	if !strings.Contains(r, "RingLog") {
		t.Error("render should include title 'RingLog'")
	}
}
