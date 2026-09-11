package printfdebugging

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The SGR codes are transcribed from fatih/color. They are plain `iota` blocks,
// so a single inserted or removed line silently shifts every constant below it
// and the terminal renders the wrong colour. Pin the boundaries and the offsets.

func TestBaseAttributes(t *testing.T) {
	cases := []struct {
		name string
		got  Attribute
		want int
	}{
		{"Reset", Reset, 0},
		{"Bold", Bold, 1},
		{"Faint", Faint, 2},
		{"Italic", Italic, 3},
		{"Underline", Underline, 4},
		{"BlinkSlow", BlinkSlow, 5},
		{"BlinkRapid", BlinkRapid, 6},
		{"ReverseVideo", ReverseVideo, 7},
		{"Concealed", Concealed, 8},
		{"CrossedOut", CrossedOut, 9},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, int(c.got), c.name)
	}
}

// TestResetAttributes covers the block with a deliberate `_` gap at 26.
func TestResetAttributes(t *testing.T) {
	cases := []struct {
		name string
		got  Attribute
		want int
	}{
		{"ResetBold", ResetBold, 22},
		{"ResetItalic", ResetItalic, 23},
		{"ResetUnderline", ResetUnderline, 24},
		{"ResetBlinking", ResetBlinking, 25},
		// 26 is skipped with `_`
		{"ResetReversed", ResetReversed, 27},
		{"ResetConcealed", ResetConcealed, 28},
		{"ResetCrossedOut", ResetCrossedOut, 29},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, int(c.got), c.name)
	}
}

func TestForegroundColors(t *testing.T) {
	cases := []struct {
		name string
		got  Attribute
		want int
	}{
		{"FgBlack", FgBlack, 30},
		{"FgRed", FgRed, 31},
		{"FgGreen", FgGreen, 32},
		{"FgYellow", FgYellow, 33},
		{"FgBlue", FgBlue, 34},
		{"FgMagenta", FgMagenta, 35},
		{"FgCyan", FgCyan, 36},
		{"FgWhite", FgWhite, 37},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, int(c.got), c.name)
	}
}

func TestBackgroundColors(t *testing.T) {
	cases := []struct {
		name string
		got  Attribute
		want int
	}{
		{"BgBlack", BgBlack, 40},
		{"BgRed", BgRed, 41},
		{"BgWhite", BgWhite, 47},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, int(c.got), c.name)
	}
}

func TestHiIntensityColors(t *testing.T) {
	cases := []struct {
		name string
		got  Attribute
		want int
	}{
		{"FgHiBlack", FgHiBlack, 90},
		{"FgHiWhite", FgHiWhite, 97},
		{"BgHiBlack", BgHiBlack, 100},
		{"BgHiWhite", BgHiWhite, 107},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, int(c.got), c.name)
	}
}

func TestEscape(t *testing.T) {
	uassert.Equal(t, "\x1b", Escape)
	uassert.Equal(t, 1, len(Escape))
}

// TestOutputHelpersDoNotPanic exercises the two exported helpers. They only
// println, so there is no return value to assert — this pins that they build
// and run (BigRedLine formats Escape/Attribute through ufmt).
func TestOutputHelpersDoNotPanic(t *testing.T) {
	BigRedLine()
	BigRedLine("one")
	BigRedLine("several", "args", "joined")
	Success()
}
