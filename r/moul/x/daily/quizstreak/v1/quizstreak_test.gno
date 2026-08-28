package quizstreak

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

// resetGame re-initializes package globals so each test starts clean.
func resetGame() {
	players = avl.NewTree()
}

func TestStartIndexDeterministicAndInRange(t *testing.T) {
	n := len(questions)
	for _, tc := range []struct {
		addr   string
		height int64
	}{
		{"g1aaaa", 0},
		{"g1bbbb", 42},
		{"g1cccc", -7},
	} {
		idx := startIndex(tc.addr, tc.height)
		if idx < 0 || idx >= n {
			t.Errorf("startIndex(%q, %d) = %d, want in 0..%d", tc.addr, tc.height, idx, n-1)
		}
		if again := startIndex(tc.addr, tc.height); again != idx {
			t.Errorf("startIndex(%q, %d) non-deterministic: %d != %d", tc.addr, tc.height, again, idx)
		}
	}
}

func TestNextIndexWrapsAround(t *testing.T) {
	n := 5
	if got := nextIndex(4, 0, n); got != 0 {
		t.Errorf("nextIndex(4, 0, 5) = %d, want 0", got)
	}
	if got := nextIndex(2, 3, n); got != 1 {
		t.Errorf("nextIndex(2, 3, 5) = %d, want 1", got)
	}
}

// TestAnswerCorrectAndWrong exercises the crossing Answer function, so it
// takes cur realm and calls through cross(cur).
func TestAnswerCorrectAndWrong(cur realm, t *testing.T) {
	resetGame()

	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	addr := alice.String()
	p := getPlayer(addr)
	q := questions[p.qIdx]

	// wrong answer first: pick any index that isn't correct
	wrong := (q.correctIdx + 1) % len(q.choices)
	got := Answer(cross(cur), wrong)
	if !strings.HasPrefix(got, "Wrong") {
		t.Errorf("Answer(wrong) = %q, want it to start with Wrong", got)
	}
	if p.streak != 0 {
		t.Errorf("streak after wrong answer = %d, want 0", p.streak)
	}
	if p.qIdx != questionIndexOf(q) {
		t.Errorf("question changed after a wrong answer, want it to stay the same")
	}

	got = Answer(cross(cur), q.correctIdx)
	if !strings.HasPrefix(got, "Correct!") {
		t.Errorf("Answer(correct) = %q, want it to start with Correct!", got)
	}
	if p.streak != 1 {
		t.Errorf("streak after correct answer = %d, want 1", p.streak)
	}
	if p.best != 1 {
		t.Errorf("best after first correct answer = %d, want 1", p.best)
	}
	if p.correct != 1 || p.wrong != 1 {
		t.Errorf("correct/wrong = %d/%d, want 1/1", p.correct, p.wrong)
	}
	if len(leaderboard()) != 1 {
		t.Errorf("leaderboard len = %d, want 1", len(leaderboard()))
	}
}

// questionIndexOf is a small test helper to find a question's index.
func questionIndexOf(q question) int {
	for i, cand := range questions {
		if cand.text == q.text {
			return i
		}
	}
	return -1
}

func TestRenderShowsRulesAndLeaderboard(t *testing.T) {
	resetGame()
	out := Render("")
	for _, want := range []string{"Quiz Streak", "leaderboard", "How to play"} {
		if !strings.Contains(strings.ToLower(out), strings.ToLower(want)) {
			t.Errorf("Render(\"\") missing %q", want)
		}
	}
	if !strings.Contains(out, "No one has played yet") {
		t.Errorf("Render(\"\") should note an empty leaderboard")
	}
}

func TestRenderShowsPlayerDashboard(cur realm, t *testing.T) {
	resetGame()

	bob := testutils.TestAddress("bob")
	testing.SetRealm(testing.NewUserRealm(bob))
	addr := bob.String()

	p := getPlayer(addr)
	q := questions[p.qIdx]
	Answer(cross(cur), q.correctIdx)

	out := Render(addr)
	if !strings.Contains(out, "Your question") {
		t.Errorf("Render(addr) missing player dashboard section")
	}
	if !strings.Contains(out, "Current streak: 1") {
		t.Errorf("Render(addr) missing updated streak, got:\n%s", out)
	}
}
