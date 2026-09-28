package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// TestReactionBlockRenders exercises the cross-realm call itself, which is the
// only thing that can find the failure mode this realm is exposed to: it is
// private = true, and a private realm that hands one of its own objects to
// another realm panics at RUNTIME with "cannot persist object from the private
// realm", where gno lint sees nothing (AGENTS.md, ADR 0044). Only strings cross
// here, in both directions, and this test is what says so.
func TestReactionBlockRenders(t *testing.T) {
	reset()
	seed("layout", "# page\n\n:reactions:\n")

	got := Render("")
	uassert.True(t, strings.Contains(got, "(/r/moul/reactions/v0$help&func=React&"),
		"the block's txlinks target the reactions realm")
	uassert.True(t, strings.Contains(got, "page=gno.land%2Fr%2Fmoul%2Fhome"),
		"keyed on this realm's path, which is what makes the tally this page's")
	uassert.True(t, strings.Contains(got, "*no reactions yet*"))
}

// TestReactionsIsAReservedSlug: the placeholder is computed, so a slot may not
// take its name and shadow it. gnohome refuses the same name off chain, before
// the gas is spent (tools/gnohome/content.go).
func TestReactionsIsAReservedSlug(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(admin))
	uassert.AbortsWithMessage(t, cur,
		"reserved slug: reactions is computed at render time", func() {
			Set(cross(cur), "reactions", "nope")
		})
}

// TestLayoutWithoutTheBlockCallsNothing is the property that makes the
// placeholder free: dynreplacer only invokes a callback whose placeholder
// occurs in the layout, so a layout that drops :reactions: does not reach into
// the reactions realm at all.
func TestLayoutWithoutTheBlockCallsNothing(t *testing.T) {
	reset()
	seed("layout", "# page\n\nnothing here\n")
	uassert.Equal(t, "# page\n\nnothing here\n", Render(""))
}
