package rps

import (
	"strings"
	"testing"

	"gno.land/p/moul/x/daily/rps/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestDecide(t *testing.T) {
	// decide: player perspective.
	uassert.Equal(t, outDraw, decide(rps.Rock, rps.Rock), "rock vs rock")
	uassert.Equal(t, outWin, decide(rps.Rock, rps.Scissors), "rock beats scissors")
	uassert.Equal(t, outLose, decide(rps.Rock, rps.Paper), "rock loses to paper")
	uassert.Equal(t, outWin, decide(rps.Paper, rps.Rock), "paper beats rock")
	uassert.Equal(t, outWin, decide(rps.Scissors, rps.Paper), "scissors beats paper")
	uassert.Equal(t, outLose, decide(rps.Scissors, rps.Rock), "scissors loses to rock")

	// houseMove determinism.
	uassert.Equal(t, int(houseMove(10, 0)), int(houseMove(10, 0)), "same inputs -> same move")
	if houseMove(10, 0) == houseMove(10, 1) && houseMove(10, 1) == houseMove(10, 2) {
		t.Error("play count should vary house move across values")
	}
}

func TestPlayRecordsTally(cur realm, t *testing.T) {
	user := testutils.TestAddress("rps-player")
	testing.SetRealm(testing.NewUserRealm(user))

	before := totalRounds
	Play(cross(cur),"rock")
	Play(cross(cur),"paper")
	Play(cross(cur),"scissors")

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
	uassert.AbortsWithMessage(t, cur, "invalid choice: use rock, paper, or scissors", func() {
		Play(cross(cur),"lizard")
	})
}
