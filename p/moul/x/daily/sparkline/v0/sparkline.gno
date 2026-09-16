// Package sparkline renders a numeric series as one line of Unicode block
// characters — ▁▂▃▄▅▆▇█ — so a realm's Render can show a trend inline, with no
// image, no chart library and no client-side code.
//
// Everything is integer math, deliberately. A realm's Render must produce
// byte-identical output on every validating node, and floating point is the
// usual way that quietly stops being true. Scaling here is integer division
// with the rounding rule stated below, so a given series always yields exactly
// the same runes.
//
// Rendering is O(len(values)) and allocates one builder; a realm should bound
// what it feeds in (slice to a window) rather than sparking an unbounded,
// user-grown slice.
//
// A live demo of this package is at
// [r/moul/x/daily/sparklinedemo](/r/moul/x/daily/sparklinedemo/v0).
package sparkline

import "strings"

// Levels is the ramp, lowest to highest. A string constant rather than a
// []rune so callers cannot mutate the ramp out from under other realms.
const Levels = "▁▂▃▄▅▆▇█"

// Steps is how many levels the ramp has.
const Steps = 8

// maxInt is the largest int, used to keep the scaling multiply from wrapping.
const maxInt = int(^uint(0) >> 1)

// Ints renders values scaled between their own smallest and largest element.
// An empty series renders as the empty string.
func Ints(values []int) string {
	lo, hi, ok := Bounds(values)
	if !ok {
		return ""
	}
	return Scaled(values, lo, hi)
}

// Scaled renders values against an explicit [lo, hi] window. Values outside it
// clamp to the ends rather than erroring: a window is chosen for readability
// (0..100 for a percentage, say), and one outlier should not be able to break a
// realm's Render.
//
// A window with hi <= lo is treated as flat; see Level.
func Scaled(values []int, lo, hi int) string {
	if len(values) == 0 {
		return ""
	}
	ramp := []rune(Levels)
	var b strings.Builder
	for _, v := range values {
		b.WriteRune(ramp[Level(v, lo, hi)])
	}
	return b.String()
}

// Level maps v within [lo, hi] to a ramp index in [0, Steps-1].
//
// Rounding is floor, so only a value at hi itself reaches the top of the ramp;
// everything below it rounds down. That makes the maximum visually distinct,
// which is what a reader is looking for in a sparkline.
//
// A flat window (hi <= lo) maps everything to the MIDDLE of the ramp, not the
// bottom: a series that sits unchanged at 1000 carries no shape, but drawing it
// along the floor would read as "zero", which is a different and wrong claim.
func Level(v, lo, hi int) int {
	if hi <= lo {
		return Steps / 2
	}
	if v <= lo {
		return 0
	}
	if v >= hi {
		return Steps - 1
	}

	span, d, top := hi-lo, v-lo, Steps-1
	if span <= 0 {
		// hi-lo wrapped: the window is wider than an int can express, so there
		// is no usable ramp. Split at the midpoint, computed without overflowing.
		if v < lo/2+hi/2 {
			return 0
		}
		return Steps - 1
	}
	// d*top would wrap on an extreme span; halve both until it cannot. The
	// chosen bucket is unchanged for any realistic series, and off by at most
	// one level for the pathological ones this protects against.
	for span > maxInt/top {
		span >>= 1
		d >>= 1
	}
	return d * top / span
}

// Bounds returns the smallest and largest value in values. ok is false when
// values is empty, in which case lo and hi are zero.
func Bounds(values []int) (lo, hi int, ok bool) {
	if len(values) == 0 {
		return 0, 0, false
	}
	lo, hi = values[0], values[0]
	for _, v := range values[1:] {
		if v < lo {
			lo = v
		}
		if v > hi {
			hi = v
		}
	}
	return lo, hi, true
}
