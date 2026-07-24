package reactions

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

func TestReactAndRender(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	cross(cur, React, "launch", "👍")

	testing.SetRealm(testing.NewUserRealm(bob))
	cross(cur, React, "launch", "❤️")

	if got := TopicCount(); got != 1 {
		t.Fatalf("expected 1 topic, got %d", got)
	}

	out := Render("launch")
	if !strings.Contains(out, "👍 1") {
		t.Fatalf("expected '👍 1' in render, got:\n%s", out)
	}
	if !strings.Contains(out, "❤️ 1") {
		t.Fatalf("expected '❤️ 1' in render, got:\n%s", out)
	}
	if !strings.Contains(out, "Total reactions:** 2") {
		t.Fatalf("expected total 2 in render, got:\n%s", out)
	}
}

func TestOneReactionPerCaller(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")

	testing.SetRealm(testing.NewUserRealm(alice))
	cross(cur, React, "topicA", "🎉")

	// Second reaction by same caller to same topic must abort.
	uassert.AbortsWithMessage(t, "caller already reacted to this topic: topicA", func() {
		cross(cur, React, "topicA", "😀")
	})
}

func TestCreateTopicAndDuplicate(cur realm, t *testing.T) {
	dave := testutils.TestAddress("dave")
	testing.SetRealm(testing.NewUserRealm(dave))

	cross(cur, CreateTopic, "poll")
	if !topics.Has("poll") {
		t.Fatalf("expected topic 'poll' to exist")
	}

	uassert.AbortsWithMessage(t, "topic already exists: poll", func() {
		cross(cur, CreateTopic, "poll")
	})

	// A freshly created topic renders as having no reactions.
	out := Render("poll")
	if !strings.Contains(out, "no reactions yet") {
		t.Fatalf("expected empty-topic notice, got:\n%s", out)
	}
}

func TestTallyRowOrdering(cur realm, t *testing.T) {
	a := testutils.TestAddress("u1")
	b := testutils.TestAddress("u2")
	c := testutils.TestAddress("u3")

	testing.SetRealm(testing.NewUserRealm(a))
	cross(cur, React, "party", "🎉")
	testing.SetRealm(testing.NewUserRealm(b))
	cross(cur, React, "party", "🎉")
	testing.SetRealm(testing.NewUserRealm(c))
	cross(cur, React, "party", "👍")

	out := Render("party")
	// 🎉 has 2, 👍 has 1 — 🎉 must come first (count desc).
	iParty := strings.Index(out, "🎉 2")
	iThumb := strings.Index(out, "👍 1")
	if iParty < 0 || iThumb < 0 {
		t.Fatalf("expected both tallies in render, got:\n%s", out)
	}
	if iParty > iThumb {
		t.Fatalf("expected 🎉 before 👍 by count, got:\n%s", out)
	}
}
