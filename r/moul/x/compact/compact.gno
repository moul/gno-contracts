// Package compact makes fragmentation a number you can act on.
//
// A soft delete does not free anything. It clears the element and leaves the
// tree node behind, so the bytes stay locked and every read still walks past
// them. Compacting drops those nodes and the chain refunds their deposit to
// whoever signed the transaction. So compaction is paid work, and the only
// real question is WHEN: too early and you free too few nodes to cover the
// gas, too late and every read has been paying for the holes in between.
//
// This realm refuses to answer that question, on purpose. It publishes the
// two integers the answer is made of and lets whoever is watching decide,
// because the realm cannot see the gas price of the day and the caller can.
//
//   - Fragmentation() is live vs allocated, the free read a bot polls.
//   - Reclaimable() is what a Compact would actually free, right now.
//   - Quote() prices it at the floor gas price, as an advertisement.
//
// The arithmetic is gno.land/p/moul/x/storagecost and the container is
// gno.land/p/moul/ulist, whose Compact drops dead nodes without moving a live
// index, so an index is stable for the life of the realm.
//
// # Why this quote is trustworthy where a reaper's is not
//
// A reaper advertises what deleting entries will refund, and to do that it has
// to guess how much state an entry occupies from its payload length. That
// guess is bad: a per-entry floor dominates at the small end, and one realm
// under-advertised by 25x on chain because of it.
//
// Compaction has no such problem. What it frees is a COUNT of dead nodes, and
// the container already reports that count exactly. Every node costs the same
// whatever it carried. So the number on this page is a measured constant times
// an exact integer, not a ratio applied to a guess, which is why this is the
// half of the mechanism worth showing first.
package compact

import (
	"strings"

	"chain/runtime"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/ulist/v1"
	"gno.land/p/moul/x/storagecost/v1"
	"gno.land/p/nt/ufmt/v0"
)

// gasWantedCompact is the gas ceiling a compacting transaction is assumed to
// ask for, used only to price the advertised bounty. A caller compacting an
// unusually large number of nodes should re-price with
// storagecost.EvaluateAtFloor directly rather than trust this.
const gasWantedCompact int64 = 5_000_000

// maxText caps an entry so one caller cannot lock an unbounded deposit in a
// single call. Small on purpose: this realm is about the NODES, and a fat
// payload would only hide the thing it exists to show.
const maxText = 256

// Entry is one element. Author is kept so a drop can be refused to anyone
// else: soft-deleting a stranger's entry would be vandalism, and the holes
// this realm studies should come from ordinary use.
type Entry struct {
	Text   string
	Author address
	Added  int64 // block height
}

var entries = ulist.New()

// Add appends an entry and locks its storage deposit against the caller.
func Add(cur realm, text string) int {
	if text == "" {
		panic("compact: empty entry")
	}
	if len(text) > maxText {
		panic(ufmt.Sprintf("compact: entry too long, %d bytes against a %d cap", len(text), maxText))
	}
	entries.Append(&Entry{
		Text:   text,
		Author: cur.Previous().Address(),
		Added:  runtime.ChainHeight(),
	})
	return entries.TotalSize() - 1
}

// Drop soft-deletes your own entry, which is what creates a hole.
//
// It frees nothing on its own, and that is the point of the realm: the bytes
// stay locked until somebody compacts. Only the author may drop, so the
// fragmentation on this page is the honest kind that ordinary use produces.
func Drop(cur realm, index int) {
	e, ok := entryAt(index)
	if !ok {
		panic(ufmt.Sprintf("compact: no live entry at %d", index))
	}
	if e.Author != cur.Previous().Address() {
		panic("compact: only the author may drop an entry")
	}
	entries.MustDelete(index)
}

// Compact frees the dead tree nodes and returns how many it freed.
//
// Permissionless by design, and the refund goes to whoever signs this
// transaction rather than to the realm or to the authors: the chain pays the
// signer directly, so there is nothing here to distribute and nothing to
// steal. The worst a caller can do is waste their own gas compacting a board
// that had no holes.
func Compact(cur realm) int {
	return entries.Compact()
}

// Fragmentation reports live elements against allocated indices.
//
// The gap between them is what a compaction has to work with. It is a free
// read so a bot can poll it and decide for itself, which is the whole design:
// the realm publishes, the caller times.
func Fragmentation() (live, allocated int) {
	return entries.Size(), entries.TotalSize()
}

// Reclaimable is how many dead nodes a Compact would free right now.
//
// It is NOT the same as allocated minus live. A dead element only becomes a
// reclaimable node once every element under it is also dead, so a board with
// many scattered holes can report a large gap and nothing to reclaim. That
// difference is exactly what makes the timing a decision instead of a rule.
func Reclaimable() int { return entries.Compactable() }

// Quote prices what a Compact would return, at the default storage price and
// the floor gas price.
//
// Unlike a payload-derived bounty this is a counted quantity: Reclaimable is
// exact, and storagecost.EstimateNodes multiplies it by a measured per-node
// constant. Treat it as an advertisement all the same. The authoritative
// numbers are the chain's, in the StorageUnlockEvent the transaction emits.
func Quote() storagecost.Quote {
	return storagecost.EvaluateAtFloor(
		storagecost.EstimateNodes(int64(Reclaimable())), gasWantedCompact)
}

// entryAt reads index i, reporting whether a live entry is there.
func entryAt(i int) (*Entry, bool) {
	v := entries.Get(i)
	if v == nil {
		return nil, false
	}
	e, ok := v.(*Entry)
	return e, ok
}

func Render(path string) string {
	var b strings.Builder

	b.WriteString(md.H1("Compact"))
	b.WriteString("\nSoft-deleting an entry frees nothing: the tree node stays, the bytes stay locked, and every read still walks past the hole. Compacting drops those nodes and the chain refunds their deposit **to whoever signs the transaction**. The only question is when.\n\n")

	live, allocated := Fragmentation()
	dead := Reclaimable()
	q := Quote()

	b.WriteString(md.H2("The two integers"))
	b.WriteString("\n")
	b.WriteString(md.BulletList([]string{
		ufmt.Sprintf("**%d live** of **%d allocated** indices%s", live, allocated, ratioSuffix(live, allocated)),
		ufmt.Sprintf("**%d reclaimable nodes**, about %d bytes of state", dead, q.Bytes),
		ufmt.Sprintf("refunds roughly **%s** to whoever compacts", storagecost.FormatGNOT(q.Refund)),
		ufmt.Sprintf("against **%s** of gas at the floor price, break-even at %d bytes", storagecost.FormatGNOT(q.Fee), q.BreakEven),
		ufmt.Sprintf("verdict: **%s**", verdict(q, dead)),
	}))
	b.WriteString("\n")

	if dead > 0 {
		b.WriteString(ui.Action("Compact it", "Compact") + "\n\n")
	}

	b.WriteString(md.H2("Why allocated minus live is not the answer"))
	b.WriteString(ufmt.Sprintf("\nThis board has **%d** unused indices and **%d** reclaimable nodes. A dead element only becomes a reclaimable node once everything under it is dead too, so scattered holes free nothing while a dead tail frees a lot. That is why nobody can write down a rule for when to compact, and why the realm publishes the numbers instead of a schedule.\n\n", allocated-live, dead))

	b.WriteString(md.H2("Board"))
	b.WriteString("\n")
	if live == 0 {
		b.WriteString("Empty. " + ui.Action("Add the first entry", "Add", "text", "hello") + "\n\n")
	} else {
		rows := []string{}
		for i := 0; i < allocated; i++ {
			e, ok := entryAt(i)
			if !ok {
				continue
			}
			rows = append(rows, ufmt.Sprintf("`#%d` %s | by %s at height %d",
				i, ui.Excerpt(strings.ReplaceAll(e.Text, "|", " "), 48), ui.Addr(e.Author), e.Added))
		}
		b.WriteString(md.BulletList(rows))
		b.WriteString("\n")
	}

	b.WriteString(md.HorizontalRule())
	b.WriteString("\nThe arithmetic is [p/moul/x/storagecost](/p/moul/x/storagecost/v1); the container is [p/moul/ulist](/p/moul/ulist/v1), whose `Compact` drops dead nodes without moving a live index. The byte figure is an exact node count times a measured per-node constant, which is why it is sounder than a payload-derived bounty, but it is still an estimate: the chain's `StorageUnlockEvent` is the settlement.\n")

	return b.String()
}

// ratioSuffix adds the fragmentation percentage, and says nothing at all when
// the board is empty rather than dividing by zero.
func ratioSuffix(live, allocated int) string {
	if allocated <= 0 || live == allocated {
		return ""
	}
	return ufmt.Sprintf(", %d%% of indices are holes", (allocated-live)*100/allocated)
}

func verdict(q storagecost.Quote, dead int) string {
	if dead == 0 {
		return "nothing to reclaim, compacting would only burn gas"
	}
	if q.Worth() {
		return "worth " + storagecost.FormatGNOT(q.Net)
	}
	return "not worth the gas yet"
}
