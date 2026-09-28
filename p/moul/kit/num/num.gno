// Package num formats numbers for a human to read: fixed-point amounts,
// percentages and zero padding.
//
// Thousands separators are NOT here. They belong to
// [p/moul/x/daily/humanize](/p/moul/x/daily/humanize/v1), which already owns
// Comma, Bytes, Ordinal, Plural and Blocks.
//
// It exists because nothing in p/moul or p/nt did. Measured across the 828
// .gno files deployed on gnoland-1 by someone other than moul, five
// independent teams wrote their own ugnot-to-GNOT formatter, and the two that
// are byte-level cousins disagree on every input that is not positive. The
// README carries the full table.
//
// # The contract
//
// Every function here is total: no input panics, including the int64 minimum,
// and no input returns a malformed string. That is the whole point of the
// package, because it is precisely where the hand-rolled copies fail.
//
// # Where the decimals come from
//
// gno.land denominates GNOT in ugnot, one millionth of a GNOT, so [GNOT] is
// [Dec] with decimals = 6. A GRC20 token declares its own decimals; pass that
// to [Dec] rather than assuming six.
package num

import (
	"strconv"
	"strings"
)

// GnotDecimals is the number of decimal places between ugnot and GNOT.
const GnotDecimals = 6

// maxDecimals caps the scale [Dec] accepts. An int64 holds at most 19 decimal
// digits, so beyond that every value is pure fraction and the cap costs
// nothing real while keeping the padding loop bounded.
const maxDecimals = 19

// Dec renders v as a fixed-point decimal with the given number of places,
// trailing zeros trimmed: Dec(1234500, 6) is "1.2345", Dec(2000000, 6) is "2".
//
// The sign is carried on the whole part, so Dec(-1, 6) is "-0.000001" and not
// "0.999999". Dec panics only on a negative or out-of-range decimals, which is
// a programming error rather than a value.
func Dec(v int64, decimals int) string {
	return dec(v, decimals, false)
}

// DecFixed is [Dec] without the trailing-zero trim, so every value renders at
// the same width: DecFixed(2000000, 6) is "2.000000". Use it in a column.
func DecFixed(v int64, decimals int) string {
	return dec(v, decimals, true)
}

// GNOT renders an amount in ugnot as GNOT, with no unit: "1.234567".
func GNOT(ugnot int64) string { return Dec(ugnot, GnotDecimals) }

// GNOTf is [GNOT] with the unit appended: "1.234567 GNOT".
func GNOTf(ugnot int64) string { return GNOT(ugnot) + " GNOT" }

// Pct renders basis points as a percentage: Pct(1234) is "12.34%".
// One basis point is a hundredth of a percent, which is the unit every fee on
// this chain is already quoted in.
func Pct(bps int64) string { return Dec(bps, 2) + "%" }

// Pad renders v in base 10, left-padded with zeros to at least width
// characters: Pad(7, 3) is "007". A negative value keeps its sign outside the
// padding, so Pad(-7, 3) is "-007" and the string is width+1 long.
//
// It exists because ufmt supports no width flags: ufmt.Sprintf("%03d", 7)
// returns "7", silently.
//
// Pad is for DISPLAY. For an avl key that must sort in insertion order, use
// [p/moul/kit/store](/p/moul/kit/store/v0), which has no ceiling to overflow.
func Pad(v int64, width int) string {
	neg, m := mag(v)
	s := strconv.FormatUint(m, 10)
	if n := width - len(s); n > 0 {
		s = strings.Repeat("0", n) + s
	}
	if neg {
		return "-" + s
	}
	return s
}

func dec(v int64, decimals int, fixed bool) string {
	if decimals < 0 || decimals > maxDecimals {
		panic("num: decimals out of range [0, 19]")
	}
	neg, m := mag(v)
	sign := ""
	if neg {
		sign = "-"
	}
	if decimals == 0 {
		return sign + strconv.FormatUint(m, 10)
	}

	digits := strconv.FormatUint(m, 10)
	if n := decimals + 1 - len(digits); n > 0 {
		digits = strings.Repeat("0", n) + digits
	}
	cut := len(digits) - decimals
	whole, frac := digits[:cut], digits[cut:]

	if !fixed {
		frac = strings.TrimRight(frac, "0")
		if frac == "" {
			return sign + whole
		}
	}
	return sign + whole + "." + frac
}

// mag splits v into a sign and an unsigned magnitude.
//
// -v on math.MinInt64 is math.MinInt64 again, so every shape that stays in
// int64 is wrong there: `if v < 0 { v = -v }` silently keeps the value
// negative, and a recursive `return "-" + f(-v)` never terminates at all. Both
// are live on gnoland-1 today; the second halts the realm.
//
// `uint64(-v)` happens to give the right answer by twos-complement wraparound,
// but it gets it from the overflow rather than despite it. -(v+1)+1 never
// overflows, so it does not depend on that.
func mag(v int64) (bool, uint64) {
	if v < 0 {
		return true, uint64(-(v+1)) + 1
	}
	return false, uint64(v)
}
