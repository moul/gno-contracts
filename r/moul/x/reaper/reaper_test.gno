package reaper

import (
	"strings"
	"testing"

	"gno.land/p/moul/x/storagecost/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	poster = testutils.TestAddress("poster")
	// stranger never posts, it only deletes. The whole point of the realm is
	// that this is the address the chain pays.
	stranger = testutils.TestAddress("stranger")
)

// ttlFuture is the ttl used for a note that must not be reapable yet. It is a
// named constant because clear has to outrun it.
const ttlFuture = 1000

// clear empties the board so a test starts from a known state, whatever ran
// before it.
//
// gno resets the block height for each test function but keeps realm state, so
// a test that left an unexpired note behind cannot be cleaned up by a later
// test skipping heights: the later test's clock starts over. Every test that
// posts a future-dated note therefore drains it before returning, and clear
// asserts an empty board rather than trusting that.
//
// clear cannot reset TotalSize, which is append-addressed for the life of the
// realm, so tests assert on Live and Reapable and never on absolute indices.
func clear(cur realm, t *testing.T) {
	t.Helper()
	drain(cur)
	uassert.Equal(t, 0, Live())
	uassert.Equal(t, 0, Reapable())
}

// drain expires everything outstanding and reaps it.
func drain(cur realm) {
	testing.SkipHeights(ttlFuture + 1)
	testing.SetRealm(testing.NewUserRealm(stranger))
	for Reapable() > 0 {
		Reap(cross(cur), 1000)
	}
	Compact(cross(cur))
}

func TestPostLocksAndReapFrees(cur realm, t *testing.T) {
	clear(cur, t)

	testing.SetRealm(testing.NewUserRealm(poster))
	Post(cross(cur), "first", 0)
	Post(cross(cur), "second", 0)
	uassert.Equal(t, 2, Live())
	uassert.Equal(t, 2, Reapable())

	// A stranger who posted nothing may reap, and that is the point.
	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.Equal(t, 2, Reap(cross(cur), 100))
	uassert.Equal(t, 0, Live())
	uassert.Equal(t, 0, Reapable())
}

func TestReapSkipsUnexpiredAndHonoursLimit(cur realm, t *testing.T) {
	clear(cur, t)
	testing.SetRealm(testing.NewUserRealm(poster))

	Post(cross(cur), "ripe one", 0)
	Post(cross(cur), "ripe two", 0)
	Post(cross(cur), "not yet", ttlFuture)
	uassert.Equal(t, 3, Live())
	uassert.Equal(t, 2, Reapable())

	// The limit caps the work, so a reaper can size a transaction to its gas.
	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.Equal(t, 1, Reap(cross(cur), 1))
	uassert.Equal(t, 1, Reapable())

	// The unexpired note survives a reap that asks for everything.
	uassert.Equal(t, 1, Reap(cross(cur), 100))
	uassert.Equal(t, 0, Reapable())
	uassert.Equal(t, 1, Live())

	// Leave nothing behind: the next test's height starts over and could not
	// expire this note.
	drain(cur)
}

func TestReapOfNothingIsNotAnError(cur realm, t *testing.T) {
	clear(cur, t)
	// A bot that races another bot to the same notes must not revert, or it
	// loses its gas to an abort instead of merely earning nothing.
	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.Equal(t, 0, Reap(cross(cur), 100))
}

func TestCompactFollowsReaping(cur realm, t *testing.T) {
	clear(cur, t)
	testing.SetRealm(testing.NewUserRealm(poster))
	for i := 0; i < 8; i++ {
		Post(cross(cur), "note", 0)
	}

	// Nothing is reclaimable until something has been reaped.
	uassert.Equal(t, 0, Compactable())

	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.Equal(t, 8, Reap(cross(cur), 100))
	uassert.True(t, Compactable() > 0)

	freed := Compact(cross(cur))
	uassert.True(t, freed > 0)
	uassert.Equal(t, 0, Compactable())
	// Compacting twice is not an error, it just frees nothing.
	uassert.Equal(t, 0, Compact(cross(cur)))
}

func TestPostRejectsBadInput(cur realm, t *testing.T) {
	clear(cur, t)
	testing.SetRealm(testing.NewUserRealm(poster))

	uassert.AbortsWithMessage(t, cur, "reaper: empty note", func() {
		Post(cross(cur), "", 0)
	})
	uassert.AbortsWithMessage(t, cur, "reaper: negative ttl", func() {
		Post(cross(cur), "fine", -1)
	})
	// The cap keeps one call from locking an unbounded deposit.
	uassert.AbortsWithMessage(t, cur, "reaper: note too long, 4097 bytes against a 4096 cap", func() {
		Post(cross(cur), strings.Repeat("x", maxBody+1), 0)
	})
	uassert.AbortsWithMessage(t, cur, "reaper: limit must be positive", func() {
		Reap(cross(cur), 0)
	})
}

func TestBountyPricesWhatIsOnTheTable(cur realm, t *testing.T) {
	clear(cur, t)

	// An empty board advertises nothing, and must not claim a profit.
	empty := Bounty()
	uassert.Equal(t, int64(0), empty.Bytes)
	uassert.Equal(t, int64(0), empty.Refund)
	uassert.False(t, empty.Worth())

	testing.SetRealm(testing.NewUserRealm(poster))
	body := strings.Repeat("x", 1024)
	for i := 0; i < 10; i++ {
		Post(cross(cur), body, 0)
	}

	// Ten 1 KB notes, priced through the same estimate the library documents.
	q := Bounty()
	uassert.Equal(t, storagecost.EstimateBytes(10*1024), q.Bytes)
	uassert.Equal(t, storagecost.Refund(q.Bytes, storagecost.DefaultStoragePrice), q.Refund)
	uassert.True(t, q.Worth())

	// Once reaped, nothing is on the table.
	testing.SetRealm(testing.NewUserRealm(stranger))
	Reap(cross(cur), 100)
	uassert.Equal(t, int64(0), Bounty().Bytes)
}

func TestRenderShowsTheBountyAndTheReapLink(cur realm, t *testing.T) {
	clear(cur, t)

	// Empty board: an invitation, and no bounty claimed.
	out := Render("")
	uassert.True(t, strings.Contains(out, "# Reaper"), out)
	uassert.True(t, strings.Contains(out, "Nothing has expired"), out)
	uassert.True(t, strings.Contains(out, "Post the first note"), out)

	testing.SetRealm(testing.NewUserRealm(poster))
	Post(cross(cur), strings.Repeat("y", 1024), 0)

	out = Render("")
	uassert.True(t, strings.Contains(out, "1 expired notes"), out)
	uassert.True(t, strings.Contains(out, "refunds roughly **0.1894 GNOT**"), out)
	// The reap link must be a help link for the right function with the right
	// argument, or the button on the page does nothing useful. txlink builds
	// it relative to the current realm, so there is no path to get wrong.
	uassert.True(t, strings.Contains(out, "$help&func=Reap&limit=100"), out)
	// The author is named, which is what makes "the poster paid" visible.
	uassert.True(t, strings.Contains(out, poster.String()), out)
	uassert.True(t, strings.Contains(out, "**reapable**"), out)

	// A long note is summarized rather than dumped into the table.
	uassert.True(t, strings.Contains(out, "..."), out)
	uassert.False(t, strings.Contains(out, strings.Repeat("y", 200)), "body should be truncated")
}

func TestRenderNeverEmitsTwoBlankLines(cur realm, t *testing.T) {
	// gno collapses two consecutive blank lines, so output containing them can
	// never be pinned by an Example. This test is what lets ExampleRender stay
	// meaningful.
	clear(cur, t)
	testing.SetRealm(testing.NewUserRealm(poster))
	Post(cross(cur), "one", 0)
	Post(cross(cur), "two", ttlFuture)
	testing.SetRealm(testing.NewUserRealm(stranger))
	Reap(cross(cur), 1)

	for _, path := range []string{"", "anything"} {
		out := Render(path)
		uassert.False(t, strings.Contains(out, "\n\n\n"), "blank-line run in Render("+path+")")
	}

	drain(cur)
}

func TestReapWalksNewestFirstSoCompactionHasWork(cur realm, t *testing.T) {
	// The ordering is economic, not cosmetic: in the backing list the oldest
	// indices are the ancestors of the newest, so a partial reap that took the
	// oldest first would leave nothing compactable and strand the tree
	// structure, which costs more than the notes do.
	clear(cur, t)
	testing.SetRealm(testing.NewUserRealm(poster))
	for i := 0; i < 16; i++ {
		Post(cross(cur), "note", 0)
	}
	first := notes.TotalSize() - 16
	last := notes.TotalSize() - 1

	testing.SetRealm(testing.NewUserRealm(stranger))
	uassert.Equal(t, 4, Reap(cross(cur), 4))

	// The four highest indices went, and the four lowest survived.
	uassert.Equal(t, nil, notes.Get(last))
	uassert.True(t, notes.Get(first) != nil)

	// Which is the whole point: there is something to compact after one batch.
	uassert.True(t, Compactable() > 0)

	drain(cur)
}
