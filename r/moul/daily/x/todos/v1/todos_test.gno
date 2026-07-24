package todos

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils"
)

// reset clears package globals between tests (t.Run/subtests do not reset them).
func reset() {
	items = avl.Tree{}
	nextID = 0
}

// TestAddToggleRemove exercises the full lifecycle through the crossing API.
// Crossing test: takes `cur realm` and calls via cross(cur).
func TestAddToggleRemove(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	id1 := Add(cross(cur), "buy milk")
	if id1 != 1 {
		t.Fatalf("Add first id = %d, want 1", id1)
	}
	id2 := Add(cross(cur), "walk dog")
	if id2 != 2 {
		t.Fatalf("Add second id = %d, want 2", id2)
	}

	open, done := counts()
	if open != 2 || done != 0 {
		t.Fatalf("after adds: open=%d done=%d, want 2/0", open, done)
	}

	// Toggle #1 done.
	Toggle(cross(cur), 1)
	open, done = counts()
	if open != 1 || done != 1 {
		t.Fatalf("after toggle: open=%d done=%d, want 1/1", open, done)
	}

	// Toggle #1 back to open.
	Toggle(cross(cur), 1)
	open, done = counts()
	if open != 2 || done != 0 {
		t.Fatalf("after re-toggle: open=%d done=%d, want 2/0", open, done)
	}

	// Remove #1.
	Remove(cross(cur), 1)
	open, done = counts()
	if open != 1 || done != 0 {
		t.Fatalf("after remove: open=%d done=%d, want 1/0", open, done)
	}
	if _, ok := items.Get(idKey(1)); ok {
		t.Fatalf("item #1 still present after Remove")
	}
}

// TestRender checks the Markdown output shape and counts. Render is not a
// crossing function, so this is a plain test — but the Add calls that seed
// state still need a realm, so it also takes `cur realm`.
func TestRender(cur realm, t *testing.T) {
	reset()

	// Empty board.
	empty := Render("")
	if !strings.Contains(empty, "0 open · 0 done · 0 total") {
		t.Fatalf("empty render missing zero counts:\n%s", empty)
	}
	if !strings.Contains(empty, "No items yet") {
		t.Fatalf("empty render missing placeholder:\n%s", empty)
	}

	bob := testutils.TestAddress("bob")
	testing.SetRealm(testing.NewUserRealm(bob))

	Add(cross(cur), "first")
	Add(cross(cur), "second")
	Add(cross(cur), "third")
	Toggle(cross(cur), 2) // mark #2 done

	out := Render("")

	// Counts line: 2 open, 1 done, 3 total.
	if !strings.Contains(out, "2 open · 1 done · 3 total") {
		t.Fatalf("render counts wrong:\n%s", out)
	}
	// Done checkbox for #2.
	if !strings.Contains(out, "- [x] #2 second") {
		t.Fatalf("render missing done item #2:\n%s", out)
	}
	// Open checkbox for #1.
	if !strings.Contains(out, "- [ ] #1 first") {
		t.Fatalf("render missing open item #1:\n%s", out)
	}
	// Newest first: #3 must appear before #1.
	if strings.Index(out, "#3 third") > strings.Index(out, "#1 first") {
		t.Fatalf("render not newest-first:\n%s", out)
	}
	// Author short form present.
	if !strings.Contains(out, "(g1") {
		t.Fatalf("render missing author short address:\n%s", out)
	}
}

// TestIDKeyOrdering verifies idKey produces lexicographically-ordered keys so
// avl iteration matches numeric id order. Non-crossing: plain signature.
func TestIDKeyOrdering(t *testing.T) {
	if idKey(2) >= idKey(10) {
		t.Fatalf("idKey(2)=%q should sort before idKey(10)=%q", idKey(2), idKey(10))
	}
	if idKey(9) >= idKey(100) {
		t.Fatalf("idKey(9)=%q should sort before idKey(100)=%q", idKey(9), idKey(100))
	}
	if len(idKey(1)) != 12 {
		t.Fatalf("idKey width = %d, want 12", len(idKey(1)))
	}
}
