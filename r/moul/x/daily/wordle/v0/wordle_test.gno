package wordle

import (
	"strings"
	"testing"
)

func TestScore(t *testing.T) {
	tests := []struct {
		name   string
		guess  string
		secret string
		want   string
	}{
		// all letters correct, correct spots.
		{"all correct", "crane", "crane", "🟩🟩🟩🟩🟩"},
		// s⬜ l🟨 a🟨 t🟨 e🟩  (secret t,a,b,l,e vs guess s,l,a,t,e)
		{"present wrong spot", "slate", "table", "⬜🟨🟨🟨🟩"},
		// no shared letters at all.
		{"all absent", "vivid", "champ", "⬜⬜⬜⬜⬜"},
	}
	for _, tt := range tests {
		got := score(tt.guess, tt.secret)
		if n := len([]rune(got)); n != wordLen {
			t.Errorf("%s: score(%q,%q) produced %d tiles, want %d", tt.name, tt.guess, tt.secret, n, wordLen)
		}
		if got != tt.want {
			t.Errorf("%s: score(%q,%q) = %q, want %q", tt.name, tt.guess, tt.secret, got, tt.want)
		}
	}
}

func TestScoreDuplicateLetters(t *testing.T) {
	// guess "eerie" vs secret "there": guess e,e,r,i,e ; secret t,h,e,r,e
	// greens: pos? e-t no, e-h no, r-e no, i-r no, e-e yes(pos4) 🟩
	// secret remaining after greens: t,h,e,r (one e consumed at pos4)
	// pos0 e: e available -> 🟨, consume e (none left)
	// pos1 e: no e left -> ⬜
	// pos2 r: r available -> 🟨
	// pos3 i: not present -> ⬜
	got := score("eerie", "there")
	want := "🟨⬜🟨⬜🟩"
	if got != want {
		t.Errorf("eerie/there: got %q want %q", got, want)
	}
}

func TestIsFiveLetters(t *testing.T) {
	tests := []struct {
		in   string
		want bool
	}{
		{"crane", true},
		{"CRANE", false}, // uppercase rejected (caller lowercases first)
		{"cran", false},  // too short
		{"cranes", false},// too long
		{"cr4ne", false}, // digit
		{"cr ne", false}, // space
		{"", false},
	}
	for _, tt := range tests {
		if got := isFiveLetters(tt.in); got != tt.want {
			t.Errorf("isFiveLetters(%q) = %v, want %v", tt.in, got, tt.want)
		}
	}
}

func TestDayAndWordDeterminism(t *testing.T) {
	// Same day index must yield the same word; word must be a dictionary entry.
	d := dayIndex(blocksPerDay * 3)
	if d != 3 {
		t.Errorf("dayIndex: got %d want 3", d)
	}
	w1 := wordForDay(d)
	w2 := wordForDay(d)
	if w1 != w2 {
		t.Errorf("wordForDay not deterministic: %q vs %q", w1, w2)
	}
	found := false
	for _, w := range words {
		if w == w1 {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("wordForDay returned %q which is not in the dictionary", w1)
	}
	if !isFiveLetters(w1) {
		t.Errorf("dictionary word %q is not 5 lowercase letters", w1)
	}
}

func TestAllDictionaryWordsValid(t *testing.T) {
	for _, w := range words {
		if !isFiveLetters(w) {
			t.Errorf("dictionary word %q is not exactly 5 lowercase letters", w)
		}
	}
}

func TestRenderContainsRules(t *testing.T) {
	out := Render("")
	if !strings.Contains(out, "Daily Word Puzzle") {
		t.Errorf("Render missing title; got:\n%s", out)
	}
	if !strings.Contains(out, "Rules") {
		t.Errorf("Render missing rules section; got:\n%s", out)
	}
}
