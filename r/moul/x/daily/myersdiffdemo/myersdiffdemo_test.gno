package myersdiffdemo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestUnknownPathFallsBackToTheIndex(t *testing.T) {
	index := Render("")
	uassert.Equal(t, index, Render("/"))
	uassert.Equal(t, index, Render("/nope"))
	uassert.Equal(t, index, Render("/patch2"))
}

// TestNoCallerEchoOnThePage is the escaping question asked the only way that
// settles it: feed the path every construct the sanitizer exists to stop, then
// assert none of it reached the page. This realm answers by never rendering a
// caller string at all, so the assertion is that the output is byte-identical
// to the index.
func TestNoCallerEchoOnThePage(t *testing.T) {
	index := Render("")
	hostile := []string{
		"/[click](https://evil.example)",
		"/![x](https://evil.example/p.png)",
		"/<gno-columns>",
		"/a`b",
		"/x\ny",
		"/patch/[link](https://evil.example)",
	}
	for _, p := range hostile {
		got := Render(p)
		uassert.False(t, strings.Contains(got, "evil.example"), "a caller URL reached the page")
		uassert.False(t, strings.Contains(got, "<gno-"), "caller chrome reached the page")
		if !strings.HasPrefix(p, "/patch/") {
			uassert.Equal(t, index, got)
		}
	}
	// A hostile context segment is parsed as an integer, fails, and leaves the
	// default width, so the page is the ordinary one.
	uassert.Equal(t, Render("/patch"), Render("/patch/[link](https://evil.example)"))
}

func TestContextIsClamped(t *testing.T) {
	uassert.Equal(t, Render("/patch/0"), Render("/patch/-3"))
	uassert.Equal(t, Render("/patch/6"), Render("/patch/99"))
	uassert.Equal(t, Render("/patch/2"), Render("/patch"))

	// Context 0 prints changed lines only, so no unchanged line of the fixture
	// survives into the diff body.
	narrow := Render("/patch/0")
	uassert.False(t, strings.Contains(narrow, " package main"), "context 0 printed an unchanged line")
	wide := Render("/patch/6")
	uassert.True(t, strings.Contains(wide, " package main"), "context 6 dropped an unchanged line")
}

func TestStarvedScenarioSaysSo(t *testing.T) {
	page := Render("/starved")
	uassert.True(t, strings.Contains(page, "| minimal | no |"), "the starved page should report a non-minimal script")
	uassert.True(t, strings.Contains(page, "reproduces the right one **yes**"), "a non-minimal script still applies")

	ok := Render("/move")
	uassert.True(t, strings.Contains(ok, "| minimal | yes |"), "the move page should report a minimal script")
}

// TestEveryScenarioApplies walks the whole table rather than the one scenario a
// hand-written test would pick: a fixture added later is covered the day it is
// added, not the day someone remembers it.
func TestEveryScenarioApplies(t *testing.T) {
	for _, sc := range scenarios {
		s := diffOf(sc)
		uassert.True(t, applies(sc, s), "scenario "+sc.key+" does not replay into its right-hand document")
		page := Render("/" + sc.key)
		uassert.True(t, strings.Contains(page, "```diff"), "scenario "+sc.key+" rendered no diff block")
	}
}
