package ipaddrdemo

// ExampleRender pins the realm's root Render output as a testable example.
// Every number in it, the bounds and sizes of the registry blocks and the
// five-block cover of 10.0.0.5-10.0.0.20, is computed by the library inside
// the VM, so this example doubles as a conformance test for it.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # IPv4 addressing
	//
	// Addresses and CIDR blocks as integer arithmetic, demoing the [`p/moul/x/daily/ipaddr`](/p/moul/x/daily/ipaddr/v0) library.
	//
	// ## Special-purpose blocks
	//
	// | prefix | what it is | RFC | first | last | addresses |
	// | --- | --- | --- | --- | --- | --- |
	// | `0.0.0.0/8` | this network | RFC 1122 | 0.0.0.0 | 0.255.255.255 | 16777216 |
	// | `10.0.0.0/8` | private-use | RFC 1918 | 10.0.0.0 | 10.255.255.255 | 16777216 |
	// | `100.64.0.0/10` | shared address space | RFC 6598 | 100.64.0.0 | 100.127.255.255 | 4194304 |
	// | `127.0.0.0/8` | loopback | RFC 1122 | 127.0.0.0 | 127.255.255.255 | 16777216 |
	// | `169.254.0.0/16` | link-local | RFC 3927 | 169.254.0.0 | 169.254.255.255 | 65536 |
	// | `172.16.0.0/12` | private-use | RFC 1918 | 172.16.0.0 | 172.31.255.255 | 1048576 |
	// | `192.0.0.0/24` | IETF protocol assignments | RFC 6890 | 192.0.0.0 | 192.0.0.255 | 256 |
	// | `192.0.2.0/24` | documentation (TEST-NET-1) | RFC 5737 | 192.0.2.0 | 192.0.2.255 | 256 |
	// | `192.88.99.0/24` | 6to4 relay anycast | RFC 7526 | 192.88.99.0 | 192.88.99.255 | 256 |
	// | `192.168.0.0/16` | private-use | RFC 1918 | 192.168.0.0 | 192.168.255.255 | 65536 |
	// | `198.18.0.0/15` | benchmarking | RFC 2544 | 198.18.0.0 | 198.19.255.255 | 131072 |
	// | `198.51.100.0/24` | documentation (TEST-NET-2) | RFC 5737 | 198.51.100.0 | 198.51.100.255 | 256 |
	// | `203.0.113.0/24` | documentation (TEST-NET-3) | RFC 5737 | 203.0.113.0 | 203.0.113.255 | 256 |
	// | `224.0.0.0/4` | multicast | RFC 5771 | 224.0.0.0 | 239.255.255.255 | 268435456 |
	// | `240.0.0.0/4` | reserved | RFC 1112 | 240.0.0.0 | 255.255.255.255 | 268435456 |
	// | `255.255.255.255/32` | limited broadcast | RFC 8190 | 255.255.255.255 | 255.255.255.255 | 1 |
	//
	// Everything not in that table is ordinary public unicast space. Three of the rows are the RFC 1918 blocks, and the middle one is the trap: 172.16.0.0/12 runs to 172.31.255.255, so `172.32.0.1` is a public address that a hand-written check on the second octet usually swallows.
	//
	// ## Inside one prefix
	//
	// `192.168.1.37/24`, which is written with a host octet rather than its network address:
	//
	// | field | value |  |
	// | --- | --- | --- |
	// | as written | 192.168.1.37/24 | kept as given, not rewritten |
	// | network | 192.168.1.0 | the block's canonical name |
	// | netmask | 255.255.255.0 | /24 |
	// | first | 192.168.1.0 |  |
	// | last | 192.168.1.255 | the subnet broadcast address |
	// | addresses | 256 |  |
	// | usable hosts | 254 | network and broadcast addresses removed |
	// | classification | private-use (RFC 1918, 192.168.0.0/16) |  |
	//
	// ## A range is almost never a prefix
	//
	// `10.0.0.5 - 10.0.0.20` is 16 addresses and takes five blocks:
	//
	// | # | block | first | last | addresses |
	// | --- | --- | --- | --- | --- |
	// | 1 | `10.0.0.5/32` | 10.0.0.5 | 10.0.0.5 | 1 |
	// | 2 | `10.0.0.6/31` | 10.0.0.6 | 10.0.0.7 | 2 |
	// | 3 | `10.0.0.8/29` | 10.0.0.8 | 10.0.0.15 | 8 |
	// | 4 | `10.0.0.16/30` | 10.0.0.16 | 10.0.0.19 | 4 |
	// | 5 | `10.0.0.20/32` | 10.0.0.20 | 10.0.0.20 | 1 |
	//
	// The blocks widen and then narrow again because each one has to start on its own alignment: an address ending in 5 can only begin a /32, while 10.0.0.8 can begin a /29.
	//
	// Append a query to ask about your own: [`/8.8.8.8`](/r/moul/x/daily/ipaddrdemo/v0:8.8.8.8), [`/172.16.0.0/12`](/r/moul/x/daily/ipaddrdemo/v0:172.16.0.0/12), [`/10.0.0.5-10.0.0.20`](/r/moul/x/daily/ipaddrdemo/v0:10.0.0.5-10.0.0.20)
	//
	// > ℹ️ **IPv4 only, and the parser is strict.** A leading zero in an octet is rejected rather than read as octal, because `010.0.0.1` is 10.0.0.1 to a browser and 8.0.0.1 to the C library, and an allowlist that picks one reading disagrees with whatever picked the other.
}
