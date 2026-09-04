package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var notAdmin = testutils.TestAddress("mallory")

// reset restores the globals to what init() sets, so assertions do not depend
// on which tests ran before. Realm globals persist for the whole test binary.
func reset() {
	todos = []string{"fill this todo list..."}
	status = "Online"
	memeImgURL = "https://i.imgflip.com/7ze8dc.jpg"
}

// ExampleRender pins the dashboard's default output. It resets state first so
// the example is deterministic regardless of test ordering (Go runs examples
// after tests, and the tests below mutate these globals).
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # Manfred's (gn)home Dashboard
	//
	// ## Meme
	// ![](https://i.imgflip.com/7ze8dc.jpg)
	//
	// ## Status
	// Online
	//
	// ## Personal ToDo List
	// - [ ] fill this todo list...
}

// TestRenderIgnoresPath documents that Render serves the same dashboard for
// any path — it takes no sub-routes.
func TestRenderIgnoresPath(t *testing.T) {
	reset()
	uassert.Equal(t, Render(""), Render("/anything"))
}

// TestRenderReflectsState checks Render tracks the admin-mutable fields.
func TestRenderReflectsState(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	UpdateStatus(cross(cur), "Away")
	AddNewTodo(cross(cur), "ship the thing")

	out := Render("")
	uassert.True(t, strings.Contains(out, "## Status\nAway\n"), "status should show Away")
	uassert.True(t, strings.Contains(out, "- [ ] ship the thing\n"), "new todo should be listed")
	uassert.True(t, strings.Contains(out, "- [ ] fill this todo list...\n"), "original todo should remain")
}

// TestDeleteTodo removes by index and keeps the rest.
func TestDeleteTodo(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	AddNewTodo(cross(cur), "first")
	AddNewTodo(cross(cur), "second")
	DeleteTodo(cross(cur), 1) // drop "first"

	out := Render("")
	uassert.False(t, strings.Contains(out, "- [ ] first\n"), "deleted todo should be gone")
	uassert.True(t, strings.Contains(out, "- [ ] second\n"), "other todo should remain")
}

// TestDeleteTodoOutOfRange covers both bounds of the index check.
func TestDeleteTodoOutOfRange(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))

	uassert.AbortsWithMessage(t, cur, "Invalid todo index", func() {
		DeleteTodo(cross(cur), -1)
	})
	uassert.AbortsWithMessage(t, cur, "Invalid todo index", func() {
		DeleteTodo(cross(cur), len(todos))
	})
}

// TestAdminGating checks every mutator rejects a non-admin caller.
func TestAdminGating(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(notAdmin))

	uassert.AbortsWithMessage(t, cur, "restricted to admin", func() {
		AddNewTodo(cross(cur), "nope")
	})
	uassert.AbortsWithMessage(t, cur, "restricted to admin", func() {
		DeleteTodo(cross(cur), 0)
	})
	uassert.AbortsWithMessage(t, cur, "restricted to admin", func() {
		UpdateStatus(cross(cur), "hacked")
	})

	// State must be untouched.
	uassert.Equal(t, "Online", status)
	uassert.Equal(t, 1, len(todos))
}
