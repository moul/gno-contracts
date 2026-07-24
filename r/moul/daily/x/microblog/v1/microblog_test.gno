package microblog

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

// resetWall clears package state between tests (globals persist in-process,
// and subtests do not reset them — do it explicitly).
func resetWall() { posts = nil }

// asUser must be inlined into each test: SetRealm affects the calling frame
// only. We therefore call it directly in the test bodies below.

func TestPostAndCount(cur realm, t *testing.T) {
	resetWall()

	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "hello wall")

	if got := Count(); got != 1 {
		t.Fatalf("Count() = %d, want 1", got)
	}
	if posts[0].Msg != "hello wall" {
		t.Errorf("Msg = %q, want %q", posts[0].Msg, "hello wall")
	}
	if posts[0].Author != alice.String() {
		t.Errorf("Author = %q, want %q", posts[0].Author, alice.String())
	}
}

func TestPostTooLongPanics(cur realm, t *testing.T) {
	resetWall()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("bob")))

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for over-long message, got none")
		}
	}()
	Post(cross(cur), strings.Repeat("x", maxMsgLen+1))
}

func TestPostEmptyPanics(cur realm, t *testing.T) {
	resetWall()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("bob")))

	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for empty message, got none")
		}
	}()
	Post(cross(cur), "")
}

func TestPostMaxLenOK(cur realm, t *testing.T) {
	resetWall()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("carol")))

	// Exactly maxMsgLen bytes must be accepted.
	Post(cross(cur), strings.Repeat("y", maxMsgLen))
	if got := Count(); got != 1 {
		t.Fatalf("Count() = %d, want 1 for exactly-max message", got)
	}
}

func TestRenderEmpty(t *testing.T) {
	resetWall()
	out := Render("")
	if !strings.Contains(out, "No posts yet") {
		t.Errorf("empty Render should mention no posts, got:\n%s", out)
	}
}

func TestRenderNewestFirstAndPagination(cur realm, t *testing.T) {
	resetWall()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("dave")))

	// 25 posts -> 2 pages (20 + 5).
	for i := 0; i < 25; i++ {
		Post(cross(cur), "msg"+itoa(i))
	}

	if got := Count(); got != 25 {
		t.Fatalf("Count() = %d, want 25", got)
	}

	page1 := Render("")
	// Newest (msg24) must appear before older (msg5) on page 1.
	i24 := strings.Index(page1, "msg24")
	i5 := strings.Index(page1, "msg5")
	if i24 < 0 || i5 < 0 {
		t.Fatalf("page 1 missing expected posts: msg24=%d msg5=%d", i24, i5)
	}
	if i24 > i5 {
		t.Errorf("page 1 not newest-first: msg24 at %d should precede msg5 at %d", i24, i5)
	}
	if !strings.Contains(page1, "page 1 of 2") {
		t.Errorf("page 1 header wrong, got:\n%s", page1)
	}

	// Page 2 via query form must contain the oldest post.
	page2 := Render("?page=2")
	if !strings.Contains(page2, "msg0") {
		t.Errorf("page 2 should contain oldest msg0, got:\n%s", page2)
	}
	if !strings.Contains(page2, "page 2 of 2") {
		t.Errorf("page 2 header wrong, got:\n%s", page2)
	}

	// Path form "/2" should equal query form "?page=2".
	if Render("/2") != page2 {
		t.Errorf("path form /2 differs from query form ?page=2")
	}
}

func TestParsePage(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"", 1},
		{"?page=3", 3},
		{"?p=4", 4},
		{"/2", 2},
		{"5", 5},
		{"?page=abc", 1},
		{"garbage", 1},
	}
	for _, c := range cases {
		if got := parsePage(c.in); got != c.want {
			t.Errorf("parsePage(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

// itoa is a tiny local int->string helper for building test messages.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
