package polls

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// What a creator may store is bounded, and the root page renders a fixed
// window of the newest polls whatever the count.
func TestPollsAreBounded(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("bounded")))
	uassert.AbortsContains(t, cur, "question too long", func() { CreatePoll(cross(cur), strings.Repeat("q", MaxQuestionLen+1), "a,b") })
	uassert.AbortsContains(t, cur, "at most", func() { CreatePoll(cross(cur), "many", strings.Repeat("o,", MaxOptions)+"o") })
	for len(polls) < IndexRecent+3 {
		CreatePoll(cross(cur), "filler", "a,b")
	}
	uassert.Equal(t, IndexRecent, strings.Count(Render(""), "## Poll #"))
}

// The poll count is bounded globally.
func TestPollCountIsBounded(cur realm, t *testing.T) {
	before := len(polls)
	for len(polls) < MaxPolls {
		polls = append(polls, &Poll{ID: len(polls), Question: "q", Options: []string{"a", "b"}, Tallies: []int{0, 0}})
	}
	defer func() { polls = polls[:before] }()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("latecomer")))
	uassert.AbortsContains(t, cur, "polls is full", func() { CreatePoll(cross(cur), "one more", "a,b") })
}
