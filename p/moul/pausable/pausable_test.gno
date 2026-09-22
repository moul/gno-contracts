package pausable

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestParse(t *testing.T) {
	tests := []struct {
		raw        string
		wantLevel  Level
		wantReason string
		wantOK     bool
	}{
		{"", Running, "", true},
		{"   ", Running, "", true},
		{"running", Running, "", true},
		{"readonly", ReadOnly, "", true},
		{"paused", Paused, "", true},
		{"Paused", Paused, "", true},   // case-insensitive
		{"  paused  ", Paused, "", true},
		{"paused: migrating storage", Paused, "migrating storage", true},
		{"readonly:  spaced  ", ReadOnly, "spaced", true},
		{"running: nothing wrong", Running, "nothing wrong", true},
		// A reason containing the separator keeps everything after the first
		// one, so a URL or a time survives.
		{"paused: back at 14:00 UTC", Paused, "back at 14:00 UTC", true},
		// Not recognised. These are exactly the values that must NOT read as
		// Running.
		{"yes", Running, "", false},
		{"true", Running, "", false},
		{"1", Running, "", false},
		{"stop", Running, "", false},
		{"read-only", Running, "", false},
	}
	for _, tt := range tests {
		got, ok := Parse(tt.raw)
		uassert.Equal(t, tt.wantOK, ok, "Parse("+tt.raw+") ok")
		if !ok {
			continue
		}
		uassert.Equal(t, int(tt.wantLevel), int(got.Level), "Parse("+tt.raw+") level")
		uassert.Equal(t, tt.wantReason, got.Reason, "Parse("+tt.raw+") reason")
	}
}

// TestMustParseFailsClosed is the whole safety argument of this package. Every
// value here is something a person might plausibly type, and every one of them
// has to stop the realm rather than quietly leave it running.
func TestMustParseFailsClosed(t *testing.T) {
	for _, raw := range []string{"yes", "true", "1", "on", "stop", "PAUSE", "pasued"} {
		got := MustParse(raw)
		uassert.Equal(t, int(Paused), int(got.Level), "MustParse("+raw+") must fail closed")
		uassert.False(t, got.AllowsWrite(), "MustParse("+raw+") must refuse writes")
		uassert.True(t, len(got.Reason) > 0, "MustParse("+raw+") must say why")
	}

	// And the values it does understand are untouched.
	uassert.Equal(t, int(Running), int(MustParse("").Level))
	uassert.Equal(t, int(ReadOnly), int(MustParse("readonly").Level))
}

func TestAllows(t *testing.T) {
	tests := []struct {
		level     Level
		read      bool
		write     bool
		isPaused  bool
	}{
		{Running, true, true, false},
		{ReadOnly, true, false, true},
		{Paused, false, false, true},
	}
	for _, tt := range tests {
		s := State{Level: tt.level}
		uassert.Equal(t, tt.read, s.AllowsRead(), tt.level.String()+" read")
		uassert.Equal(t, tt.write, s.AllowsWrite(), tt.level.String()+" write")
		uassert.Equal(t, tt.isPaused, s.IsPaused(), tt.level.String()+" isPaused")
	}
}

func TestStrictest(t *testing.T) {
	run := State{Level: Running}
	ro := State{Level: ReadOnly, Reason: "scoped"}
	paused := State{Level: Paused, Reason: "global"}

	uassert.Equal(t, int(ReadOnly), int(Strictest(run, ro).Level))
	uassert.Equal(t, int(ReadOnly), int(Strictest(ro, run).Level))
	uassert.Equal(t, int(Paused), int(Strictest(paused, ro).Level))
	uassert.Equal(t, int(Paused), int(Strictest(ro, paused).Level))

	// A stale per-realm entry can never re-open a realm during a global halt.
	// This is the property the whole precedence rule exists for.
	uassert.Equal(t, int(Paused), int(Strictest(paused, run).Level),
		"a per-realm 'running' cannot defeat a global pause")

	// The reason travels with the level that won.
	uassert.Equal(t, "global", Strictest(paused, ro).Reason)
	uassert.Equal(t, "scoped", Strictest(run, ro).Reason)

	// On a tie the first argument wins, so a caller passing (global, scoped)
	// keeps the global explanation.
	a := State{Level: Paused, Reason: "first"}
	b := State{Level: Paused, Reason: "second"}
	uassert.Equal(t, "first", Strictest(a, b).Reason)
}

func TestStringRoundTrips(t *testing.T) {
	for _, raw := range []string{"", "readonly", "paused", "paused: migrating storage"} {
		s, ok := Parse(raw)
		uassert.True(t, ok, "Parse("+raw+")")
		again, ok := Parse(s.String())
		uassert.True(t, ok, "Parse(String()) for "+raw)
		uassert.Equal(t, int(s.Level), int(again.Level), "level round-trip for "+raw)
		uassert.Equal(t, s.Reason, again.Reason, "reason round-trip for "+raw)
	}

	// The zero State renders empty, so an unset setting stays unset rather
	// than being written back as the word "running".
	uassert.Equal(t, "", State{}.String())
	uassert.Equal(t, "running: why", State{Reason: "why"}.String())
}

func TestAsserts(cur realm, t *testing.T) {
	State{}.AssertWritable()
	State{}.AssertReadable()
	State{Level: ReadOnly}.AssertReadable()

	uassert.PanicsWithMessage(t, cur, "writes are paused", func() {
		State{Level: ReadOnly}.AssertWritable()
	})
	uassert.PanicsWithMessage(t, cur, "writes are paused: migrating", func() {
		State{Level: Paused, Reason: "migrating"}.AssertWritable()
	})
	uassert.PanicsWithMessage(t, cur, "paused: migrating", func() {
		State{Level: Paused, Reason: "migrating"}.AssertReadable()
	})
}

func TestNotice(t *testing.T) {
	uassert.Equal(t, "", State{}.Notice(), "a running realm shows no banner")

	uassert.Equal(t,
		"> **Read-only.** This realm is still readable, but not accepting changes.",
		State{Level: ReadOnly}.Notice())

	uassert.Equal(t,
		"> **Paused.** This realm is not accepting anything right now. back in an hour",
		State{Level: Paused, Reason: "back in an hour"}.Notice())
}

// TestNoticeStaysOneBlock covers the reason a manager typed. It lands inside a
// markdown blockquote, where a newline ends the quote and lets the rest render
// as ordinary page content, so it is folded to one line.
func TestNoticeStaysOneBlock(t *testing.T) {
	s := State{Level: Paused, Reason: "line one\n\nline two\n# not a heading"}
	uassert.Equal(t,
		"> **Paused.** This realm is not accepting anything right now. line one line two # not a heading",
		s.Notice())
}
