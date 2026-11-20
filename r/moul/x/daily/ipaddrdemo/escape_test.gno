package ipaddrdemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw it
// would render as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y|z"

// TestRenderEscapesAnUnparseableAddress pins that a query the parser refuses
// is reported through ui.Inline and never through a code span, which a
// backtick in the query could close.
func TestRenderEscapesAnUnparseableAddress(t *testing.T) {
	want := 		"# IPv4 addressing\n" +
		"\n" +
		"Addresses and CIDR blocks as integer arithmetic, demoing the [`p/moul/x/daily/ipaddr`](/p/moul/x/daily/ipaddr/v0) library.\n" +
		"\n" +
		"## Not parsed\n" +
		"\n" +
		"x\\` \\!\\[p\\]\\(https:e\\.io\\) \\`y|z is not a dotted-quad IPv4 address.\n" +
		"\n" +
		"[← back](/r/moul/x/daily/ipaddrdemo/v0)\n"
	uassert.Equal(t, want, Render("/"+payload))
}

// TestRenderEscapesAnUnparseablePrefix is the same worry on the other branch:
// a query carrying a "/" routes to ParsePrefix, and its refusal path has to
// escape too.
func TestRenderEscapesAnUnparseablePrefix(t *testing.T) {
	want := 		"# IPv4 addressing\n" +
		"\n" +
		"Addresses and CIDR blocks as integer arithmetic, demoing the [`p/moul/x/daily/ipaddr`](/p/moul/x/daily/ipaddr/v0) library.\n" +
		"\n" +
		"## Not parsed\n" +
		"\n" +
		"10\\.0\\.0\\.0|evil/8 is not a CIDR prefix.\n" +
		"\n" +
		"[← back](/r/moul/x/daily/ipaddrdemo/v0)\n"
	uassert.Equal(t, want, Render("/10.0.0.0|evil/8"))
}

// TestRenderEscapesAnUnparseableRangeHalf covers the third branch: a "-" in
// the query routes to the range view, which rejects each half separately and
// echoes whichever one failed.
func TestRenderEscapesAnUnparseableRangeHalf(t *testing.T) {
	want := 		"# IPv4 addressing\n" +
		"\n" +
		"Addresses and CIDR blocks as integer arithmetic, demoing the [`p/moul/x/daily/ipaddr`](/p/moul/x/daily/ipaddr/v0) library.\n" +
		"\n" +
		"## Not parsed\n" +
		"\n" +
		"9\\.9\\.9\\.9|x is not a dotted-quad IPv4 address.\n" +
		"\n" +
		"[← back](/r/moul/x/daily/ipaddrdemo/v0)\n"
	uassert.Equal(t, want, Render("/1.2.3.4-9.9.9.9|x"))
}
