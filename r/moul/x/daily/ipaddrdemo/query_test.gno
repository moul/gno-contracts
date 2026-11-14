package ipaddrdemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// TestRenderAddress pins the single-address view on the address the registry
// matches twice: 255.255.255.255 is inside 240.0.0.0/4 and is also its own
// /32 entry, and the page has to name the specific one.
func TestRenderAddress(t *testing.T) {
	want := 		"# IPv4 addressing\n" +
		"\n" +
		"Addresses and CIDR blocks as integer arithmetic, demoing the [`p/moul/x/daily/ipaddr`](/p/moul/x/daily/ipaddr/v0) library.\n" +
		"\n" +
		"## `255.255.255.255`\n" +
		"\n" +
		"| field | value |  |\n" +
		"| --- | --- | --- |\n" +
		"| address | 255.255.255.255 |  |\n" +
		"| as a number | 4294967295 | the 32 bits the four octets spell |\n" +
		"| classification | limited broadcast (RFC 8190, 255.255.255.255/32) |  |\n" +
		"| routable | no | on the public internet |\n" +
		"| flags | broadcast |  |\n" +
		"\n" +
		"[← back](/r/moul/x/daily/ipaddrdemo/v0)\n"
	uassert.Equal(t, want, Render("/255.255.255.255"))
}

// TestRenderPrefix pins the block view on a /31, where "usable hosts" is the
// full count rather than count minus two and the last address is not a
// broadcast address.
func TestRenderPrefix(t *testing.T) {
	want := 		"# IPv4 addressing\n" +
		"\n" +
		"Addresses and CIDR blocks as integer arithmetic, demoing the [`p/moul/x/daily/ipaddr`](/p/moul/x/daily/ipaddr/v0) library.\n" +
		"\n" +
		"## `10.0.0.0/31`\n" +
		"\n" +
		"| field | value |  |\n" +
		"| --- | --- | --- |\n" +
		"| as written | 10.0.0.0/31 | already the network address |\n" +
		"| network | 10.0.0.0 | the block's canonical name |\n" +
		"| netmask | 255.255.255.254 | /31 |\n" +
		"| first | 10.0.0.0 |  |\n" +
		"| last | 10.0.0.1 |  |\n" +
		"| addresses | 2 |  |\n" +
		"| usable hosts | 2 | a point-to-point link, both ends are hosts (RFC 3021) |\n" +
		"| classification | private-use (RFC 1918, 10.0.0.0/8) |  |\n" +
		"\n" +
		"[← back](/r/moul/x/daily/ipaddrdemo/v0)\n"
	uassert.Equal(t, want, Render("/10.0.0.0/31"))
}

// TestRenderReversedRange pins that a backwards range says so instead of
// rendering an empty table.
func TestRenderReversedRange(t *testing.T) {
	want := 		"# IPv4 addressing\n" +
		"\n" +
		"Addresses and CIDR blocks as integer arithmetic, demoing the [`p/moul/x/daily/ipaddr`](/p/moul/x/daily/ipaddr/v0) library.\n" +
		"\n" +
		"## `9.9.9.9 - 1.2.3.4`\n" +
		"\n" +
		"That range runs backwards, so it covers nothing.\n" +
		"\n" +
		"[← back](/r/moul/x/daily/ipaddrdemo/v0)\n"
	uassert.Equal(t, want, Render("/9.9.9.9-1.2.3.4"))
}
