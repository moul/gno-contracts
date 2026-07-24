package hangman

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

// TestPureHelpers checks the deterministic, non-crossing logic.
func TestPureHelpers(t *testing.T) {
	// normalizeLetter
	if c, ok := normalizeLetter("A"); !ok || c != "a" {
		t.Fatalf("normalizeLetter(A) = %q,%v; want a,true", c, ok)
	}
	if _, ok := normalizeLetter("ab"); ok {
		t.Fatalf("normalizeLetter(ab) should fail")
	}
	if _, ok := normalizeLetter("3"); ok {
		t.Fatalf("normalizeLetter(3) should fail")
	}

	// wordForDay is deterministic and cycles the list.
	w0 := wordForDay(0)
	if w0 != words[0] {
		t.Fatalf("wordForDay(0) = %q; want %q", w0, words[0])
	}
	if wordForDay(int64(len(words))) != words[0] {
		t.Fatalf("wordForDay should wrap around the list length")
	}

	// dayKey formatting.
	if got := dayKey(0); got != "0" {
		t.Fatalf("dayKey(0) = %q; want 0", got)
	}
	if got := dayKey(123); got != "123" {
		t.Fatalf("dayKey(123) = %q; want 123", got)
	}

	// gallows clamps and grows.
	if gallows(0) == gallows(6) {
		t.Fatalf("gallows should differ between 0 and 6 wrong")
	}
	if gallows(99) != gallows(6) {
		t.Fatalf("gallows should clamp out-of-range to max stage")
	}
}

// TestRoundMasking checks masked/win/lose logic directly on a round.
func TestRoundMasking(t *testing.T) {
	r := &round{word: "gno", guessed: avl.NewTree(), wrong: 0}

	if got := r.masked(); got != "_ _ _" {
		t.Fatalf("initial masked = %q; want _ _ _", got)
	}
	if r.isWon() {
		t.Fatalf("fresh round should not be won")
	}

	r.guessed.Set("g", struct{}{})
	if got := r.masked(); got != "g _ _" {
		t.Fatalf("masked after g = %q; want g _ _", got)
	}

	r.guessed.Set("n", struct{}{})
	r.guessed.Set("o", struct{}{})
	if !r.isWon() {
		t.Fatalf("round should be won after guessing all letters")
	}

	// Lose path.
	r2 := &round{word: "gno", guessed: avl.NewTree(), wrong: maxWrong}
	if !r2.isLost() {
		t.Fatalf("round with %d wrong should be lost", maxWrong)
	}
	if !r2.over() {
		t.Fatalf("lost round should be over")
	}
}

// TestGuessCrossing exercises the crossing entrypoint end to end.
func TestGuessCrossing(cur realm, t *testing.T) {
	user := testutils.TestAddress("player")
	testing.SetRealm(testing.NewUserRealm(user))

	r := current()
	word := r.word

	// A correct guess: pick the first letter of today's word.
	first := string(word[0])
	Guess(cross(cur), first)
	if !r.guessed.Has(first) {
		t.Fatalf("guessed set should contain %q after Guess", first)
	}
	if r.wrong != 0 {
		t.Fatalf("correct guess should not increase wrong count, got %d", r.wrong)
	}

	// Re-guessing the same letter aborts.
	uassert.AbortsWithMessage(t, "letter already guessed: "+first, func() {
		Guess(cross(cur), first)
	})

	// Invalid input aborts.
	uassert.AbortsWithMessage(t, "guess must be a single letter a-z", func() {
		Guess(cross(cur), "42")
	})

	// A wrong guess: find a letter not in the word.
	miss := firstMissing(word)
	if miss != "" {
		before := r.wrong
		Guess(cross(cur), miss)
		if r.wrong != before+1 {
			t.Fatalf("wrong guess should increment wrong count: got %d want %d", r.wrong, before+1)
		}
	}

	// Render always returns non-empty markdown.
	out := Render("")
	if !strings.Contains(out, "Hangman") {
		t.Fatalf("Render output missing title")
	}
}

// firstMissing returns a lowercase letter a-z not present in word, or "".
func firstMissing(word string) string {
	for c := byte('a'); c <= 'z'; c++ {
		if !strings.Contains(word, string(c)) {
			return string(c)
		}
	}
	return ""
}
