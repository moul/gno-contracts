package relay

import (
	"strings"
	"testing"

	"gno.land/p/moul/agents/msg/v0"
	"gno.land/p/moul/x/daily/ringbuffer/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

// reset puts the realm back to its init() state. Realm globals persist for the
// whole test binary and examples run after every Test, so every test that
// writes starts here and ExampleRender builds its own state.
func reset() {
	log = ringbuffer.New(Slots)
	seq = 0
	seen = 0
}

func TestPostAssignsSeqAndAuthor(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	got := Post(cross(cur), "agent-a", "build", "note", "pr/1", "first")

	uassert.Equal(t, uint64(1), got)
	uassert.Equal(t, 1, Len())
	uassert.Equal(t, 1, Seen())

	e := Latest(0)[0]
	uassert.Equal(t, uint64(1), e.Msg.Seq)
	uassert.Equal(t, "agent-a", e.Msg.From)
	uassert.Equal(t, alice.String(), e.Author.String())
}

func TestSeqIsMonotonicAcrossAuthors(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "agent-a", "build", "", "", "one")
	testing.SetRealm(testing.NewUserRealm(bob))
	Post(cross(cur), "agent-b", "build", "", "", "two")

	all := Latest(0) // newest first
	uassert.Equal(t, uint64(2), all[0].Msg.Seq)
	uassert.Equal(t, bob.String(), all[0].Author.String())
	uassert.Equal(t, uint64(1), all[1].Msg.Seq)
	uassert.Equal(t, alice.String(), all[1].Author.String())
}

func TestRingDropsTheOldestAndSeenKeepsCounting(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	for i := 0; i < Slots+5; i++ {
		Post(cross(cur), "agent-a", "build", "", "", "body")
	}
	uassert.Equal(t, Slots, Len())
	uassert.Equal(t, Slots+5, Seen())

	// The five oldest fell off the back; the newest is the last one posted.
	all := Latest(0)
	uassert.Equal(t, uint64(Slots+5), all[0].Msg.Seq)
	uassert.Equal(t, uint64(6), all[len(all)-1].Msg.Seq)
}

func TestSinceAndTopicFilter(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "agent-a", "build", "", "", "b1")
	Post(cross(cur), "agent-a", "deploy", "", "", "d1")
	Post(cross(cur), "agent-a", "build", "", "", "b2")

	since := Since(1) // oldest first
	uassert.Equal(t, 2, len(since))
	uassert.Equal(t, uint64(2), since[0].Msg.Seq)
	uassert.Equal(t, uint64(3), since[1].Msg.Seq)
	uassert.Equal(t, 0, len(Since(3)))

	build := Topic("build") // newest first
	uassert.Equal(t, 2, len(build))
	uassert.Equal(t, "b2", build[0].Msg.Body)
	uassert.Equal(t, 0, len(Topic("nothing-here")))
}

func TestLatestRespectsN(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	for i := 0; i < 5; i++ {
		Post(cross(cur), "agent-a", "build", "", "", "body")
	}
	uassert.Equal(t, 2, len(Latest(2)))
	uassert.Equal(t, 5, len(Latest(0)))
	uassert.Equal(t, 5, len(Latest(-1)))
}

func TestPostRejectsInvalidFields(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "empty topic", func() {
		Post(cross(cur), "agent-a", "", "", "", "body")
	})
	uassert.AbortsWithMessage(t, cur, "topic must be lowercase a-z, 0-9, dash or dot", func() {
		Post(cross(cur), "agent-a", "Build", "", "", "body")
	})
	uassert.AbortsWithMessage(t, cur, "empty body", func() {
		Post(cross(cur), "agent-a", "build", "", "", "")
	})
	uassert.Equal(t, 0, Len())
	uassert.Equal(t, 0, Seen())
}

// TestBodySurvivesTheEncoding is the regression test for the framing: a body
// that looks like the encoding, or ends in the digits a length prefix is made
// of, must come back unchanged with its author still attached.
func TestBodySurvivesTheEncoding(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	nasty := []string{
		"ends in 40",
		"3:abc",
		"has\na newline",
		msg.Msg{Seq: 9, Height: 9, From: "x", Topic: "y", Kind: "z", Ref: "w", Body: "v"}.Encode(),
		"| breaks | a | table |",
	}
	for _, body := range nasty {
		Post(cross(cur), "agent-a", "build", "", "", body)
	}
	got := Latest(0) // newest first
	for i, body := range nasty {
		e := got[len(nasty)-1-i]
		uassert.Equal(t, body, e.Msg.Body)
		uassert.Equal(t, alice.String(), e.Author.String())
	}
}

// TestRenderEscapesACallersString pins what guard-untrusted-render exists for:
// a pipe in a body must not open a column in the rendered table.
func TestRenderEscapesACallersString(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "agent-a", "build", "", "", "a | b")

	out := Render("")
	uassert.False(t, strings.Contains(out, "| a | b |"),
		"an unescaped pipe opened a column in the rendered table")
}

// TestRenderEscapesABodyExactlyOnce is the regression test for the v0 bug.
// ui.Cell(ui.Excerpt(s)) escaped twice, so a hyphen reached mainnet as
// backslash-backslash-backslash-hyphen. Over-escaping is not a security hole,
// which is exactly why the pipe test above passed while this was broken: a
// doubly escaped pipe is still safe and still wrong.
func TestRenderEscapesABodyExactlyOnce(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "agent-a", "build", "", "", "evicting in-call")

	out := Render("")
	uassert.True(t, strings.Contains(out, `evicting in\-call`),
		"a hyphen in a short body should be escaped once")
	uassert.False(t, strings.Contains(out, `in\\-call`),
		"the body was escaped more than once")
}

// TestRenderEscapesALongBodyExactlyOnce covers the other branch of
// excerptCell, where the body is cut before it is escaped.
func TestRenderEscapesALongBodyExactlyOnce(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	long := "evicting in-call"
	for len(long) < 200 {
		long += " and-again"
	}
	Post(cross(cur), "agent-a", "build", "", "", long)

	out := Render("")
	uassert.True(t, strings.Contains(out, `evicting in\-call`),
		"a hyphen in a cut body should be escaped once")
	uassert.False(t, strings.Contains(out, `in\\-call`),
		"the cut body was escaped more than once")
}

// TestPostRecordsNoSessionForAMasterKey pins the empty-session branch. A test
// signs as a plain user realm, never through a session, so isSession is false
// and Session must stay empty rather than inherit the author.
func TestPostRecordsNoSessionForAMasterKey(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "agent-a", "build", "", "", "body")

	e := Latest(0)[0]
	uassert.Equal(t, alice.String(), e.Author.String())
	uassert.Equal(t, "", e.Session.String())
}
