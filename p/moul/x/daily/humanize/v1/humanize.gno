// Package humanize formats numbers for people rather than machines, as a pure,
// reusable package: byte sizes, thousands separators, ordinals, pluralisation
// and block-height "durations".
//
// Everything is integer-only. There are no floats here on purpose: gno has no
// float determinism guarantees worth relying on for consensus output, and a
// rendered value that differs between nodes would be a consensus bug. One
// decimal place is produced by scaling by 10 and taking a remainder.
//
// Durations are expressed in BLOCKS, not seconds. There is no wall clock on
// chain, so "about 2 hours" is a lie dressed as precision; this package says
// "~1200 blocks" and lets the caller decide what that means on their chain.
//
// A live demo of this package is at
// [r/moul/x/daily/humanizedemo](/r/moul/x/daily/humanizedemo/v1).
package humanize

import (
	"strconv"
	"strings"
)

// Bytes renders n bytes with SI-ish binary units and one decimal place.
// Negative input is rendered with a leading minus rather than rejected.
func Bytes(n int64) string {
	neg := n < 0
	if neg {
		n = -n
	}
	const unit = 1024
	if n < unit {
		s := strconv.FormatInt(n, 10) + " B"
		if neg {
			return "-" + s
		}
		return s
	}
	units := []string{"KiB", "MiB", "GiB", "TiB", "PiB", "EiB"}
	div := int64(unit)
	i := 0
	for n/div >= unit && i < len(units)-1 {
		div *= unit
		i++
	}
	// one decimal place without floats: scale by 10, then split
	scaled := n * 10 / div
	whole, freq := scaled/10, scaled%10
	s := strconv.FormatInt(whole, 10)
	if freq != 0 {
		s += "." + strconv.FormatInt(freq, 10)
	}
	s += " " + units[i]
	if neg {
		return "-" + s
	}
	return s
}

// Comma inserts thousands separators: 1234567 -> "1,234,567".
func Comma(n int64) string {
	neg := n < 0
	if neg {
		n = -n
	}
	s := strconv.FormatInt(n, 10)
	var b strings.Builder
	for i, c := range []byte(s) {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteByte(c)
	}
	if neg {
		return "-" + b.String()
	}
	return b.String()
}

// Ordinal renders 1 -> "1st", 2 -> "2nd", 11 -> "11th".
//
// The teens are the trap: 11/12/13 take "th" despite ending in 1/2/3, so the
// 11–13 case must be checked before the last digit.
func Ordinal(n int64) string {
	s := strconv.FormatInt(n, 10)
	a := n
	if a < 0 {
		a = -a
	}
	if a%100 >= 11 && a%100 <= 13 {
		return s + "th"
	}
	switch a % 10 {
	case 1:
		return s + "st"
	case 2:
		return s + "nd"
	case 3:
		return s + "rd"
	}
	return s + "th"
}

// Plural returns "1 block" / "2 blocks", using plural when given, else word+"s".
func Plural(n int64, word, plural string) string {
	if n == 1 || n == -1 {
		return strconv.FormatInt(n, 10) + " " + word
	}
	if plural == "" {
		plural = word + "s"
	}
	return strconv.FormatInt(n, 10) + " " + plural
}

// Blocks renders a block count at a coarse magnitude — deliberately vague,
// because a block count is not a wall-clock duration.
func Blocks(n int64) string {
	switch {
	case n < 0:
		return "in the past"
	case n == 0:
		return "now"
	case n < 10:
		return Plural(n, "block", "")
	case n < 1000:
		return "~" + Comma(n/10*10) + " blocks"
	default:
		return "~" + Comma(n/100*100) + " blocks"
	}
}

// Truncate shortens s to at most max runes, appending "…" when it cut.
// Counts RUNES, not bytes, so a multi-byte string is not sliced mid-character.
func Truncate(s string, max int) string {
	if max <= 0 {
		return ""
	}
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	if max == 1 {
		return "…"
	}
	return string(r[:max-1]) + "…"
}
