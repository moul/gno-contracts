package blog

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestPublishAndRender(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	id0 := Publish(cross(cur), "First Post", "Hello from alice.")
	uassert.Equal(t, 0, id0)

	testing.SetRealm(testing.NewUserRealm(bob))
	id1 := Publish(cross(cur), "Second Post", "A longer body\nwith a newline from bob.")
	uassert.Equal(t, 1, id1)

	uassert.Equal(t, 2, PostCount())

	// Root render lists both, newest (bob's) first.
	list := Render("")
	uassert.True(t, strings.Contains(list, "First Post"), "list has first post")
	uassert.True(t, strings.Contains(list, "Second Post"), "list has second post")
	uassert.True(t, strings.Index(list, "Second Post") < strings.Index(list, "First Post"),
		"newest post appears first")
	uassert.True(t, strings.Contains(list, alice.String()), "list shows alice author")

	// Single-post render shows full body + back link.
	single := Render("/1")
	uassert.True(t, strings.Contains(single, "newline from bob"), "full body shown")
	uassert.True(t, strings.Contains(single, "← back"), "back link present")

	// Unknown id.
	uassert.True(t, strings.Contains(Render("/99"), "Not found"), "missing post handled")
}

func TestPublishEmptyTitleAborts(cur realm, t *testing.T) {
	carol := testutils.TestAddress("carol")
	testing.SetRealm(testing.NewUserRealm(carol))

	uassert.AbortsWithMessage(t, cur, "blog: title must not be empty", func() {
		Publish(cross(cur), "   ", "some body")
	})
	uassert.AbortsWithMessage(t, cur, "blog: body must not be empty", func() {
		Publish(cross(cur), "a title", "")
	})
}
