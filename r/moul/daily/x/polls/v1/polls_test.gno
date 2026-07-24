package polls

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

// resetState clears package-level state between tests so cases are independent.
func resetState() {
	polls = nil
	nextID = 0
}

func TestParseOptions(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  []string
	}{
		{"simple", "a,b,c", []string{"a", "b", "c"}},
		{"trims spaces", " yes , no ", []string{"yes", "no"}},
		{"drops empties", "a,,b, ,c", []string{"a", "b", "c"}},
		{"single", "only", []string{"only"}},
		{"all blank", " , ,", nil},
	}
	for _, tt := range tests {
		got := parseOptions(tt.input)
		if len(got) != len(tt.want) {
			t.Errorf("%s: len = %d, want %d (%v)", tt.name, len(got), len(tt.want), got)
			continue
		}
		for i := range got {
			if got[i] != tt.want[i] {
				t.Errorf("%s: [%d] = %q, want %q", tt.name, i, got[i], tt.want[i])
			}
		}
	}
}

func TestCreateAndVote(t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice))

	id := CreatePoll(cross, "Best chain?", "gno,eth,btc")
	if id != 0 {
		t.Fatalf("first poll id = %d, want 0", id)
	}
	if PollCount() != 1 {
		t.Fatalf("PollCount = %d, want 1", PollCount())
	}

	// alice votes gno.
	Vote(cross, id, 0)

	// bob votes eth.
	testing.SetRealm(testing.NewUserRealm(bob))
	Vote(cross, id, 1)

	// carol votes gno.
	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross, id, 0)

	p := getPoll(id)
	if p.Tallies[0] != 2 {
		t.Errorf("gno tally = %d, want 2", p.Tallies[0])
	}
	if p.Tallies[1] != 1 {
		t.Errorf("eth tally = %d, want 1", p.Tallies[1])
	}
	if total(p.Tallies) != 3 {
		t.Errorf("total = %d, want 3", total(p.Tallies))
	}
}

func TestDoubleVotePanics(t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice))

	id := CreatePoll(cross, "Coffee or tea?", "coffee,tea")
	Vote(cross, id, 0)

	// A second vote by the same address aborts (cross-realm panic).
	uassert.AbortsWithMessage(t, "address already voted on this poll", func() {
		Vote(cross, id, 1)
	})
}

func TestVoteBounds(t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice))

	id := CreatePoll(cross, "A or B?", "a,b")

	uassert.AbortsWithMessage(t, "option index out of range", func() {
		Vote(cross, id, 5)
	})
}

func TestCreatePollNeedsTwoOptions(t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice))

	uassert.AbortsWithMessage(t, "a poll needs at least 2 options", func() {
		CreatePoll(cross, "One?", "only")
	})
}

func TestRender(t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice))

	// Empty index.
	if got := Render(""); !strings.Contains(got, "No polls yet") {
		t.Errorf("empty Render should mention no polls, got:\n%s", got)
	}

	id := CreatePoll(cross, "Pick one", "x,y")
	Vote(cross, id, 0)

	// Index lists the poll and bar chart glyphs.
	idx := Render("")
	if !strings.Contains(idx, "Pick one") {
		t.Errorf("index missing question:\n%s", idx)
	}
	if !strings.Contains(idx, "▓") || !strings.Contains(idx, "░") {
		t.Errorf("index missing bar glyphs:\n%s", idx)
	}
	if !strings.Contains(idx, "Total votes: 1") {
		t.Errorf("index missing total votes:\n%s", idx)
	}
	if !strings.Contains(idx, "100%") {
		t.Errorf("index missing 100%% for the sole vote:\n%s", idx)
	}

	// Single-poll path.
	single := Render("0")
	if !strings.Contains(single, "Poll #0") {
		t.Errorf("single Render missing poll header:\n%s", single)
	}

	// Unknown path.
	if got := Render("99"); !strings.Contains(got, "not found") {
		t.Errorf("unknown poll should say not found, got:\n%s", got)
	}
}
