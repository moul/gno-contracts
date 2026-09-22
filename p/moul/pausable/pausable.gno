// Package pausable is the switch a realm checks before it acts: a parsed pause
// state, the rule for combining two of them, and the asserts that stop a call.
//
// # Three levels, because "paused" is usually too blunt
//
// Taking a realm fully offline hides the thing people came to read. Most
// incidents only need the writes stopped: a board keeps rendering, an exchange
// keeps quoting, and nothing new lands while the fix is prepared. So the
// levels are Running, ReadOnly and Paused, and a realm normally guards its
// mutating functions with AssertWritable and leaves Render alone.
//
//	func Post(cur realm, body string) {
//		config.AssertWritable()  // aborts while the realm is ReadOnly or Paused
//		…
//	}
//
//	func Render(path string) string {
//		return config.TopBlock() + body  // the banner explains itself
//	}
//
// # It fails closed
//
// MustParse turns a value it does not recognise into Paused, not Running. A
// pause switch that a typo silently disables is not a pause switch, and the
// failure is loud and one transaction from fixed, where the opposite failure
// is silent and discovered during the incident it was meant to cover.
//
// The cost of that choice is a typo taking a realm offline, so the writer is
// expected to validate: Parse reports ok=false and the storing realm refuses
// the write. Validate on the way in, fail closed on the way out.
//
// # The stricter of two states wins
//
// A global pause and a per-realm pause combine with Strictest, so a stale
// per-realm entry can never re-open a realm during a global halt. The cost is
// that exempting one realm from a global pause is not expressible; clear the
// global and set the others instead.
package pausable

import "strings"

// Level is how much of a realm is still allowed to work.
type Level int

const (
	// Running is the normal state, and what an unset value means.
	Running Level = iota
	// ReadOnly still renders and still answers queries; it refuses writes.
	ReadOnly
	// Paused refuses everything, reads included.
	Paused
)

// The canonical spelling of each level, which is what a value round-trips to.
const (
	runningWord  = "running"
	readOnlyWord = "readonly"
	pausedWord   = "paused"
)

// reasonSep separates the level from the human explanation in a stored value:
// "paused: migrating storage, back in an hour".
const reasonSep = ":"

func (l Level) String() string {
	switch l {
	case Running:
		return runningWord
	case ReadOnly:
		return readOnlyWord
	case Paused:
		return pausedWord
	default:
		// Not reachable through Parse, and not worth panicking over in a
		// Render path: an unknown level reads as the strictest one.
		return pausedWord
	}
}

// AllowsRead reports whether rendering and querying are still allowed.
func (l Level) AllowsRead() bool { return l != Paused }

// AllowsWrite reports whether state-changing calls are still allowed.
func (l Level) AllowsWrite() bool { return l == Running }

// State is a parsed pause setting: a level and an optional reason to show.
//
// The zero State is Running with no reason, which is what an unset setting
// means, so a realm that never configures anything is never paused.
type State struct {
	Level  Level
	Reason string
}

// Parse reads a stored value: "", "running", "readonly", "paused", each
// optionally followed by ": <reason>".
//
// ok is false for anything else. A caller that is STORING the value should
// refuse on !ok; a caller that is READING one should use MustParse, which
// fails closed instead.
func Parse(raw string) (State, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return State{}, true
	}

	word, reason := raw, ""
	if i := strings.Index(raw, reasonSep); i >= 0 {
		word = strings.TrimSpace(raw[:i])
		reason = strings.TrimSpace(raw[i+1:])
	}

	switch strings.ToLower(word) {
	case runningWord:
		return State{Level: Running, Reason: reason}, true
	case readOnlyWord:
		return State{Level: ReadOnly, Reason: reason}, true
	case pausedWord:
		return State{Level: Paused, Reason: reason}, true
	default:
		return State{}, false
	}
}

// MustParse is Parse for a reader, failing closed: a value it cannot read
// becomes Paused, carrying the raw text as the reason so whoever hits it can
// see what is wrong.
func MustParse(raw string) State {
	if s, ok := Parse(raw); ok {
		return s
	}
	return State{Level: Paused, Reason: "unreadable pause setting: " + strings.TrimSpace(raw)}
}

// String renders a State back into a storable value. It round-trips through
// Parse, and the zero State renders empty so an unset setting stays unset.
func (s State) String() string {
	if s.Level == Running && s.Reason == "" {
		return ""
	}
	if s.Reason == "" {
		return s.Level.String()
	}
	return s.Level.String() + reasonSep + " " + s.Reason
}

// Strictest returns whichever of the two stops more, keeping the reason that
// belongs to the level it returns. On a tie the first argument wins, so a
// caller passing (global, scoped) keeps the global explanation when both say
// the same thing, and the scoped one when it is the stricter.
func Strictest(a, b State) State {
	if b.Level > a.Level {
		return b
	}
	return a
}

// AllowsRead reports whether rendering and querying are still allowed.
func (s State) AllowsRead() bool { return s.Level.AllowsRead() }

// AllowsWrite reports whether state-changing calls are still allowed.
func (s State) AllowsWrite() bool { return s.Level.AllowsWrite() }

// IsPaused reports whether anything at all is being held back. It is true for
// ReadOnly as well as Paused, because the question a caller usually means by
// "is it paused" is "is it behaving normally".
func (s State) IsPaused() bool { return s.Level != Running }

// AssertWritable aborts unless writes are allowed. This is the one a realm
// puts at the top of every state-changing function.
func (s State) AssertWritable() {
	if !s.AllowsWrite() {
		panic(s.message("writes are paused"))
	}
}

// AssertReadable aborts unless reads are allowed. Most realms do not want this
// in Render: a page that aborts tells a reader nothing, while Notice tells
// them what happened and when to come back.
func (s State) AssertReadable() {
	if !s.AllowsRead() {
		panic(s.message("paused"))
	}
}

func (s State) message(what string) string {
	if s.Reason == "" {
		return what
	}
	return what + reasonSep + " " + s.Reason
}

// Notice is the banner a Render puts above its content, or "" while running.
//
// It is a markdown blockquote, so it reads as set apart from the page without
// needing any style the renderer might not have.
func (s State) Notice() string {
	if s.Level == Running {
		return ""
	}
	head := "**Paused.** This realm is not accepting anything right now."
	if s.Level == ReadOnly {
		head = "**Read-only.** This realm is still readable, but not accepting changes."
	}
	if s.Reason == "" {
		return "> " + head
	}
	// The reason is text a manager typed, and it lands inside a blockquote
	// where a newline would end the quote and let the rest render as page
	// content. Folding it to a single line keeps the banner one block.
	return "> " + head + " " + oneLine(s.Reason)
}

// oneLine collapses every run of whitespace, newlines included, into single
// spaces.
func oneLine(s string) string {
	var b strings.Builder
	space := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			space = true
			continue
		}
		if space && b.Len() > 0 {
			b.WriteByte(' ')
		}
		space = false
		b.WriteByte(c)
	}
	return b.String()
}
