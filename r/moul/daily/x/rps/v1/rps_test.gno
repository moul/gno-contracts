package rps

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

func TestDecideAndParse(t *testing.T) {
	// parseChoice.
	cases := []struct {
		in   string
		want int
		ok   bool
	}{
		{"rock", rock, true},
		{"PAPER", paper, true},
		{" scissors ", scissors, true},
		{"r", rock, true},
		{"p", paper, true},
		{"s", scissors, true},
		{"lizard", 0, false},
	}
	for _, c := range cases {
		got, ok := parseChoice(c.in)
		uassert.Equal(t, c.ok, ok, "ok for "+c.in)
		if ok {
			uassert.Equal(t, c.want, got, "move for "+c.in)
		}
	}

	// decide: player perspective.
	uassert.Equal(t, outDraw, decide(rock, rock), "rock vs rock")
	uassert.Equal(t, outWin, decide(rock, scissors), "rock beats scissors")
	uassert.Equal(t, outLose, decide(rock, paper), "rock loses to paper")
	uassert.Equal(t, outWin, decide(paper, rock), "paper beats rock")
	uassert.Equal(t, outWin, decide(scissors, paper), "scissors beats paper")
	uassert.Equal(t, outLose, decide(scissors, rock), "scissors loses to rock")

	// houseMove determinism.
	uassert.Equal(t, houseMove(10, 0), houseMove(10, 0), "same inputs -> same move")
	if houseMove(10, 0) == houseMove(10, 1) && houseMove(10, 1) == houseMove(10, 2) {
		t.Error("play count should vary house move across values")
	}
}

func TestPlayRecordsTally(cur realm, t *testing.T) {
	user := testutils.TestAddress("rps-player")
	testing.SetRealm(testing.NewUserRealm(user))

	before := totalRounds
	cross(cur, Play, "rock")
	cross(cur, Play, "paper")
	cross(cur, Play, "scissors")

	uassert.Equal(t, before+3, totalRounds, "global rounds incremented")

	tl := getTally(user.String())
	uassert.True(t, tl != nil, "player tally exists")
	uassert.Equal(t, 3, tl.plays, "player played 3 rounds")
	uassert.Equal(t, tl.wins+tl.losses+tl.draws, tl.plays, "outcomes sum to plays")

	// Render must show the global tally header and the player.
	out := Render("")
	uassert.True(t, strings.Contains(out, "Global tally"), "render has global tally")
	uassert.True(t, strings.Contains(out, "Recent rounds"), "render has recent rounds")

	// Invalid choice aborts (crossing fn -> cross-realm abort).
	uassert.AbortsWithMessage(t, "invalid choice: use rock, paper, or scissors", func() {
		cross(cur, Play, "lizard")
	})
}
