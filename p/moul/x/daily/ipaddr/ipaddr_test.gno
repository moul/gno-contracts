package ipaddr

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestParseAddr(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want Addr
		ok   bool
	}{
		{"zero", "0.0.0.0", 0, true},
		{"loopback", "127.0.0.1", 2130706433, true},
		{"broadcast", "255.255.255.255", 4294967295, true},
		{"dns", "8.8.8.8", 134744072, true},
		{"private", "192.168.1.1", 3232235777, true},
		{"leading zero", "010.0.0.1", 0, false},
		{"lone zero field is fine", "0.0.0.1", 1, true},
		{"octet too large", "256.0.0.1", 0, false},
		{"three fields", "1.2.3", 0, false},
		{"five fields", "1.2.3.4.5", 0, false},
		{"trailing dot", "1.2.3.4.", 0, false},
		{"leading dot", ".1.2.3.4", 0, false},
		{"empty field", "1..3.4", 0, false},
		{"empty", "", 0, false},
		{"spaces", " 1.2.3.4", 0, false},
		{"four digit field", "1.2.3.4444", 0, false},
		{"hex", "0x1.2.3.4", 0, false},
		{"cidr is not an address", "10.0.0.0/8", 0, false},
	}
	for _, tt := range tests {
		got, ok := ParseAddr(tt.in)
		uassert.Equal(t, tt.ok, ok, "ok for "+tt.name)
		uassert.Equal(t, uint64(tt.want), uint64(got), "value for "+tt.name)
	}
}

func TestAddrStringRoundTrips(t *testing.T) {
	for _, s := range []string{"0.0.0.0", "1.2.3.4", "127.0.0.1", "192.168.255.254", "255.255.255.255"} {
		a, ok := ParseAddr(s)
		uassert.True(t, ok, "parse "+s)
		uassert.Equal(t, s, a.String(), "round trip "+s)
	}
}

func TestAddrFrom4AndOctets(t *testing.T) {
	a := AddrFrom4(192, 168, 1, 10)
	uassert.Equal(t, "192.168.1.10", a.String())
	o := a.Octets()
	uassert.Equal(t, 192, int(o[0]))
	uassert.Equal(t, 168, int(o[1]))
	uassert.Equal(t, 1, int(o[2]))
	uassert.Equal(t, 10, int(o[3]))
}

func TestNextPrevSaturate(t *testing.T) {
	a := AddrFrom4(10, 0, 0, 255)
	n, ok := a.Next()
	uassert.True(t, ok, "next in range")
	uassert.Equal(t, "10.0.1.0", n.String())

	p, ok := a.Prev()
	uassert.True(t, ok, "prev in range")
	uassert.Equal(t, "10.0.0.254", p.String())

	_, ok = Addr(4294967295).Next()
	uassert.False(t, ok, "next off the top")
	_, ok = Addr(0).Prev()
	uassert.False(t, ok, "prev off the bottom")
}

func TestMaskOf(t *testing.T) {
	tests := []struct {
		bits int
		want string
	}{
		{0, "0.0.0.0"},
		{8, "255.0.0.0"},
		{12, "255.240.0.0"},
		{16, "255.255.0.0"},
		{24, "255.255.255.0"},
		{30, "255.255.255.252"},
		{31, "255.255.255.254"},
		{32, "255.255.255.255"},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, MaskOf(tt.bits).String(), "mask of "+tt.want)
	}
}

func TestParsePrefix(t *testing.T) {
	tests := []struct {
		in   string
		want string
		ok   bool
	}{
		{"10.0.0.0/8", "10.0.0.0/8", true},
		{"0.0.0.0/0", "0.0.0.0/0", true},
		{"192.168.1.1/32", "192.168.1.1/32", true},
		{"192.168.1.37/24", "192.168.1.37/24", true}, // kept unmasked, as Go does
		{"10.0.0.0/33", "", false},
		{"10.0.0.0/08", "", false},
		{"10.0.0.0/", "", false},
		{"10.0.0.0", "", false},
		{"10.0.0.0/8/8", "", false},
		{"/8", "", false},
		{"", "", false},
	}
	for _, tt := range tests {
		p, ok := ParsePrefix(tt.in)
		uassert.Equal(t, tt.ok, ok, "ok for "+tt.in)
		if tt.ok {
			uassert.Equal(t, tt.want, p.String(), "string for "+tt.in)
		}
	}
}

func TestPrefixFromRejectsBadBits(t *testing.T) {
	_, ok := PrefixFrom(0, -1)
	uassert.False(t, ok, "negative bits")
	_, ok = PrefixFrom(0, 33)
	uassert.False(t, ok, "bits past 32")
	p, ok := PrefixFrom(AddrFrom4(10, 1, 2, 3), 16)
	uassert.True(t, ok, "valid bits")
	uassert.Equal(t, "10.1.2.3/16", p.String())
}

func TestMaskedAndIsMasked(t *testing.T) {
	p, _ := ParsePrefix("192.168.1.37/24")
	uassert.False(t, p.IsMasked(), "37 is not the network address")
	uassert.Equal(t, "192.168.1.0/24", p.Masked().String())
	uassert.True(t, p.Masked().IsMasked(), "masked is idempotent")

	z, _ := ParsePrefix("1.2.3.4/0")
	uassert.Equal(t, "0.0.0.0/0", z.Masked().String())

	h, _ := ParsePrefix("1.2.3.4/32")
	uassert.True(t, h.IsMasked(), "a /32 is always its own network")
	uassert.Equal(t, "1.2.3.4/32", h.Masked().String())
}

func TestPrefixBoundsAndCounts(t *testing.T) {
	tests := []struct {
		in     string
		first  string
		last   string
		count  uint64
		usable uint64
	}{
		{"192.168.1.0/24", "192.168.1.0", "192.168.1.255", 256, 254},
		{"10.0.0.0/8", "10.0.0.0", "10.255.255.255", 16777216, 16777214},
		{"203.0.113.64/26", "203.0.113.64", "203.0.113.127", 64, 62},
		{"10.0.0.4/30", "10.0.0.4", "10.0.0.7", 4, 2},
		{"10.0.0.4/31", "10.0.0.4", "10.0.0.5", 2, 2},
		{"10.0.0.4/32", "10.0.0.4", "10.0.0.4", 1, 1},
		{"0.0.0.0/0", "0.0.0.0", "255.255.255.255", 4294967296, 4294967294},
		// an unmasked prefix answers for the block it names, not for its own octet
		{"192.168.1.37/24", "192.168.1.0", "192.168.1.255", 256, 254},
	}
	for _, tt := range tests {
		p, ok := ParsePrefix(tt.in)
		uassert.True(t, ok, "parse "+tt.in)
		uassert.Equal(t, tt.first, p.First().String(), "first of "+tt.in)
		uassert.Equal(t, tt.last, p.Last().String(), "last of "+tt.in)
		uassert.Equal(t, tt.count, p.Count(), "count of "+tt.in)
		uassert.Equal(t, tt.usable, p.Usable(), "usable of "+tt.in)
	}
}

func TestContains(t *testing.T) {
	p, _ := ParsePrefix("192.168.1.0/24")
	in := []string{"192.168.1.0", "192.168.1.1", "192.168.1.255"}
	out := []string{"192.168.0.255", "192.168.2.0", "10.0.0.1", "0.0.0.0", "255.255.255.255"}
	for _, s := range in {
		a, _ := ParseAddr(s)
		uassert.True(t, p.Contains(a), s+" is inside 192.168.1.0/24")
	}
	for _, s := range out {
		a, _ := ParseAddr(s)
		uassert.False(t, p.Contains(a), s+" is outside 192.168.1.0/24")
	}

	// The default route holds everything, including both ends of the space.
	d, _ := ParsePrefix("0.0.0.0/0")
	uassert.True(t, d.Contains(0), "0.0.0.0/0 holds 0.0.0.0")
	uassert.True(t, d.Contains(4294967295), "0.0.0.0/0 holds 255.255.255.255")

	// An unmasked prefix contains by block, not by the octet it was written with.
	u, _ := ParsePrefix("192.168.1.37/24")
	a, _ := ParseAddr("192.168.1.9")
	uassert.True(t, u.Contains(a), "an unmasked prefix still means its block")
}

func TestContainsPrefixAndOverlaps(t *testing.T) {
	eight, _ := ParsePrefix("10.0.0.0/8")
	sixteen, _ := ParsePrefix("10.1.0.0/16")
	other, _ := ParsePrefix("11.0.0.0/8")

	uassert.True(t, eight.ContainsPrefix(sixteen), "/8 holds its /16")
	uassert.False(t, sixteen.ContainsPrefix(eight), "a /16 cannot hold its /8")
	uassert.True(t, eight.ContainsPrefix(eight), "a prefix holds itself")
	uassert.False(t, eight.ContainsPrefix(other), "11/8 is elsewhere")

	uassert.True(t, eight.Overlaps(sixteen), "overlap is symmetric, wide side")
	uassert.True(t, sixteen.Overlaps(eight), "overlap is symmetric, narrow side")
	uassert.False(t, eight.Overlaps(other), "disjoint blocks do not overlap")

	d, _ := ParsePrefix("0.0.0.0/0")
	uassert.True(t, d.Overlaps(other), "the default route overlaps everything")
}

func TestClassify(t *testing.T) {
	tests := []struct {
		in   string
		name string
		ok   bool
	}{
		{"10.1.2.3", "private-use", true},
		{"172.16.0.1", "private-use", true},
		{"172.32.0.1", "", false}, // just past 172.16/12
		{"192.168.0.1", "private-use", true},
		{"127.0.0.1", "loopback", true},
		{"169.254.1.1", "link-local", true},
		{"100.64.0.1", "shared address space", true},
		{"224.0.0.1", "multicast", true},
		{"203.0.113.9", "documentation (TEST-NET-3)", true},
		{"0.0.0.0", "this network", true},
		{"8.8.8.8", "", false},
		{"1.1.1.1", "", false},
	}
	for _, tt := range tests {
		a, _ := ParseAddr(tt.in)
		b, ok := Classify(a)
		uassert.Equal(t, tt.ok, ok, "classified "+tt.in)
		uassert.Equal(t, tt.name, b.Name, "name for "+tt.in)
	}
}

// TestClassifyPrefersTheMostSpecificBlock pins the one case where two entries
// of the table both match: 255.255.255.255 is inside 240.0.0.0/4 as well as
// being the limited broadcast address.
func TestClassifyPrefersTheMostSpecificBlock(t *testing.T) {
	b, ok := Classify(4294967295)
	uassert.True(t, ok, "255.255.255.255 is special")
	uassert.Equal(t, "limited broadcast", b.Name)
	uassert.Equal(t, 32, b.Prefix.Bits())

	r, ok := Classify(AddrFrom4(240, 0, 0, 1))
	uassert.True(t, ok, "240/4 is reserved")
	uassert.Equal(t, "reserved", r.Name)
}

func TestPredicates(t *testing.T) {
	type want struct {
		unspecified, loopback, private, linkLocal, multicast, broadcast, global bool
	}
	tests := []struct {
		in string
		w  want
	}{
		{"0.0.0.0", want{unspecified: true}},
		{"127.0.0.1", want{loopback: true}},
		{"10.0.0.1", want{private: true}},
		{"172.16.5.4", want{private: true}},
		{"172.15.5.4", want{global: true}},
		{"192.168.0.1", want{private: true}},
		{"169.254.0.1", want{linkLocal: true}},
		{"239.255.255.250", want{multicast: true}},
		{"255.255.255.255", want{broadcast: true}},
		{"8.8.8.8", want{global: true}},
	}
	for _, tt := range tests {
		a, ok := ParseAddr(tt.in)
		uassert.True(t, ok, "parse "+tt.in)
		uassert.Equal(t, tt.w.unspecified, a.IsUnspecified(), "unspecified "+tt.in)
		uassert.Equal(t, tt.w.loopback, a.IsLoopback(), "loopback "+tt.in)
		uassert.Equal(t, tt.w.private, a.IsPrivate(), "private "+tt.in)
		uassert.Equal(t, tt.w.linkLocal, a.IsLinkLocal(), "link local "+tt.in)
		uassert.Equal(t, tt.w.multicast, a.IsMulticast(), "multicast "+tt.in)
		uassert.Equal(t, tt.w.broadcast, a.IsBroadcast(), "broadcast "+tt.in)
		uassert.Equal(t, tt.w.global, a.IsGlobalUnicast(), "global unicast "+tt.in)
	}
}

func TestSummarize(t *testing.T) {
	tests := []struct {
		name  string
		first string
		last  string
		want  []string
	}{
		{"single address", "10.0.0.7", "10.0.0.7", []string{"10.0.0.7/32"}},
		{"an aligned block comes back whole", "10.0.0.0", "10.0.0.255", []string{"10.0.0.0/24"}},
		{"the classic ragged range", "10.0.0.5", "10.0.0.20", []string{
			"10.0.0.5/32", "10.0.0.6/31", "10.0.0.8/29", "10.0.0.16/30", "10.0.0.20/32",
		}},
		{"off by one at the end", "192.168.0.0", "192.168.0.254", []string{
			"192.168.0.0/25", "192.168.0.128/26", "192.168.0.192/27", "192.168.0.224/28",
			"192.168.0.240/29", "192.168.0.248/30", "192.168.0.252/31", "192.168.0.254/32",
		}},
		{"the whole space is one prefix", "0.0.0.0", "255.255.255.255", []string{"0.0.0.0/0"}},
		{"the top of the space does not wrap", "255.255.255.252", "255.255.255.255", []string{"255.255.255.252/30"}},
		{"reversed is empty", "10.0.0.20", "10.0.0.5", []string{}},
	}
	for _, tt := range tests {
		first, _ := ParseAddr(tt.first)
		last, _ := ParseAddr(tt.last)
		got := Summarize(first, last)
		uassert.Equal(t, len(tt.want), len(got), "block count for "+tt.name)
		if len(tt.want) != len(got) {
			continue
		}
		for i := range got {
			uassert.Equal(t, tt.want[i], got[i].String(), "block for "+tt.name)
		}
	}
}

// TestSummarizeCoversExactlyTheRange is the property behind the table: the
// blocks tile the range with no gap, no overlap and nothing outside it.
func TestSummarizeCoversExactlyTheRange(t *testing.T) {
	first := AddrFrom4(172, 16, 3, 77)
	last := AddrFrom4(172, 16, 9, 200)
	blocks := Summarize(first, last)
	uassert.True(t, len(blocks) > 1, "this range needs several blocks")

	cursor := uint64(first)
	total := uint64(0)
	for _, b := range blocks {
		uassert.Equal(t, cursor, uint64(b.First()), "a block starts where the last one ended")
		uassert.True(t, b.IsMasked(), "every summarized block is aligned")
		total += b.Count()
		cursor = uint64(b.Last()) + 1
	}
	uassert.Equal(t, uint64(last)+1, cursor, "the blocks end exactly at last")
	uassert.Equal(t, uint64(last)-uint64(first)+1, total, "and cover the range exactly once")
}
