// Package reaper is a noticeboard whose garbage is a standing bounty.
//
// Anyone can post a note with an expiry. Posting locks a storage deposit, paid
// by the poster. Once a note expires, anyone at all can delete it, and the
// chain refunds that deposit to whoever signed the deleting transaction. So
// the poster pays to occupy space and a stranger is paid to reclaim it.
//
// Nothing here is a token, a reward pool or an emission schedule. The incentive
// is the chain's own storage accounting, which already works this way for every
// realm on gno.land; this realm only makes it legible. Reap and Compact are
// permissionless because the expiry predicate is checked on chain, so the
// worst a malicious reaper can do is waste their own gas.
//
// Two collaborators own the parts this realm does not:
//
//   - gno.land/p/moul/ulist/v1 stores the notes and owns compaction. Its
//     Delete is a soft delete that leaves a dead tree node behind, and its
//     Compact frees those nodes without moving any live index.
//   - gno.land/p/moul/x/storagecost/v0 owns the arithmetic: what a byte
//     refunds, and how many bytes a transaction must free to pay for itself.
//   - gno.land/p/moul/kit/ui/v0 owns display: the escaping, the length cap
//     and the address format. A note body is arbitrary bytes chosen by
//     whoever paid to post it and is rendered back to every reader, so it is
//     attacker-controlled input in a markdown slot. Render never emits a body
//     unescaped; ui.Excerpt is what makes that true, and it delegates to
//     p/nt/markdown/sanitize.
//
// The realm deliberately cannot see its own byte count. No stdlib call exposes
// a realm's locked storage, so every figure Render shows is an estimate from
// payload length. The authoritative numbers are the chain's, in the
// StorageDepositEvent and StorageUnlockEvent each transaction emits.
package reaper

import (
	"strings"

	"chain/runtime"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/ulist/v1"
	"gno.land/p/moul/x/storagecost/v0"
	"gno.land/p/nt/ufmt/v0"
)

// gasWantedReap is the gas ceiling a reaping transaction is assumed to ask
// for, used only to price the advertised bounty. It is the measured cost of a
// ten-note reap rounded up; a caller reaping more notes should re-price with
// storagecost.EvaluateAtFloor directly rather than trust this.
const gasWantedReap int64 = 5_000_000

// maxBody caps a note so one poster cannot lock an unbounded deposit in a
// single call, which would also make the gas cost of reaping it unpredictable.
const maxBody = 4096

// Note is one posting. Body is what costs storage; the rest is bookkeeping
// that makes the incentive visible in Render.
type Note struct {
	Body    string
	Author  address
	Posted  int64 // block height
	Expires int64 // block height; reapable once ChainHeight passes it
}

// notes is append-addressed: an index is stable for the life of the realm,
// which is what lets Compact reclaim dead nodes without renumbering.
var notes = ulist.New()

// Post adds a note that becomes reapable ttl blocks from now, and locks the
// storage deposit for it against the caller.
//
// A ttl of zero is allowed and makes the note reapable immediately, which is
// the cheapest way to demonstrate the mechanism.
func Post(cur realm, body string, ttl int64) int {
	if body == "" {
		panic("reaper: empty note")
	}
	if len(body) > maxBody {
		panic(ufmt.Sprintf("reaper: note too long, %d bytes against a %d cap", len(body), maxBody))
	}
	if ttl < 0 {
		panic("reaper: negative ttl")
	}
	height := runtime.ChainHeight()
	notes.Append(&Note{
		Body:    body,
		Author:  cur.Previous().Address(),
		Posted:  height,
		Expires: height + ttl,
	})
	return notes.TotalSize() - 1
}

// Reap deletes up to limit expired notes and returns how many it deleted.
//
// Permissionless by design. The storage deposit freed goes to whoever signed
// this transaction, so a stranger keeping the board tidy is paid for it out of
// the deposits the posters locked. A note that has not expired is skipped, not
// refused, so a reaper never has to guess which indices are ripe.
//
// It walks from the highest index down, which is not cosmetic. In the backing
// list the oldest indices are the ancestors of the newest, so a node can only
// be freed once everything below it is dead. Reaping oldest-first with a
// binding limit therefore never creates a dead tail and leaves Compactable at
// zero, stranding the tree structure, which measures at roughly two thirds of
// what an entry costs. Reaping newest-first makes each batch immediately
// compactable. Every candidate is expired either way, so the order changes
// only who gets paid how much, and it is measured: see the ulist package doc.
func Reap(cur realm, limit int) int {
	if limit <= 0 {
		panic("reaper: limit must be positive")
	}
	height := runtime.ChainHeight()
	reaped := 0
	for i := notes.TotalSize() - 1; i >= 0 && reaped < limit; i-- {
		n, ok := noteAt(i)
		if !ok || n.Expires > height {
			continue
		}
		notes.MustDelete(i)
		reaped++
	}
	return reaped
}

// Compact frees the tree nodes that reaping left behind and returns how many.
//
// Also permissionless, and also paid the same way. It is a separate call
// because it is a separate economic decision, and a surprisingly large one: on
// chain, compacting a drained board returned about three times what deleting
// the notes themselves did, because a list node costs more than the note it
// carries. But it returns nothing at all while any live note sits below the
// dead ones, so the two calls are worth batching in that order: reap, then
// compact. Compactable says how much is actually there, for free.
func Compact(cur realm) int {
	return notes.Compact()
}

// Reapable counts the notes that have expired and not yet been reaped.
func Reapable() int {
	height := runtime.ChainHeight()
	count := 0
	total := notes.TotalSize()
	for i := 0; i < total; i++ {
		n, ok := noteAt(i)
		if ok && n.Expires <= height {
			count++
		}
	}
	return count
}

// Compactable reports how many dead tree nodes a Compact would free.
func Compactable() int { return notes.Compactable() }

// Live counts the notes still holding storage.
func Live() int { return notes.Size() }

// Bounty prices what is currently on the table for a reaper, at the default
// storage price and the floor gas price.
//
// The byte figure is an estimate from payload length, never the chain's own
// accounting. Treat it as an advertisement, not a settlement.
func Bounty() storagecost.Quote {
	height := runtime.ChainHeight()
	var payload int64
	total := notes.TotalSize()
	for i := 0; i < total; i++ {
		n, ok := noteAt(i)
		if ok && n.Expires <= height {
			payload += int64(len(n.Body))
		}
	}
	return storagecost.EvaluateAtFloor(storagecost.EstimateBytes(payload), gasWantedReap)
}

// noteAt reads index i, reporting whether a live note is there. A reaped or
// compacted index reads as absent.
func noteAt(i int) (*Note, bool) {
	v := notes.Get(i)
	if v == nil {
		return nil, false
	}
	n, ok := v.(*Note)
	return n, ok
}

func Render(path string) string {
	var b strings.Builder

	b.WriteString(md.H1("Reaper"))
	b.WriteString("\nA noticeboard whose garbage is a standing bounty. Posting a note locks a storage deposit. Once the note expires, anyone can delete it and the chain refunds that deposit **to whoever signs the deleting transaction**.\n\n")

	quote := Bounty()
	b.WriteString(md.H2("On the table right now"))
	b.WriteString("\n")

	reapable := Reapable()
	if reapable == 0 {
		b.WriteString("Nothing has expired. Every note here is still paid for.\n\n")
	} else {
		b.WriteString(md.BulletList([]string{
			ufmt.Sprintf("**%d expired notes**, about %d bytes of state", reapable, quote.Bytes),
			ufmt.Sprintf("refunds roughly **%s** to the reaper", storagecost.FormatGNOT(quote.Refund)),
			ufmt.Sprintf("against **%s** of gas at the floor price, break-even at %d bytes", storagecost.FormatGNOT(quote.Fee), quote.BreakEven),
			ufmt.Sprintf("verdict: **%s**", verdictWord(quote)),
		}))
		b.WriteString("\n")
		b.WriteString(ui.Action("Reap them", "Reap", "limit", "100") + "\n\n")
	}

	if dead := Compactable(); dead > 0 {
		b.WriteString(md.H2("Compaction available"))
		b.WriteString(ufmt.Sprintf("\n%d dead tree nodes are reclaimable. Compacting frees fewer bytes per unit of gas than reaping does, so it is worth doing in batches.\n\n%s\n\n",
			dead, ui.Action("Compact", "Compact")))
	}

	b.WriteString(md.H2("Board"))
	b.WriteString("\n")
	if notes.Size() == 0 {
		b.WriteString("Empty. " + ui.Action("Post the first note", "Post", "body", "hello", "ttl", "0") + "\n\n")
	} else {
		height := runtime.ChainHeight()
		rows := []string{}
		total := notes.TotalSize()
		for i := 0; i < total; i++ {
			n, ok := noteAt(i)
			if !ok {
				continue
			}
			state := ufmt.Sprintf("expires at %d", n.Expires)
			if n.Expires <= height {
				state = "**reapable**"
			}
			rows = append(rows, ufmt.Sprintf("`#%d` %s | %d bytes by %s, %s",
				i, summarize(n.Body), len(n.Body), ui.Addr(n.Author), state))
		}
		b.WriteString(md.BulletList(rows))
		b.WriteString("\n")
	}

	b.WriteString(md.HorizontalRule())
	b.WriteString("\nThe arithmetic is [p/moul/x/storagecost](/p/moul/x/storagecost/v0); the storage is [p/moul/ulist](/p/moul/ulist/v1), whose `Compact` reclaims dead nodes without moving a live index. Byte figures on this page are estimates from payload length: no stdlib call exposes a realm's real locked storage.\n")

	return b.String()
}

func verdictWord(q storagecost.Quote) string {
	if q.Worth() {
		return "worth " + storagecost.FormatGNOT(q.Net)
	}
	return "not worth the gas yet"
}

// summarize is the board's one-line view of a note.
//
// A body is whatever bytes a poster paid to store, so on the board it is
// attacker-controlled input in an inline markdown slot. ui.Excerpt owns both
// halves of that: the rune-boundary cut and the escaping, in the order that is
// safe. This realm shipped a hand-rolled version that did neither, and the
// replacement for it is one call.
func summarize(body string) string {
	const width = 48
	// Cosmetic, not a defense: "|" is the column separator of the row this
	// lands in. The escaper deliberately leaves pipes literal, which is right,
	// since a lone pipe cannot open a GFM table with no delimiter row.
	return ui.Excerpt(strings.ReplaceAll(body, "|", " "), width)
}
