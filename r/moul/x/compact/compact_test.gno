package compact

import (
	"strings"
	"testing"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/storagecost/v1"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	// janitor never adds anything, it only compacts. The whole point of the
	// realm is that this is the address the chain pays.
	janitor = testutils.TestAddress("janitor")
)

// drain empties the board and asserts it, so a test starts from a known
// state whatever ran before it. Indices are append-addressed for the life of
// the realm, so every test asserts on counts and never on absolute indices.
func drain(cur realm, t *testing.T) {
	t.Helper()
	for i := 0; i < entries.TotalSize(); i++ {
		if e, ok := entryAt(i); ok {
			testing.SetRealm(testing.NewUserRealm(e.Author))
			Drop(cross(cur), i)
		}
	}
	testing.SetRealm(testing.NewUserRealm(janitor))
	Compact(cross(cur))
	live, _ := Fragmentation()
	uassert.Equal(t, 0, live)
}

func TestDropFreesNothingUntilCompact(cur realm, t *testing.T) {
	drain(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	for i := 0; i < 8; i++ {
		Add(cross(cur), "entry")
	}
	live, allocated := Fragmentation()
	uassert.Equal(t, 8, live)
	uassert.Equal(t, 0, Reclaimable())

	// Dropping everything moves the live count but frees no nodes by itself.
	base := allocated - 8
	for i := base; i < allocated; i++ {
		Drop(cross(cur), i)
	}
	live, allocated2 := Fragmentation()
	uassert.Equal(t, 0, live)
	uassert.Equal(t, allocated, allocated2, "a soft delete must not change the index space")
	uassert.True(t, Reclaimable() > 0, "a fully dead tail should be reclaimable")

	// And compaction is what actually frees them.
	testing.SetRealm(testing.NewUserRealm(janitor))
	freed := Compact(cross(cur))
	uassert.True(t, freed > 0)
	uassert.Equal(t, 0, Reclaimable())
	// Compacting twice is not an error, it just frees nothing, so two bots
	// racing for the same nodes both survive rather than one aborting.
	uassert.Equal(t, 0, Compact(cross(cur)))
}

// TestScatteredHolesReclaimLessThanTheGap is the claim the Render makes, and
// the reason the realm publishes two numbers instead of one. No other test
// could catch it: they all drop contiguous runs.
func TestScatteredHolesReclaimLessThanTheGap(cur realm, t *testing.T) {
	drain(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	base := entries.TotalSize()
	for i := 0; i < 16; i++ {
		Add(cross(cur), "entry")
	}
	// Every other index, so no whole subtree dies.
	for i := base; i < base+16; i += 2 {
		Drop(cross(cur), i)
	}
	live, allocated := Fragmentation()
	gap := allocated - live
	uassert.True(t, gap >= 8, "eight holes were made")
	uassert.True(t, Reclaimable() < gap,
		"scattered holes must reclaim fewer nodes than the gap suggests")

	drain(cur, t)
}

func TestOnlyTheAuthorMayDrop(cur realm, t *testing.T) {
	drain(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	i := Add(cross(cur), "alice's entry")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, cur, "compact: only the author may drop an entry", func() {
		Drop(cross(cur), i)
	})
	// But compaction stays permissionless, which is the asymmetry that makes
	// the mechanism work: choosing what dies is owned, reclaiming is not.
	testing.SetRealm(testing.NewUserRealm(janitor))
	uassert.NotAborts(t, cur, func() { Compact(cross(cur)) })

	drain(cur, t)
}

func TestAddRejectsBadInput(cur realm, t *testing.T) {
	drain(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "compact: empty entry", func() {
		Add(cross(cur), "")
	})
	uassert.AbortsWithMessage(t, cur, "compact: entry too long, 257 bytes against a 256 cap", func() {
		Add(cross(cur), strings.Repeat("x", maxText+1))
	})
	uassert.AbortsContains(t, cur, "compact: no live entry at", func() {
		Drop(cross(cur), 99999)
	})
}

// TestQuoteCountsNodesRatherThanGuessingFromPayload is the design claim of the
// realm. The quote must depend on the NODE COUNT and not on how fat the
// entries were, which is exactly where a payload-derived bounty goes wrong.
func TestQuoteCountsNodesRatherThanGuessingFromPayload(cur realm, t *testing.T) {
	drain(cur, t)

	// An empty board advertises nothing and must not claim a profit.
	empty := Quote()
	uassert.Equal(t, int64(0), empty.Bytes)
	uassert.False(t, empty.Worth())

	// Eight tiny entries, dropped and measured.
	testing.SetRealm(testing.NewUserRealm(alice))
	base := entries.TotalSize()
	for i := 0; i < 8; i++ {
		Add(cross(cur), "x")
	}
	for i := base; i < base+8; i++ {
		Drop(cross(cur), i)
	}
	tiny := Quote()
	tinyNodes := Reclaimable()
	testing.SetRealm(testing.NewUserRealm(janitor))
	Compact(cross(cur))

	// Eight fat entries, same count, same treatment.
	testing.SetRealm(testing.NewUserRealm(alice))
	base = entries.TotalSize()
	fat := strings.Repeat("y", maxText)
	for i := 0; i < 8; i++ {
		Add(cross(cur), fat)
	}
	for i := base; i < base+8; i++ {
		Drop(cross(cur), i)
	}
	big := Quote()

	bigNodes := Reclaimable()

	// 256x the payload, and the quote is still purely a function of the node
	// count. Not the same TOTAL: the two batches sit at different offsets in
	// an append-addressed index space, so the tree shape differs and one
	// reclaimed a node more than the other. That is the honest version of the
	// claim, and asserting equal totals (which an earlier draft of this test
	// did) only passed by luck of the offsets.
	uassert.True(t, tinyNodes > 0 && bigNodes > 0)
	uassert.Equal(t, storagecost.EstimateNodes(int64(tinyNodes)), tiny.Bytes)
	uassert.Equal(t, storagecost.EstimateNodes(int64(bigNodes)), big.Bytes)

	// The rate is what must not move: same bytes per reclaimed node whether
	// the entries were 1 byte or 256. A payload-derived bounty would differ
	// by 256x here, which is the failure this realm is built to avoid.
	uassert.Equal(t, tiny.Bytes/int64(tinyNodes), big.Bytes/int64(bigNodes),
		"bytes per reclaimed node must not depend on payload size")

	drain(cur, t)
}

// TestRenderEscapesTheBoard: an entry is a caller's string landing in an
// inline markdown slot, so it goes through ui.Excerpt or it is an injection.
func TestRenderEscapesTheBoard(cur realm, t *testing.T) {
	drain(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	Add(cross(cur), "[Claim 100 GNOT](https://evil.example)\n# Official")

	out := Render("")
	uassert.False(t, strings.Contains(out, "](https://evil.example)"), out)
	uassert.False(t, strings.Contains(out, "\n# Official"), out)
	uassert.True(t, strings.Contains(out, "Claim 100 GNOT"), out)
	uassert.True(t, strings.Contains(out, ui.Addr(alice)), out)

	drain(cur, t)
}

func TestRenderShowsBothIntegersAndTheAction(cur realm, t *testing.T) {
	drain(cur, t)

	out := Render("")
	uassert.True(t, strings.Contains(out, "# Compact"), out)
	uassert.True(t, strings.Contains(out, "Add the first entry"), out)
	uassert.True(t, strings.Contains(out, "nothing to reclaim"), out)

	testing.SetRealm(testing.NewUserRealm(alice))
	base := entries.TotalSize()
	for i := 0; i < 8; i++ {
		Add(cross(cur), "entry")
	}
	for i := base; i < base+8; i++ {
		Drop(cross(cur), i)
	}
	out = Render("")
	uassert.True(t, strings.Contains(out, "reclaimable nodes"), out)
	uassert.True(t, strings.Contains(out, "$help&func=Compact"), out)

	drain(cur, t)
}

// TestRenderNeverEmitsTwoBlankLines is what lets ExampleRender stay
// meaningful: gno collapses them, so output containing them can never be
// pinned by an example.
func TestRenderNeverEmitsTwoBlankLines(cur realm, t *testing.T) {
	drain(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	i := Add(cross(cur), "one")
	Add(cross(cur), "two")
	Drop(cross(cur), i)

	for _, path := range []string{"", "anything"} {
		out := Render(path)
		uassert.False(t, strings.Contains(out, "\n\n\n"), "blank-line run in Render("+path+")")
	}

	drain(cur, t)
}
