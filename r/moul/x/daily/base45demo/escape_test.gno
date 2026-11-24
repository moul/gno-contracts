package base45demo

import (
	"strings"
	"testing"

	"gno.land/p/moul/x/daily/base45/v0"
	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw it
// renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesArgument pins that the echoed argument reaches the page
// escaped: every backtick, bracket and parenthesis the caller typed arrives
// backslashed, so none of them can close a span or open a link.
//
// The row below it is the same 22 bytes through the codec, in a code span: the
// base45 alphabet holds no backtick, so the encoded half of this page can never
// carry markup whatever the caller types, and the echo is the only place an
// injection could land. The span is padded because the value starts with a
// space, which a bare cell would trim.
//
// uassert.Equal rather than an Example, because the payload is a format string
// as far as a failure message is concerned and because the exact backslashes
// are the assertion.
func TestRenderEscapesArgument(t *testing.T) {
	want := "# Base45\n\n" +
		"The QR-alphanumeric encoding of RFC 9285, demoing the " +
		"[`p/moul/x/daily/base45`](/p/moul/x/daily/base45/v0) library.\n\n" +
		"Encoding x\\` \\!\\[p\\]\\(https:e\\.io\\) \\`y:\n\n" +
		"| field | value |\n| --- | --- |\n" +
		"| input | 22 bytes |\n" +
		"| base45 | `  9FZ248PB/YBA9DIWENPERZC ED/85$8C ` |\n" +
		"| characters | 33 |\n"
	uassert.Equal(t, want, Render("/"+payload))
}

// TestRenderedValueDecodesBack reads the base45 value the way a GFM renderer
// shows it, not as markdown source, and decodes it. A bare cell is trimmed, so
// Render("/Q") used to show "1" for " 1", a string that decodes to other bytes;
// pinning the source alone cannot see that.
func TestRenderedValueDecodesBack(t *testing.T) {
	inputs := []string{"Q", payload, "gno.land", "ietf!"}
	for c := byte(0x20); c < 0x7f; c++ {
		inputs = append(inputs, string(c), "a"+string(c), string(c)+"z")
	}
	for _, in := range inputs {
		shown, ok := renderedBase45(Render("/" + in))
		if !ok {
			t.Errorf("no base45 row rendered for input %q", in)
			continue
		}
		got, err := base45.Decode(shown)
		if err != nil {
			t.Errorf("input %q: shown value %q does not decode: %v", in, shown, err)
			continue
		}
		if got != in {
			t.Errorf("input %q: shown value %q decodes to %q", in, shown, got)
		}
	}
}

// renderedBase45 extracts the base45 row's cell and applies what a GFM
// renderer does to it: trim the cell, then strip a code span's fence and, when
// the content both starts and ends with a space, one space from each side.
func renderedBase45(page string) (string, bool) {
	const prefix = "| base45 |"
	for _, line := range strings.Split(page, "\n") {
		if !strings.HasPrefix(line, prefix) || !strings.HasSuffix(line, "|") {
			continue
		}
		cell := strings.TrimSpace(line[len(prefix) : len(line)-1])
		n := 0
		for n < len(cell) && cell[n] == '`' {
			n++
		}
		if n == 0 {
			return cell, true
		}
		if len(cell) < 2*n {
			return "", false
		}
		code := cell[n : len(cell)-n]
		if len(code) >= 2 && code[0] == ' ' && code[len(code)-1] == ' ' && strings.TrimSpace(code) != "" {
			code = code[1 : len(code)-1]
		}
		return code, true
	}
	return "", false
}
