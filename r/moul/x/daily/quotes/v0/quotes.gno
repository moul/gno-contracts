// Package quotes is a community "Quote of the Moment" board realm.
//
// Anyone can submit a quote via the exported crossing function AddQuote.
// Each quote records its text, the address of the caller who added it, and
// the block height at submission time. Render deterministically picks a
// "featured" quote by the current block height (a stable index into the
// list), shows it as a blockquote, then lists every quote with its author
// and id below.
package quotes

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"
)

// quote is a single board entry. Author is stored as a plain string address
// (realm values are ephemeral and must never be persisted).
type quote struct {
	id     int
	text   string
	author string // bech32 address of the submitter, or "" for seeded quotes
	height int64  // block height at submission (0 for seeded quotes)
}

// board is the persistent realm state. A plain slice is fine here: the list
// only ever grows by append and Render walks it in insertion order, which is
// deterministic.
var board []quote

// init seeds the board so a fresh deploy renders nicely.
func init() {
	seed := []string{
		"The unexamined life is not worth living.",
		"We suffer more often in imagination than in reality.",
		"Waste no more time arguing about what a good person should be. Be one.",
		"He who is brave is free.",
	}
	for _, s := range seed {
		board = append(board, quote{
			id:     len(board),
			text:   s,
			author: "", // seeded
			height: 0,
		})
	}
}

// AddQuote is the exported, state-mutating entry point. It follows the gno 0.9
// interrealm crossing convention: the first parameter is `cur realm`. Callers
// invoke it as AddQuote(cross(cur), "...") over a MsgCall.
func AddQuote(cur realm, text string) {
	// Authentication primitive: reject a stale/forged realm value before
	// deriving any caller identity from it.
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}

	if err := validate(text); err != nil {
		panic(err)
	}

	author := cur.Previous().Address().String()
	h := runtime.ChainHeight()

	board = append(board, quote{
		id:     len(board),
		text:   text,
		author: author,
		height: h,
	})

	chain.Emit("QuoteAdded",
		"id", strconv.Itoa(len(board)-1),
		"author", author,
		"height", strconv.FormatInt(h, 10),
	)
}

// maxQuoteLen caps quote length to keep storage costs bounded and Render tidy.
const maxQuoteLen = 280

// validate enforces basic content rules. Returns an error describing the
// problem, or nil when the text is acceptable.
func validate(text string) error {
	if len(text) == 0 {
		return errEmpty
	}
	if len(text) > maxQuoteLen {
		return errTooLong
	}
	return nil
}

// Sentinel errors for validation. Kept as package-level vars so tests can
// compare against them directly.
var (
	errEmpty   = quoteError("quote text must not be empty")
	errTooLong = quoteError("quote text exceeds " + strconv.Itoa(maxQuoteLen) + " characters")
)

// quoteError is a trivial string-backed error type (the VM has no host
// stdlib errors package convenience beyond this).
type quoteError string

func (e quoteError) Error() string { return string(e) }

// featuredIndex deterministically picks which quote is "of the moment" for a
// given block height. Pure function of (height, count) so it is fully
// deterministic and easy to test.
func featuredIndex(height int64, count int) int {
	if count <= 0 {
		return -1
	}
	// Guard against a negative height (should not happen on-chain, but keeps
	// the modulo well-defined).
	if height < 0 {
		height = -height
	}
	return int(height % int64(count))
}

// Render produces the Markdown page shown in gnoweb. It is NOT a crossing
// function (no `cur realm` parameter) — it is a read-only view.
func Render(path string) string {
	count := len(board)
	if count == 0 {
		return "# Quote of the Moment\n\n_No quotes yet. Be the first to add one._\n"
	}

	h := runtime.ChainHeight()
	idx := featuredIndex(h, count)
	featured := board[idx]

	var b strings.Builder
	b.WriteString("# Quote of the Moment\n\n")

	// Featured quote as a blockquote.
	b.WriteString("> ")
	b.WriteString(featured.text)
	b.WriteString("\n>\n> — ")
	b.WriteString(authorLabel(featured))
	b.WriteString(" (#")
	b.WriteString(strconv.Itoa(featured.id))
	b.WriteString(")\n\n")

	b.WriteString("_Featured pick rotates with block height ")
	b.WriteString(strconv.FormatInt(h, 10))
	b.WriteString(" — index ")
	b.WriteString(strconv.Itoa(idx))
	b.WriteString(" of ")
	b.WriteString(strconv.Itoa(count))
	b.WriteString("._\n\n")

	// Full list.
	b.WriteString("## All quotes (")
	b.WriteString(strconv.Itoa(count))
	b.WriteString(")\n\n")
	for _, q := range board {
		b.WriteString("- **#")
		b.WriteString(strconv.Itoa(q.id))
		b.WriteString("** ")
		b.WriteString(q.text)
		b.WriteString(" — _")
		b.WriteString(authorLabel(q))
		b.WriteString("_\n")
	}

	return b.String()
}

// authorLabel renders a human-friendly author string. Seeded quotes (empty
// author) show as the house account.
func authorLabel(q quote) string {
	if q.author == "" {
		return "the board"
	}
	return q.author
}
