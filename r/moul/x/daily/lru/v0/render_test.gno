package lru

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// clear empties the cache without needing a realm argument, so examples (which
// take no `cur`) can start from a known state. Examples run after all tests.
func clear() {
	c = &cache{index: make(map[string]*node)}
}

// ExampleRender pins the empty-cache view.
func ExampleRender() {
	clear()
	print(Render(""))
	// Output:
	// # LRU Cache
	//
	// A fixed-capacity least-recently-used cache.
	//
	// ## Stats
	//
	// - Capacity: 8
	// - Size: 0
	// - Hits: 0
	// - Misses: 0
	// - Hit rate: n/a
	//
	// ## Entries (MRU → LRU)
	//
	// _empty_
}

// TestRenderListsEntriesMRUFirst checks the table is ordered most-recently-used
// first and renumbered from 1.
func TestRenderListsEntriesMRUFirst(cur realm, t *testing.T) {
	reset(cur)
	Put(cross(cur), "a", "1")
	Put(cross(cur), "b", "2")
	Put(cross(cur), "c", "3")
	Get(cross(cur), "a") // a becomes MRU

	out := Render("")
	uassert.True(t, strings.Contains(out, "| 1 | a | 1 |\n| 2 | c | 3 |\n| 3 | b | 2 |\n"),
		"entries should be listed MRU->LRU: a, c, b")
	uassert.True(t, strings.Contains(out, "- Size: 3\n"), "size should be 3")
}

// TestRenderHitRate covers the integer-percent branch and the n/a branch.
func TestRenderHitRate(cur realm, t *testing.T) {
	reset(cur)
	uassert.True(t, strings.Contains(Render(""), "- Hit rate: n/a\n"),
		"no lookups yet should render n/a")

	Put(cross(cur), "a", "1")
	Get(cross(cur), "a")   // hit
	Get(cross(cur), "nope") // miss

	out := Render("")
	uassert.True(t, strings.Contains(out, "- Hits: 1\n"), "one hit")
	uassert.True(t, strings.Contains(out, "- Misses: 1\n"), "one miss")
	uassert.True(t, strings.Contains(out, "- Hit rate: 50%\n"), "1/2 should be 50%")
}

// TestRenderCapacityMatchesConst guards the header against a capacity change
// that the pinned example would otherwise silently disagree with.
func TestRenderCapacityMatchesConst(cur realm, t *testing.T) {
	reset(cur)
	uassert.True(t, strings.Contains(Render(""), "- Capacity: "+strconv.Itoa(capacity)+"\n"),
		"rendered capacity should match the constant")
}

// TestRenderIgnoresPath documents that Render has no sub-routes.
func TestRenderIgnoresPath(cur realm, t *testing.T) {
	reset(cur)
	Put(cross(cur), "k", "v")
	uassert.Equal(t, Render(""), Render("/whatever"))
}
