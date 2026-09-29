package art

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestParseHex(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want int
		ok   bool
	}{
		{"six with hash", "#e8c39e", 0xe8c39e, true},
		{"six without hash", "e8c39e", 0xe8c39e, true},
		{"uppercase", "#E8C39E", 0xe8c39e, true},
		{"short expands by duplication", "#abc", 0xaabbcc, true},
		{"short is not zero padded", "#abc", 0x0a0b0c, false},
		{"surrounding space", "  #000000 ", 0x000000, true},
		{"white", "#ffffff", 0xffffff, true},
		{"empty is not a colour", "", Default, false},
		{"four digits", "#abcd", Default, false},
		{"non hex digit", "#gggggg", Default, false},
	}
	for _, tc := range cases {
		got, ok := ParseHex(tc.in)
		if !tc.ok {
			// Either it failed to parse, or it parsed to something other than
			// the value this case says it must not produce.
			uassert.False(t, ok && got == tc.want, tc.name)
			continue
		}
		uassert.True(t, ok, tc.name+": parsed")
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

func TestHexRoundTrip(t *testing.T) {
	for _, s := range []string{"#000000", "#ffffff", "#e8c39e", "#0a0b0c"} {
		c, ok := ParseHex(s)
		uassert.True(t, ok, s)
		uassert.Equal(t, s, Hex(c), s)
	}
	uassert.Equal(t, "", Hex(Default), "Default has no hex spelling")
}

func TestRGBClamps(t *testing.T) {
	uassert.Equal(t, 0xffffff, RGB(300, 300, 300), "over range clamps to ff")
	uassert.Equal(t, 0x000000, RGB(-5, -5, -5), "under range clamps to 00")
	// The point of clamping rather than masking: 256 must not alias to 0 and
	// carry a bit into the next channel.
	uassert.Equal(t, 0x00ff00, RGB(0, 256, 0), "256 does not carry into red")
}

func TestLuminance(t *testing.T) {
	cases := []struct {
		name string
		in   int
		want int
	}{
		{"black", 0x000000, 0},
		{"white", 0xffffff, 255},
		{"pure green is the brightest primary", 0x00ff00, 182},
		{"pure blue is the darkest primary", 0x0000ff, 18},
		{"pure red", 0xff0000, 54},
		{"Default reads as black", Default, 0},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, Luminance(tc.in), tc.name)
	}
}
