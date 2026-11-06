package quotedprintabledemo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw it
// would render as markup the realm appears to have authored. It is a realistic
// input here and not a contrived one: a backtick is printable ASCII, so the
// body encoder passes it through literally and it reaches the page twice, once
// as the echoed input and once inside the encoded result.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPath pins that both echoes of the caller's string stay
// inside a code span they cannot close: md.InlineCode widens the fence to two
// backticks because the content holds one.
//
// It also pins what the header encoder does NOT escape. A backtick, "!", "["
// and "(" are all vchars, so RFC 2047 Q-encoding leaves them literal and the
// image syntax survives into the encoded word intact. That is correct per the
// RFC and it is exactly why the escaping above is not optional.
func TestRenderEscapesPath(t *testing.T) {
	got := Render("/" + payload)
	uassert.Equal(t, "# Quoted-Printable\n\nRFC 2045 bodies and RFC 2047 header words, demoing the [`p/moul/x/daily/quotedprintable`](/p/moul/x/daily/quotedprintable/v0) library.\n\n## ``x` ![p](https:e.io) `y``\n\n- body: ``x` ![p](https:e.io) `y``\n- header word: ``=?UTF-8?Q?x`_![p](https:e.io)_`y?=``\n", got)
}

// TestRenderLongInputSaysSo pins the two failure messages a caller can reach:
// an input past the library's limit, and one whose header word would exceed the
// 75 characters RFC 2047 allows.
func TestRenderLongInputSaysSo(t *testing.T) {
	got := Render("/" + strings.Repeat("a", 64))
	uassert.True(t, strings.Contains(got, "- body: `"+strings.Repeat("a", 64)+"`"),
		"a 64-character body is still one line")
	uassert.True(t, strings.Contains(got, "encoded-word too long"),
		"the header word refuses past 75 characters")
}
