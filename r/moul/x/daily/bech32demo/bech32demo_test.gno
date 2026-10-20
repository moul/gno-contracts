package bech32demo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The argument path decodes a string of the caller's choosing.
func TestRenderArgument(t *testing.T) {
	got := Render("/a1lqfn3a")
	uassert.True(t, strings.Contains(got, "| variant | bech32m |"), got)
	uassert.True(t, strings.Contains(got, "| payload | 0 bytes |"))
	// The full demo's sections are not rendered for an argument.
	uassert.False(t, strings.Contains(got, "## Why Bech32m exists"))
}

// A string that does not decode says why, instead of rendering half a table.
func TestRenderRejects(t *testing.T) {
	got := Render("/g1manfred47kzduec920z88wfr64ylksmdcedlf4")
	uassert.True(t, strings.Contains(got, "bech32: bad checksum"), got)
	uassert.False(t, strings.Contains(got, "| field | value |"))
}

// A caller controls the whole argument, so anything echoed back is escaped.
// Without it, "|" opens a column and "[x](y)" renders as a link.
func TestRenderEscapesArgument(t *testing.T) {
	got := Render("/*boom*")
	uassert.False(t, strings.Contains(got, "Decoding *boom*"))
	uassert.True(t, strings.Contains(got, "Decoding \\*boom\\*"), got)
}

// A slash is legal in a human-readable part, so the argument is taken whole
// rather than cut at the first one.
func TestRenderSlashInHRP(t *testing.T) {
	got := Render("/a/b1mqd7sj")
	uassert.True(t, strings.Contains(got, "human-readable part | a/b |"), got)
}

// Nothing is trimmed. A trailing non-breaking space is part of the string the
// caller submitted, and the library refuses it: trimming it first would render
// a clean decode of a string nobody typed.
func TestRenderDoesNotTrim(t *testing.T) {
	got := Render("/g1manfred47kzduec920z88wfr64ylksmdcedlf5 ")
	uassert.True(t, strings.Contains(got, "bech32: invalid data character"), got)
	uassert.False(t, strings.Contains(got, "20 bytes"))
}
