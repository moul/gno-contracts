package num

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

const minInt64 = -9223372036854775808

func TestDec(t *testing.T) {
	cases := []struct {
		name     string
		v        int64
		decimals int
		want     string
	}{
		{"whole", 2000000, 6, "2"},
		{"trimmed", 1234500, 6, "1.2345"},
		{"full", 1234567, 6, "1.234567"},
		{"zero", 0, 6, "0"},
		{"sub-unit", 100, 6, "0.0001"},
		{"smallest unit", 1, 6, "0.000001"},
		{"no decimals", 42, 0, "42"},
		{"negative whole", -2000000, 6, "-2"},
		{"negative fraction", -1500000, 6, "-1.5"},
		{"negative sub-unit", -100, 6, "-0.0001"},
		{"negative smallest unit", -1, 6, "-0.000001"},
		{"two decimals", 1234, 2, "12.34"},
		{"int64 max", 9223372036854775807, 6, "9223372036854.775807"},
		{"int64 min", minInt64, 6, "-9223372036854.775808"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, Dec(tc.v, tc.decimals))
		})
	}
}

func TestDecFixedKeepsWidth(t *testing.T) {
	cases := []struct {
		v    int64
		want string
	}{
		{2000000, "2.000000"},
		{1234500, "1.234500"},
		{0, "0.000000"},
		{-1, "-0.000001"},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, DecFixed(tc.v, 6))
	}
}

// TestEveryDecimalStringParsesBack is the invariant the hand-rolled copies
// break: whatever comes out must be a number again. "-1." and "0.999" for a
// negative input both fail here, which is what the two live implementations
// return.
func TestEveryDecimalStringParsesBack(t *testing.T) {
	values := []int64{
		0, 1, -1, 100, -100, 999999, -999999, 1000000, -1000000,
		1234567, -1234567, 9223372036854775807, minInt64,
	}
	for _, v := range values {
		for _, fixed := range []bool{false, true} {
			got := dec(v, 6, fixed)
			f, err := strconv.ParseFloat(got, 64)
			if err != nil {
				t.Errorf("dec(%d, 6, %t) = %q, not a number: %v", v, fixed, got, err)
				continue
			}
			if (v < 0) != (f < 0) && f != 0 {
				t.Errorf("dec(%d, 6, %t) = %q, sign flipped", v, fixed, got)
			}
		}
	}
}

// TestMagnitudeSurvivesTheInt64Minimum pins the one input that makes the
// obvious implementations fail. `-v` on the minimum is the minimum again, so a
// `if v < 0 { v = -v }` keeps it negative and a recursive `"-" + f(-v)` never
// terminates. A mainnet realm does the second.
func TestMagnitudeSurvivesTheInt64Minimum(t *testing.T) {
	neg, m := mag(minInt64)
	uassert.True(t, neg)
	uassert.Equal(t, "9223372036854775808", strconv.FormatUint(m, 10))
}

func TestGNOT(t *testing.T) {
	uassert.Equal(t, "1.234567", GNOT(1234567))
	uassert.Equal(t, "1.234567 GNOT", GNOTf(1234567))
	uassert.Equal(t, "0 GNOT", GNOTf(0))
	uassert.Equal(t, "-1.5 GNOT", GNOTf(-1500000))
}

func TestPct(t *testing.T) {
	uassert.Equal(t, "12.34%", Pct(1234))
	uassert.Equal(t, "1%", Pct(100))
	uassert.Equal(t, "0.01%", Pct(1))
	uassert.Equal(t, "0%", Pct(0))
	uassert.Equal(t, "-12.34%", Pct(-1234))
}

func TestPad(t *testing.T) {
	cases := []struct {
		v     int64
		width int
		want  string
	}{
		{7, 3, "007"},
		{123, 3, "123"},
		{1234, 3, "1234"},
		{0, 2, "00"},
		{7, 0, "7"},
		{-7, 3, "-007"},
		{minInt64, 3, "-9223372036854775808"},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, Pad(tc.v, tc.width))
	}
}

func TestDecRejectsAnImpossibleScale(cur realm, t *testing.T) {
	msg := "num: decimals out of range [0, 19]"
	uassert.PanicsWithMessage(t, cur, msg, func() { Dec(1, -1) })
	uassert.PanicsWithMessage(t, cur, msg, func() { Dec(1, 20) })
	uassert.NotPanics(t, cur, func() { Dec(1, 0) })
	uassert.NotPanics(t, cur, func() { Dec(1, 19) })
}
