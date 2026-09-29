package art

import "strings"

// Default is the colour that means "let the consumer decide": the terminal's
// own foreground or background in ANSI, and transparent in SVG.
const Default = -1

// RGB packs three 0-255 components into the 0xRRGGBB form this package uses.
// Components outside 0-255 are clamped rather than wrapped, so a computed
// channel cannot silently alias onto a neighbouring one.
func RGB(r, g, b int) int {
	return clamp8(r)<<16 | clamp8(g)<<8 | clamp8(b)
}

// Split returns the three 0-255 components of a packed colour. Default splits
// to zeroes, so callers must test for Default before calling it rather than
// after.
func Split(c int) (r, g, b int) {
	if c < 0 {
		return 0, 0, 0
	}
	return (c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff
}

// ParseHex reads "#rrggbb", "#rgb", or either without the leading '#', and
// reports whether it understood the string. An empty string is not an error but
// it is not a colour either: it reports Default, false, which is how a palette
// marks a transparent entry.
func ParseHex(s string) (int, bool) {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "#")
	switch len(s) {
	case 3:
		r, ok1 := hexDigit(s[0])
		g, ok2 := hexDigit(s[1])
		b, ok3 := hexDigit(s[2])
		if !ok1 || !ok2 || !ok3 {
			return Default, false
		}
		// #abc is #aabbcc, not #0a0b0c.
		return RGB(r*17, g*17, b*17), true
	case 6:
		r, ok1 := hexByte(s[0], s[1])
		g, ok2 := hexByte(s[2], s[3])
		b, ok3 := hexByte(s[4], s[5])
		if !ok1 || !ok2 || !ok3 {
			return Default, false
		}
		return RGB(r, g, b), true
	}
	return Default, false
}

// Hex is the inverse of ParseHex. Default renders as the empty string, because
// there is no hex spelling of "the consumer's default".
func Hex(c int) string {
	if c < 0 {
		return ""
	}
	r, g, b := Split(c)
	var sb strings.Builder
	sb.WriteByte('#')
	writeHexByte(&sb, r)
	writeHexByte(&sb, g)
	writeHexByte(&sb, b)
	return sb.String()
}

// Luminance returns perceived brightness on 0-255, using the Rec. 709 weights
// (0.2126 R, 0.7152 G, 0.0722 B) in integer arithmetic. Default is treated as
// black, so an unset colour ramps to the darkest glyph rather than to a
// midpoint that would read as real content.
//
// This is the function [Ramp] keys on, and the package doc explains why keying
// on it is the wrong default for a sprite.
func Luminance(c int) int {
	if c < 0 {
		return 0
	}
	r, g, b := Split(c)
	return (2126*r + 7152*g + 722*b) / 10000
}

func clamp8(v int) int {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return v
}

func hexDigit(c byte) (int, bool) {
	switch {
	case c >= '0' && c <= '9':
		return int(c - '0'), true
	case c >= 'a' && c <= 'f':
		return int(c-'a') + 10, true
	case c >= 'A' && c <= 'F':
		return int(c-'A') + 10, true
	}
	return 0, false
}

func hexByte(hi, lo byte) (int, bool) {
	h, ok1 := hexDigit(hi)
	l, ok2 := hexDigit(lo)
	if !ok1 || !ok2 {
		return 0, false
	}
	return h*16 + l, true
}

const hexDigits = "0123456789abcdef"

func writeHexByte(sb *strings.Builder, v int) {
	sb.WriteByte(hexDigits[(v>>4)&0xf])
	sb.WriteByte(hexDigits[v&0xf])
}
