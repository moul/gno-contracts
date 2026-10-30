package base45demo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw it
// renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesArgument pins that the echoed argument reaches the page
// escaped: every backtick, bracket and parenthesis the caller typed arrives
// backslashed, so none of them can close a span or open a link.
//
// The row below it is the same 22 bytes through the codec, and it is left
// alone by ui.Cell because there is nothing in it to escape: the base45
// alphabet holds no backtick, no bracket and no pipe. So the encoded half of
// this page can never carry markup whatever the caller types, and the echo is
// the only place an injection could land. That is what this test breaks on.
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
		"| base45 |  9FZ248PB/YBA9DIWENPERZC ED/85$8C |\n" +
		"| characters | 33 |\n"
	uassert.Equal(t, want, Render("/"+payload))
}
