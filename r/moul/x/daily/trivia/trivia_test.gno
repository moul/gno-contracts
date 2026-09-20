package trivia

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
)

// resetQuiz re-initializes package globals so each test starts clean; init()
// only runs once for the whole test binary.
func resetQuiz(height int64) {
	current = newRound(1, height)
	scores = avl.NewTree()
	totalCorrect = 0
}

func TestQuestionIndexDeterministic(t *testing.T) {
	n := len(questions)
	for _, h := range []int64{0, 1, 42, 12345, -7} {
		idx := questionIndex(1, h)
		if idx < 0 || idx >= n {
			t.Errorf("questionIndex(1, %d) = %d, want in 0..%d", h, idx, n-1)
		}
		if again := questionIndex(1, h); again != idx {
			t.Errorf("questionIndex(1, %d) non-deterministic: %d != %d", h, again, idx)
		}
	}
	// consecutive rounds should walk sequentially through the list
	first := questionIndex(1, 0)
	second := questionIndex(2, 0)
	if second != (first+1)%n {
		t.Errorf("round 2 index = %d, want %d", second, (first+1)%n)
	}
}

// TestAnswerCorrectAdvances exercises the crossing Answer function, so it
// takes cur realm and calls through cross(cur).
func TestAnswerCorrectAdvances(cur realm, t *testing.T) {
	resetQuiz(10)
	q := questions[current.qIdx]
	prevRound := current.number

	// wrong answer first: pick any index that isn't correct
	wrong := (q.correctIdx + 1) % len(q.choices)
	got := Answer(cross(cur), wrong)
	if got != "Wrong — try again." {
		t.Errorf("Answer(wrong) = %q, want wrong message", got)
	}
	if current.solved {
		t.Error("round should not be solved after a wrong answer")
	}

	got = Answer(cross(cur), q.correctIdx)
	if !strings.HasPrefix(got, "Correct!") {
		t.Errorf("Answer(correct) = %q, want it to start with Correct!", got)
	}
	if current.number != prevRound+1 {
		t.Errorf("round number = %d, want %d", current.number, prevRound+1)
	}
	if totalCorrect != 1 {
		t.Errorf("totalCorrect = %d, want 1", totalCorrect)
	}
	if len(leaderboard()) != 1 {
		t.Errorf("leaderboard len = %d, want 1", len(leaderboard()))
	}
}

// TestRenderContainsState is a plain read — no cur.
func TestRenderContainsState(t *testing.T) {
	resetQuiz(5)
	out := Render("")
	for _, want := range []string{"Trivia Quiz", "Round", "Leaderboard"} {
		if !strings.Contains(out, want) {
			t.Errorf("Render() missing %q", want)
		}
	}
}
