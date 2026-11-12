// Package ipaddr is IPv4 addressing as integer arithmetic: a strict parser, a
// CIDR prefix with the questions people actually ask of one, the IANA
// special-purpose registry, and the range-to-CIDR summarizer.
//
// An [Addr] is the address's 32-bit numeric value and nothing else, so every
// operation here is a shift or a mask. There is no allocation on the hot path,
// no string ever round-trips through a number to be compared, and no float is
// involved anywhere.
//
// Three things are worth knowing before reading the API.
//
// It is IPv4 only, deliberately. IPv6 is a different type with different
// arithmetic (128 bits, no broadcast address, a zone identifier), and folding
// the two into one type is what makes a library like this hard to read. A
// caller that needs both wants two types.
//
// The parser is strict, in the same place Go's net/netip is strict: a leading
// zero in an octet is rejected rather than read as octal. "010.0.0.1" is a
// different address to inetd, to glibc and to a browser, and silently picking
// one of the readings is how an allowlist and the thing enforcing it come to
// disagree. See [ParseAddr].
//
// A [Prefix] keeps the address it was parsed from, so "192.168.1.37/24" stays
// spelled that way, again as Go does. The block it names is still 192.168.1.0/24,
// and [Prefix.Contains], [Prefix.First], [Prefix.Last] and [Prefix.Count] all
// answer for the block. [Prefix.Masked] is how you get the canonical spelling,
// [Prefix.IsMasked] is how you ask whether you already have it.
//
// Live demo: [r/moul/x/daily/ipaddrdemo](/r/moul/x/daily/ipaddrdemo/v0).
package ipaddr

import (
	"strconv"
	"strings"
)

// maxAddr is the highest IPv4 address, 255.255.255.255.
const maxAddr = uint64(1)<<32 - 1

// Addr is an IPv4 address, held as the 32-bit number the four octets spell.
//
// The zero value is 0.0.0.0, which is a real address (the unspecified one), so
// there is no "invalid" Addr: a parse failure is reported by the bool, never
// by a sentinel value.
type Addr uint32

// AddrFrom4 builds an address from its four octets, high to low.
func AddrFrom4(a, b, c, d uint8) Addr {
	return Addr(uint32(a)<<24 | uint32(b)<<16 | uint32(c)<<8 | uint32(d))
}

// ParseAddr reads a dotted-quad IPv4 address and reports whether it was one.
//
// Exactly four decimal octets, each 0 to 255, each written with no leading
// zero: "0.0.0.1" parses and "00.0.0.1" does not. Nothing else is accepted,
// which rules out the shorthands the C library takes ("10.1" for 10.0.0.1,
// "0x0a000001", a trailing dot) and leaves no reading of a string to argue
// about.
//
// The leading-zero rule is the one that matters for anything security-shaped.
// "010.0.0.1" is 10.0.0.1 to a browser and 8.0.0.1 to inet_aton, so a parser
// that accepts it has to pick, and whichever it picks disagrees with something
// else in the stack.
func ParseAddr(s string) (Addr, bool) {
	var v uint32
	i := 0
	for field := 0; field < 4; field++ {
		if field > 0 {
			if i >= len(s) || s[i] != '.' {
				return 0, false
			}
			i++
		}
		start := i
		n := 0
		for i < len(s) && s[i] >= '0' && s[i] <= '9' {
			n = n*10 + int(s[i]-'0')
			i++
		}
		switch {
		case i == start, i-start > 3, n > 255:
			return 0, false
		case i-start > 1 && s[start] == '0':
			return 0, false
		}
		v = v<<8 | uint32(n)
	}
	if i != len(s) {
		return 0, false
	}
	return Addr(v), true
}

// String renders the address as a dotted quad.
func (a Addr) String() string {
	o := a.Octets()
	return strconv.Itoa(int(o[0])) + "." +
		strconv.Itoa(int(o[1])) + "." +
		strconv.Itoa(int(o[2])) + "." +
		strconv.Itoa(int(o[3]))
}

// Octets returns the four octets, high to low.
func (a Addr) Octets() [4]uint8 {
	return [4]uint8{uint8(a >> 24), uint8(a >> 16), uint8(a >> 8), uint8(a)}
}

// Next returns the following address, and false at 255.255.255.255.
//
// The bool is the point: IPv4 arithmetic wraps silently in 32 bits, so a loop
// written as `for a := first; a <= last; a++` never terminates when last is
// the top of the space. Every walk in this package goes through Next or
// through uint64 arithmetic for that reason.
func (a Addr) Next() (Addr, bool) {
	if uint64(a) == maxAddr {
		return a, false
	}
	return a + 1, true
}

// Prev returns the preceding address, and false at 0.0.0.0.
func (a Addr) Prev() (Addr, bool) {
	if a == 0 {
		return a, false
	}
	return a - 1, true
}

// IsUnspecified reports whether the address is 0.0.0.0.
func (a Addr) IsUnspecified() bool { return a == 0 }

// IsLoopback reports whether the address is in 127.0.0.0/8.
func (a Addr) IsLoopback() bool { return a>>24 == 127 }

// IsPrivate reports whether the address is in one of the three RFC 1918
// blocks: 10.0.0.0/8, 172.16.0.0/12 or 192.168.0.0/16.
//
// 172.16.0.0/12 is the one that gets hand-rolled wrong, because the second
// octet runs 16 to 31 rather than to 16 or to 32. 172.32.0.1 is public.
func (a Addr) IsPrivate() bool {
	o := a.Octets()
	return o[0] == 10 ||
		(o[0] == 172 && o[1]&0xf0 == 16) ||
		(o[0] == 192 && o[1] == 168)
}

// IsLinkLocal reports whether the address is in 169.254.0.0/16.
func (a Addr) IsLinkLocal() bool { return a>>16 == 169<<8|254 }

// IsMulticast reports whether the address is in 224.0.0.0/4.
func (a Addr) IsMulticast() bool { return a>>28 == 0xe }

// IsBroadcast reports whether the address is the limited broadcast address,
// 255.255.255.255. The per-subnet broadcast address is [Prefix.Last].
func (a Addr) IsBroadcast() bool { return uint64(a) == maxAddr }

// IsGlobalUnicast reports whether the address is routable on the public
// internet: not in any entry of [SpecialBlocks].
func (a Addr) IsGlobalUnicast() bool {
	_, special := Classify(a)
	return !special
}

// Block is one entry of the IANA IPv4 special-purpose address registry: a
// prefix, what it is for, and the document that says so.
type Block struct {
	Prefix Prefix
	Name   string
	RFC    string
}

// SpecialBlocks is the IANA IPv4 Special-Purpose Address Registry, which is
// to say every prefix that is not ordinary public unicast space.
//
// It is ordered by address rather than by specificity, because that is how it
// reads as a table; [Classify] does the longest-prefix work instead of relying
// on the order here.
var SpecialBlocks = []Block{
	{mustPrefix(0, 0, 0, 0, 8), "this network", "RFC 1122"},
	{mustPrefix(10, 0, 0, 0, 8), "private-use", "RFC 1918"},
	{mustPrefix(100, 64, 0, 0, 10), "shared address space", "RFC 6598"},
	{mustPrefix(127, 0, 0, 0, 8), "loopback", "RFC 1122"},
	{mustPrefix(169, 254, 0, 0, 16), "link-local", "RFC 3927"},
	{mustPrefix(172, 16, 0, 0, 12), "private-use", "RFC 1918"},
	{mustPrefix(192, 0, 0, 0, 24), "IETF protocol assignments", "RFC 6890"},
	{mustPrefix(192, 0, 2, 0, 24), "documentation (TEST-NET-1)", "RFC 5737"},
	{mustPrefix(192, 88, 99, 0, 24), "6to4 relay anycast", "RFC 7526"},
	{mustPrefix(192, 168, 0, 0, 16), "private-use", "RFC 1918"},
	{mustPrefix(198, 18, 0, 0, 15), "benchmarking", "RFC 2544"},
	{mustPrefix(198, 51, 100, 0, 24), "documentation (TEST-NET-2)", "RFC 5737"},
	{mustPrefix(203, 0, 113, 0, 24), "documentation (TEST-NET-3)", "RFC 5737"},
	{mustPrefix(224, 0, 0, 0, 4), "multicast", "RFC 5771"},
	{mustPrefix(240, 0, 0, 0, 4), "reserved", "RFC 1112"},
	{mustPrefix(255, 255, 255, 255, 32), "limited broadcast", "RFC 8190"},
}

// mustPrefix builds a prefix from constants, for the table above.
func mustPrefix(a, b, c, d uint8, bits int) Prefix {
	return Prefix{base: AddrFrom4(a, b, c, d), bits: bits}
}

// Classify returns the most specific entry of [SpecialBlocks] holding the
// address, and false when the address is ordinary public unicast space.
//
// Most specific, not first match: 255.255.255.255 is inside 240.0.0.0/4 and is
// also its own /32 entry, and the /32 is the useful answer.
func Classify(a Addr) (Block, bool) {
	best := Block{}
	found := false
	for _, b := range SpecialBlocks {
		if !b.Prefix.Contains(a) {
			continue
		}
		if !found || b.Prefix.bits > best.Prefix.bits {
			best = b
			found = true
		}
	}
	return best, found
}

// Prefix is a CIDR block: the address it was written with, and a prefix
// length in bits.
//
// The address is kept as given rather than masked on construction, so
// "192.168.1.37/24" renders back as itself. Everything that asks about the
// block it names, [Prefix.Contains], [Prefix.First], [Prefix.Last],
// [Prefix.Count], masks first.
type Prefix struct {
	base Addr
	bits int
}

// PrefixFrom builds a prefix, and reports false when bits is outside 0 to 32.
func PrefixFrom(base Addr, bits int) (Prefix, bool) {
	if bits < 0 || bits > 32 {
		return Prefix{}, false
	}
	return Prefix{base: base, bits: bits}, true
}

// ParsePrefix reads "address/bits" and reports whether it was one.
//
// Both halves are strict: the address goes through [ParseAddr], and the bit
// count is 0 to 32 written with no leading zero, so "10.0.0.0/08" is rejected
// for the same reason "010.0.0.0/8" is. The address need not be the network
// address of the block, and is not rewritten if it is not.
func ParsePrefix(s string) (Prefix, bool) {
	i := strings.LastIndex(s, "/")
	if i < 0 {
		return Prefix{}, false
	}
	a, ok := ParseAddr(s[:i])
	if !ok {
		return Prefix{}, false
	}
	digits := s[i+1:]
	if len(digits) == 0 || len(digits) > 2 {
		return Prefix{}, false
	}
	if len(digits) > 1 && digits[0] == '0' {
		return Prefix{}, false
	}
	bits := 0
	for k := 0; k < len(digits); k++ {
		if digits[k] < '0' || digits[k] > '9' {
			return Prefix{}, false
		}
		bits = bits*10 + int(digits[k]-'0')
	}
	return PrefixFrom(a, bits)
}

// Base returns the address the prefix was written with, unmasked.
func (p Prefix) Base() Addr { return p.base }

// Bits returns the prefix length.
func (p Prefix) Bits() int { return p.bits }

// String renders the prefix as "address/bits", with the address as written.
func (p Prefix) String() string { return p.base.String() + "/" + strconv.Itoa(p.bits) }

// MaskOf returns the netmask for a prefix length: MaskOf(24) is 255.255.255.0.
// Out-of-range lengths clamp to 0.0.0.0 and 255.255.255.255.
//
// The shift is done in 64 bits on purpose. A 32-bit `^uint32(0) << 32` is
// undefined in C and, in Go, is a shift count equal to the width, which
// yields 0 rather than the all-ones a /32 wants; doing it wide and truncating
// gets both ends of the range right with no special case.
func MaskOf(bits int) Addr {
	if bits <= 0 {
		return 0
	}
	if bits >= 32 {
		return Addr(maxAddr)
	}
	return Addr(maxAddr << uint(32-bits) & maxAddr)
}

// Mask returns the prefix's netmask.
func (p Prefix) Mask() Addr { return MaskOf(p.bits) }

// Masked returns the prefix with its address replaced by the network address
// of the block, which is the canonical spelling.
func (p Prefix) Masked() Prefix {
	return Prefix{base: p.base & p.Mask(), bits: p.bits}
}

// IsMasked reports whether the prefix is already written with its network
// address, so Masked would change nothing.
func (p Prefix) IsMasked() bool { return p.base&p.Mask() == p.base }

// Contains reports whether the address falls in the block.
func (p Prefix) Contains(a Addr) bool {
	m := p.Mask()
	return a&m == p.base&m
}

// ContainsPrefix reports whether q's block is entirely inside p's. A prefix
// contains itself.
func (p Prefix) ContainsPrefix(q Prefix) bool {
	return p.bits <= q.bits && p.Contains(q.base)
}

// Overlaps reports whether the two blocks share any address. It is symmetric,
// and one block overlapping another means one of them contains the other:
// CIDR blocks are either nested or disjoint, never partially crossed.
func (p Prefix) Overlaps(q Prefix) bool {
	return p.ContainsPrefix(q) || q.ContainsPrefix(p)
}

// First returns the network address of the block, the lowest address in it.
func (p Prefix) First() Addr { return p.base & p.Mask() }

// Last returns the highest address in the block, which for a /31 or wider is
// also its broadcast address.
func (p Prefix) Last() Addr { return p.First() | ^p.Mask() }

// Count returns how many addresses the block holds, network and broadcast
// addresses included.
//
// It returns uint64 because 0.0.0.0/0 holds 4294967296 addresses, one more
// than a uint32 can count. That off-by-one at the widest prefix is the whole
// reason the type is not uint32.
func (p Prefix) Count() uint64 { return uint64(1) << uint(32-p.bits) }

// Usable returns how many addresses in the block can be assigned to a host:
// [Prefix.Count] less the network and broadcast addresses.
//
// A /31 and a /32 are the exceptions and they are not arithmetic. A /31 is a
// point-to-point link whose two addresses are both hosts (RFC 3021), and a /32
// is a single host with nothing to subtract, so both return their full count
// where the formula would return 0 and -2.
func (p Prefix) Usable() uint64 {
	if p.bits >= 31 {
		return p.Count()
	}
	return p.Count() - 2
}

// Summarize returns the shortest list of aligned CIDR blocks that covers
// exactly the inclusive range first..last, and nothing outside it. The range
// reversed returns an empty list.
//
// This is the operation a firewall rule, a route table or an allowlist needs
// and that CIDR notation cannot express directly: an arbitrary range almost
// never is a prefix. 10.0.0.5 through 10.0.0.20 takes five blocks, and the
// shape of them (a /32, then wider, then narrowing again) is what greedy
// alignment always produces.
//
// The greed is in two steps per block, and both are needed. The first takes
// the widest block that can START at the cursor, which is fixed by how many
// low bits of the cursor are zero: an address ending in 5 can only begin a
// /32. The second narrows that block until it also ENDS inside the range.
// Dropping either step gives blocks that are unaligned or that overshoot.
func Summarize(first, last Addr) []Prefix {
	out := []Prefix{}
	if first > last {
		return out
	}
	lo := uint64(first)
	hi := uint64(last)
	for lo <= hi {
		step := trailingZeros(lo)
		for step > 0 && lo+(uint64(1)<<uint(step))-1 > hi {
			step--
		}
		out = append(out, Prefix{base: Addr(lo), bits: 32 - step})
		// In uint64, so that a block ending at 255.255.255.255 pushes the
		// cursor past the top of the space instead of wrapping to 0.0.0.0.
		lo += uint64(1) << uint(step)
	}
	return out
}

// trailingZeros reports how many low bits of v are zero, capped at 32, which
// is how wide a block may start at v. Zero is the start of the whole space.
func trailingZeros(v uint64) int {
	if v == 0 {
		return 32
	}
	n := 0
	for v&1 == 0 {
		v >>= 1
		n++
	}
	return n
}
