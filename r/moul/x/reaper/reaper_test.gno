package reaper

import (
	"strings"
	"testing"
	"unicode/utf8"

	"gno.land/p/moul/kit/ui/v0"
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
	// The author is named, in the house address format, which is what makes
	// "the poster paid" visible without 40 opaque characters per row.
	uassert.True(t, strings.Contains(out, ui.Addr(poster)), out)
	uassert.True(t, strings.Contains(out, "**reapable**"), out)

	// A long note is summarized rather than dumped into the table.
	uassert.True(t, strings.Contains(out, ui.Ellipsis), out)
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

// TestSummarizeNeutralizesAnAttackerAuthoredBody is the regression test for a
// hole this realm shipped with: Render emitted a note body into the board
// after nothing but a ReplaceAll of "\n" and "|", so anyone who paid to post
// could put arbitrary markdown on a page every reader of the realm loads.
//
// The body is the one string here an attacker controls and the board is an
// INLINE slot, so sanitize.InlineText owns it. Each case asserts the dangerous
// SEQUENCE is dead and the readable text survived, rather than pinning the
// exact escaped bytes, which are the sanitizer's business and not this realm's.
func TestSummarizeNeutralizesAnAttackerAuthoredBody(t *testing.T) {
	cases := []struct {
		name  string
		body  string
		gone  []string // sequences that must not survive into the page
		kept  string   // the readable text, which must
	}{
		{
			// The payload that matters: a phishing link rendered as prose,
			// attributed by the page to the realm rather than to the poster.
			name: "inline link",
			body: "[Claim your 100 GNOT](https://evil.example/drain)",
			gone: []string{"](", "](https"},
			kept: "Claim your 100 GNOT",
		},
		{
			// An image is a beacon: it fires on load and hands the attacker
			// the IP of everyone who opened the board.
			name: "image beacon",
			body: "![x](https://evil.example/pixel.png)",
			gone: []string{"![", "]("},
			kept: "pixel",
		},
		{
			// gnoweb renders a set of <gno-...> components, and raw HTML
			// besides; a body that can open one can lay out the page.
			name: "gnoweb component and raw html",
			body: "<gno-columns><h5>Official notice</h5>",
			gone: []string{"<gno-", "<h5>", "</h5>"},
			kept: "Official notice",
		},
		{
			// The old ReplaceAll("\n", " ") stopped exactly this and nothing
			// else. Keep it dead: one newline ends the bullet item, and every
			// byte after it is top-level markdown.
			name: "break out of the list item",
			body: "ok\n# Reaper is deprecated, use /r/evil/reaper",
			gone: []string{"\n"},
			kept: "Reaper is deprecated",
		},
		{
			// Folding only "\n" left the other three line terminators open.
			name: "exotic line terminators",
			body: "ok\r\n- fake row\u2028- another\u2029- third",
			gone: []string{"\r", "\n", "\u2028", "\u2029"},
			kept: "fake row",
		},
		{
			// Invisible reordering: the bytes say one thing, the page shows
			// another, and a reader diffing the two sees nothing.
			name: "bidi and zero-width",
			body: "safe\u202enote\u200b\u202c",
			gone: []string{"\u202e", "\u200b", "\u202c"},
			kept: "safe",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			out := summarize(tc.body)
			for _, bad := range tc.gone {
				uassert.False(t, strings.Contains(out, bad),
					tc.name+": a dangerous sequence survived into "+out)
			}
			uassert.True(t, strings.Contains(out, tc.kept),
				tc.name+": escaping ate the readable text: "+out)
			uassert.True(t, utf8.ValidString(out), tc.name+": invalid UTF-8: "+out)
		})
	}
}

// TestSummarizeEscapesAnUnbalancedBracket covers the cross-row case: a "[" in
// one note and a "]" in another used to let two cheap notes bracket every row
// between them into one link.
func TestSummarizeEscapesAnUnbalancedBracket(t *testing.T) {
	uassert.Equal(t, "\\[", summarize("["))
	uassert.Equal(t, "\\]", summarize("]"))
	uassert.Equal(t, "\\[", ui.Excerpt("[", 48))
}

// TestSummarizeCutsOnARuneBoundary pins the other half of the old bug: the
// truncation sliced at a byte offset, so a body of multi-byte characters put
// half a character on the page. One emoji in a note was enough.
func TestSummarizeCutsOnARuneBoundary(t *testing.T) {
	// The leading "x" puts byte 48, the old cut point, in the middle of a
	// 4-byte rune rather than on a boundary.
	out := summarize("x" + strings.Repeat("\U0001F33E", 60))
	uassert.True(t, utf8.ValidString(out), "cut mid-rune: "+out)
	uassert.True(t, strings.HasSuffix(out, ui.Ellipsis), "long body should be elided: "+out)

	// A short body comes back whole, with no elision and nothing to escape.
	short := summarize("plain note")
	uassert.Equal(t, "plain note", short)
}

// TestRenderEscapesTheBoard is the end-to-end half: the sanitizer is only
// worth anything if Render is what calls it, and the board is the one place a
// stranger's bytes reach the page.
func TestRenderEscapesTheBoard(cur realm, t *testing.T) {
	clear(cur, t)
	testing.SetRealm(testing.NewUserRealm(poster))
	Post(cross(cur), "[Claim 100 GNOT](https://evil.example)\n# Official", 0)

	out := Render("")
	uassert.False(t, strings.Contains(out, "](https://evil.example)"), out)
	uassert.False(t, strings.Contains(out, "\n# Official"), out)
	// The note stays legible, just inert: the text survives, the chrome does not.
	uassert.True(t, strings.Contains(out, "Claim 100 GNOT"), out)
	uassert.True(t, utf8.ValidString(out), "Render emitted invalid UTF-8")

	testing.SetRealm(testing.NewUserRealm(stranger))
	Reap(cross(cur), 100)
	Compact(cross(cur))
}
