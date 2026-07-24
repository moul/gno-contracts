package moodstone

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

func TestLogMoodBasic(t *testing.T) {
	entries = nil
	testing.SetOriginCaller(alice)

	LogMood(cross, "happy", "great day!")
	LogMood(cross, "calm", "")

	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if entries[0].Mood != "happy" {
		t.Errorf("expected happy, got %s", entries[0].Mood)
	}
	if entries[0].Note != "great day!" {
		t.Errorf("expected 'great day!', got %s", entries[0].Note)
	}
	if entries[1].Mood != "calm" {
		t.Errorf("expected calm, got %s", entries[1].Mood)
	}
}

func TestLogMoodCaseInsensitive(t *testing.T) {
	entries = nil
	testing.SetOriginCaller(alice)

	LogMood(cross, "HAPPY", "uppercase input")
	if entries[0].Mood != "happy" {
		t.Errorf("expected normalized to happy, got %s", entries[0].Mood)
	}
}

func TestIsValid(t *testing.T) {
	for _, m := range validMoods {
		if !isValid(m) {
			t.Errorf("%s should be valid", m)
		}
	}
	if isValid("euphoric") {
		t.Error("euphoric should not be valid")
	}
	if isValid("") {
		t.Error("empty string should not be valid")
	}
}

func TestMoodCount(t *testing.T) {
	entries = nil
	testing.SetOriginCaller(alice)

	LogMood(cross, "happy", "")
	LogMood(cross, "happy", "")
	LogMood(cross, "sad", "")

	if MoodCount("happy") != 2 {
		t.Errorf("expected 2 happy, got %d", MoodCount("happy"))
	}
	if MoodCount("sad") != 1 {
		t.Errorf("expected 1 sad, got %d", MoodCount("sad"))
	}
	if MoodCount("angry") != 0 {
		t.Errorf("expected 0 angry, got %d", MoodCount("angry"))
	}
}

func TestTotalEntries(t *testing.T) {
	entries = nil

	if TotalEntries() != 0 {
		t.Errorf("expected 0, got %d", TotalEntries())
	}
	testing.SetOriginCaller(alice)
	LogMood(cross, "excited", "testing!")
	if TotalEntries() != 1 {
		t.Errorf("expected 1, got %d", TotalEntries())
	}
}

func TestDominantMood(t *testing.T) {
	entries = nil

	if DominantMood() != "none" {
		t.Errorf("expected none on empty, got %s", DominantMood())
	}

	testing.SetOriginCaller(alice)
	LogMood(cross, "happy", "")
	LogMood(cross, "happy", "")

	testing.SetOriginCaller(bob)
	LogMood(cross, "sad", "")

	if DominantMood() != "happy" {
		t.Errorf("expected happy to dominate, got %s", DominantMood())
	}
}

func TestRender(t *testing.T) {
	entries = nil

	out := Render("")
	if len(out) == 0 {
		t.Error("Render returned empty string")
	}

	testing.SetOriginCaller(alice)
	LogMood(cross, "neutral", "just checking the render")

	out = Render("")
	if len(out) == 0 {
		t.Error("Render returned empty string after entries")
	}
}
