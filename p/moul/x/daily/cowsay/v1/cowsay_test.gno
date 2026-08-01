package cowsay

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestWrap(t *testing.T) {
	tests := []struct {
		name  string
		text  string
		width int
		want  []string
	}{
		{"empty", "", 10, []string{""}},
		{"single", "hello", 10, []string{"hello"}},
		{"wrap two", "aaa bbb ccc", 7, []string{"aaa bbb", "ccc"}},
		{"hard split", "abcdefghij", 4, []string{"abcd", "efgh", "ij"}},
	}
	for _, tt := range tests {
		got := wrap(tt.text, tt.width)
		uassert.Equal(t, len(tt.want), len(got), tt.name+": line count")
		for i := range tt.want {
			uassert.Equal(t, tt.want[i], got[i], tt.name+": line "+tt.want[i])
		}
		// no wrapped line exceeds width
		for _, ln := range got {
			uassert.True(t, len(ln) <= tt.width, tt.name+": within width")
		}
	}
}

func TestBorderChars(t *testing.T) {
	l, r := borderChars(0, 1)
	uassert.Equal(t, "<", l)
	uassert.Equal(t, ">", r)

	l, r = borderChars(0, 3)
	uassert.Equal(t, "/", l)
	uassert.Equal(t, "\\", r)

	l, r = borderChars(1, 3)
	uassert.Equal(t, "|", l)
	uassert.Equal(t, "|", r)

	l, r = borderChars(2, 3)
	uassert.Equal(t, "\\", l)
	uassert.Equal(t, "/", r)
}

func TestMaxLen(t *testing.T) {
	uassert.Equal(t, 0, maxLen([]string{""}))
	uassert.Equal(t, 5, maxLen([]string{"ab", "cde", "fghij"}))
}

func TestSayDefault(t *testing.T) {
	got := Say("")
	uassert.True(t, strings.Contains(got, defaultMessage), "uses default message")
	uassert.True(t, strings.Contains(got, "(oo)"), "contains cow face")
	uassert.True(t, strings.Contains(got, "< Moo! >"), "single-line bubble")
}

func TestSayWrapsMultiline(t *testing.T) {
	msg := "the quick brown fox jumps over the lazy dog many many times over"
	got := Say(msg)
	// multi-line bubbles use slashes, never the single-line angle brackets
	uassert.True(t, strings.Contains(got, "/"), "multi-line top border char")
	uassert.False(t, strings.Contains(got, "< "), "no single-line marker")
}
