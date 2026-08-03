package gns

import (
	"strings"
	"testing"
)

func TestRenderRoutes(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetText(cross(cur), "alice", "com.github", "moul")

	home := Render("")
	isTrue(t, strings.Contains(home, "GNS"), "home mentions GNS")
	isTrue(t, strings.Contains(home, "Registered names"), "home shows stats")

	name := Render("name/alice")
	isTrue(t, strings.Contains(name, "alice"), "name page has name")
	isTrue(t, strings.Contains(name, alice.String()), "name page shows owner")
	isTrue(t, strings.Contains(name, "com.github"), "name page shows records")

	avail := Render("available/freeone")
	isTrue(t, strings.Contains(avail, "Available"), "available page")

	help := Render("help")
	isTrue(t, strings.Contains(help, "Register"), "help lists API")

	events := Render("events")
	isTrue(t, strings.Contains(events, "events"), "events page")
}

func TestRenderNoMutation(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	before := names.Size()
	_ = Render("name/alice")
	_ = Render("")
	_ = Render("available/whatever")
	after := names.Size()
	eqInt(t, int64(before), int64(after), "Render does not mutate state")
}

func TestEnumerationBounded(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "one", alice, 100000)
	doRegister(cur, "two", alice, 100000)
	doRegister(cur, "three", alice, 100000)

	page := NamesByOwner(alice.String(), "", 2)
	eqInt(t, 2, int64(len(page.Items)), "page limited to 2")
	isTrue(t, page.Next != "", "cursor for next page")

	// invariant 15: hard cap even when a huge limit is requested.
	page2 := NamesByOwner(alice.String(), "", 65535)
	isTrue(t, len(page2.Items) <= 200, "hard cap applied")
}
