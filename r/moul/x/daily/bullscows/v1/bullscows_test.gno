package bullscows

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

func TestParseGuess(t *testing.T) {
	cases := []struct {
		in string
		ok bool
	}{
		{"1972", true},
		{"0123", true},
		{"11 2", false},
		{"123", false},
		{"12345", false},
		{"1123", false}, // repeated digit
		{"12a3", false},
	}
	for _, c := range cases {
		if _, ok := parseGuess(c.in); ok != c.ok {
			t.Fatalf("parseGuess(%q) ok = %v, want %v", c.in, ok, c.ok)
		}
	}
}

func TestScore(t *testing.T) {
	target := [4]int{1, 9, 7, 2}

	if b, c := score(target, [4]int{1, 9, 7, 2}); b != 4 || c != 0 {
		t.Fatalf("exact match: got bulls=%d cows=%d, want 4/0", b, c)
	}
	if b, c := score(target, [4]int{2, 7, 9, 1}); b != 0 || c != 4 {
		t.Fatalf("full rotation: got bulls=%d cows=%d, want 0/4", b, c)
	}
	if b, c := score(target, [4]int{1, 3, 4, 5}); b != 1 || c != 0 {
		t.Fatalf("one bull: got bulls=%d cows=%d, want 1/0", b, c)
	}
	if b, c := score(target, [4]int{5, 6, 7, 8}); b != 1 || c != 0 {
		t.Fatalf("no overlap but position 7: got bulls=%d cows=%d, want 1/0", b, c)
	}
}

func TestNewSecretDistinctDigits(t *testing.T) {
	for seed := int64(0); seed < 50; seed++ {
		d := newSecret(seed)
		var seen [10]bool
		for _, v := range d {
			if v < 0 || v > 9 {
				t.Fatalf("digit out of range: %d", v)
			}
			if seen[v] {
				t.Fatalf("newSecret(%d) = %v has repeated digit", seed, d)
			}
			seen[v] = true
		}
	}
}

func TestAddRecordKeepsFastestSorted(t *testing.T) {
	records = nil
	addRecord(record{player: "a", attempts: 10, round: 1})
	addRecord(record{player: "b", attempts: 3, round: 2})
	addRecord(record{player: "c", attempts: 7, round: 3})
	addRecord(record{player: "d", attempts: 1, round: 4})
	addRecord(record{player: "e", attempts: 9, round: 5})
	addRecord(record{player: "f", attempts: 2, round: 6}) // pushes out the worst

	if len(records) != maxRecords {
		t.Fatalf("len(records) = %d, want %d", len(records), maxRecords)
	}
	want := []int{1, 2, 3, 7, 9}
	for i, w := range want {
		if records[i].attempts != w {
			t.Fatalf("records[%d].attempts = %d, want %d", i, records[i].attempts, w)
		}
	}
}

func TestAddHistoryCaps(t *testing.T) {
	history = nil
	for i := 0; i < maxHistory+5; i++ {
		addHistory(guessLog{player: "p", guess: strconv.Itoa(i), bulls: 0, cows: 0})
	}
	if len(history) != maxHistory {
		t.Fatalf("len(history) = %d, want %d", len(history), maxHistory)
	}
	if history[len(history)-1].guess != strconv.Itoa(maxHistory+4) {
		t.Fatalf("history did not keep the most recent entries")
	}
}

// Crossing: Guess mutates realm state, needs cur realm + cross(cur).
func TestGuessRoundtrip(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	round = 1
	attempts = 0
	history = nil
	records = nil
	secret = [4]int{1, 9, 7, 2}

	out := Guess(cross(cur), "1234")
	if !strings.Contains(out, "bulls") {
		t.Fatalf("Guess() = %q, want bulls/cows feedback", out)
	}
	if attempts != 1 {
		t.Fatalf("attempts = %d, want 1", attempts)
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	out = Guess(cross(cur), "1972")
	if !strings.Contains(out, "SOLVED") {
		t.Fatalf("Guess() = %q, want a solved message", out)
	}
	if round != 2 {
		t.Fatalf("round = %d, want 2 (new round should start on solve)", round)
	}
	if len(records) != 1 || records[0].attempts != 2 {
		t.Fatalf("records = %v, want one entry with attempts=2", records)
	}
}

func TestGiveUpStartsNewRound(cur realm, t *testing.T) {
	round = 1
	attempts = 3
	secret = [4]int{4, 5, 6, 7}

	out := GiveUp(cross(cur))
	if !strings.Contains(out, "4567") {
		t.Fatalf("GiveUp() = %q, want it to reveal 4567", out)
	}
	if round != 2 || attempts != 0 {
		t.Fatalf("round=%d attempts=%d, want round=2 attempts=0", round, attempts)
	}
}
