// Package ipaddrdemo is a small gnoweb demo of the
// [p/moul/x/daily/ipaddr](/p/moul/x/daily/ipaddr/v0) library: it prints the
// IANA special-purpose registry with each block's real bounds, opens one
// prefix up field by field, and shows what a range that is not a prefix costs
// in CIDR blocks.
//
// It contains no addressing logic of its own. Stateless, so Render is
// deterministic.
package ipaddrdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/ipaddr/v0"
)

// opened is the prefix the Inside section takes apart. A /24 written with a
// host octet rather than its network address, so the page shows the masking
// happening rather than describing it.
const opened = "192.168.1.37/24"

// rangeFirst and rangeLast bound the range the last section summarizes. Five
// blocks, which is enough to show the widen-then-narrow shape and short
// enough to read.
const (
	rangeFirst = "10.0.0.5"
	rangeLast  = "10.0.0.20"
)

// Render renders the demo for gnoweb.
//
//	Render("")                 / Render("/") -> the registry, one prefix, one range
//	Render("/<a.b.c.d>")                     -> what that address is
//	Render("/<a.b.c.d>/<bits>")              -> what that block is
//	Render("/<first>-<last>")                -> the range as CIDR blocks
func Render(path string) string {
	if q := strings.TrimPrefix(strings.TrimSpace(path), "/"); q != "" {
		return header() + query(q) + "\n[← back](/r/moul/x/daily/ipaddrdemo/v0)\n"
	}

	var b strings.Builder
	b.WriteString(header())

	b.WriteString("## Special-purpose blocks\n\n")
	bt := ui.NewTable("prefix", "what it is", "RFC", "first", "last", "addresses")
	for _, blk := range ipaddr.SpecialBlocks {
		bt.Row(
			md.InlineCode(blk.Prefix.String()),
			blk.Name,
			blk.RFC,
			blk.Prefix.First().String(),
			blk.Prefix.Last().String(),
			strconv.FormatUint(blk.Prefix.Count(), 10),
		)
	}
	b.WriteString(bt.String())
	b.WriteString("\nEverything not in that table is ordinary public unicast space. ")
	b.WriteString("Three of the rows are the RFC 1918 blocks, and the middle one is ")
	b.WriteString("the trap: 172.16.0.0/12 runs to 172.31.255.255, so `172.32.0.1` ")
	b.WriteString("is a public address that a hand-written check on the second ")
	b.WriteString("octet usually swallows.\n\n")

	b.WriteString("## Inside one prefix\n\n")
	p, _ := ipaddr.ParsePrefix(opened)
	b.WriteString(md.InlineCode(opened) + ", which is written with a host octet rather ")
	b.WriteString("than its network address:\n\n")
	b.WriteString(prefixTable(p))

	b.WriteString("\n## A range is almost never a prefix\n\n")
	first, _ := ipaddr.ParseAddr(rangeFirst)
	last, _ := ipaddr.ParseAddr(rangeLast)
	b.WriteString(md.InlineCode(rangeFirst+" - "+rangeLast) + " is 16 addresses and takes five blocks:\n\n")
	b.WriteString(summaryTable(first, last))
	b.WriteString("\nThe blocks widen and then narrow again because each one has to ")
	b.WriteString("start on its own alignment: an address ending in 5 can only begin ")
	b.WriteString("a /32, while 10.0.0.8 can begin a /29.\n\n")

	b.WriteString("Append a query to ask about your own: ")
	b.WriteString("[`/8.8.8.8`](/r/moul/x/daily/ipaddrdemo/v0:8.8.8.8), ")
	b.WriteString("[`/172.16.0.0/12`](/r/moul/x/daily/ipaddrdemo/v0:172.16.0.0/12), ")
	b.WriteString("[`/10.0.0.5-10.0.0.20`](/r/moul/x/daily/ipaddrdemo/v0:10.0.0.5-10.0.0.20)\n\n")
	b.WriteString("> ℹ️ **IPv4 only, and the parser is strict.** A leading zero ")
	b.WriteString("in an octet is rejected rather than read as octal, because ")
	b.WriteString("`010.0.0.1` is 10.0.0.1 to a browser and 8.0.0.1 to the C library, ")
	b.WriteString("and an allowlist that picks one reading disagrees with whatever ")
	b.WriteString("picked the other.\n")
	return b.String()
}

// header is the title and standfirst, shared by both views.
func header() string {
	return "# IPv4 addressing\n\n" +
		"Addresses and CIDR blocks as integer arithmetic, demoing the " +
		"[`p/moul/x/daily/ipaddr`](/p/moul/x/daily/ipaddr/v0) library.\n\n"
}

// query dispatches on the shape of the caller's text: a dash means a range,
// a slash means a prefix, anything else is read as a single address.
func query(q string) string {
	if i := strings.Index(q, "-"); i >= 0 {
		return rangeView(q[:i], q[i+1:])
	}
	if strings.Contains(q, "/") {
		p, ok := ipaddr.ParsePrefix(q)
		if !ok {
			return rejected(q, "not a CIDR prefix")
		}
		return "## " + md.InlineCode(p.String()) + "\n\n" + prefixTable(p)
	}
	a, ok := ipaddr.ParseAddr(q)
	if !ok {
		return rejected(q, "not a dotted-quad IPv4 address")
	}
	return "## " + md.InlineCode(a.String()) + "\n\n" + addrTable(a)
}

// rangeView summarizes first..last, once both halves parse.
func rangeView(fs, ls string) string {
	first, ok := ipaddr.ParseAddr(strings.TrimSpace(fs))
	if !ok {
		return rejected(fs, "not a dotted-quad IPv4 address")
	}
	last, ok := ipaddr.ParseAddr(strings.TrimSpace(ls))
	if !ok {
		return rejected(ls, "not a dotted-quad IPv4 address")
	}
	if first > last {
		return "## " + md.InlineCode(first.String()+" - "+last.String()) + "\n\n" +
			"That range runs backwards, so it covers nothing.\n"
	}
	return "## " + md.InlineCode(first.String()+" - "+last.String()) + "\n\n" +
		strconv.FormatUint(uint64(last)-uint64(first)+1, 10) + " addresses:\n\n" +
		summaryTable(first, last)
}

// rejected reports a query the library would not parse. The text is the
// caller's, so it goes through ui.Inline rather than into a code span, which
// a backtick in it could close.
func rejected(q, why string) string {
	return "## Not parsed\n\n" + ui.Inline(q) + " is " + why + ".\n"
}

// prefixTable is one block, field by field.
func prefixTable(p ipaddr.Prefix) string {
	t := ui.NewTable("field", "value", "")
	t.Row("as written", p.String(), maskedNote(p))
	t.Row("network", p.First().String(), "the block's canonical name")
	t.Row("netmask", p.Mask().String(), "/"+strconv.Itoa(p.Bits()))
	t.Row("first", p.First().String(), "")
	t.Row("last", p.Last().String(), broadcastNote(p))
	t.Row("addresses", strconv.FormatUint(p.Count(), 10), "")
	t.Row("usable hosts", strconv.FormatUint(p.Usable(), 10), usableNote(p))
	t.Row("classification", classify(p.First()), "")
	return t.String()
}

// addrTable is one address, field by field.
func addrTable(a ipaddr.Addr) string {
	t := ui.NewTable("field", "value", "")
	t.Row("address", a.String(), "")
	t.Row("as a number", strconv.FormatUint(uint64(a), 10), "the 32 bits the four octets spell")
	t.Row("classification", classify(a), "")
	t.Row("routable", yesno(a.IsGlobalUnicast()), "on the public internet")
	t.Row("flags", flags(a), "")
	return t.String()
}

// summaryTable is the CIDR cover of a range.
func summaryTable(first, last ipaddr.Addr) string {
	t := ui.NewTable("#", "block", "first", "last", "addresses")
	for i, blk := range ipaddr.Summarize(first, last) {
		t.Row(
			strconv.Itoa(i+1),
			md.InlineCode(blk.String()),
			blk.First().String(),
			blk.Last().String(),
			strconv.FormatUint(blk.Count(), 10),
		)
	}
	return t.String()
}

// classify names the special-purpose block holding an address, or says it is
// ordinary space.
func classify(a ipaddr.Addr) string {
	b, special := ipaddr.Classify(a)
	if !special {
		return "public unicast"
	}
	return b.Name + " (" + b.RFC + ", " + b.Prefix.String() + ")"
}

// flags lists whichever predicates hold, which for a public address is none.
func flags(a ipaddr.Addr) string {
	out := []string{}
	if a.IsUnspecified() {
		out = append(out, "unspecified")
	}
	if a.IsLoopback() {
		out = append(out, "loopback")
	}
	if a.IsPrivate() {
		out = append(out, "private")
	}
	if a.IsLinkLocal() {
		out = append(out, "link-local")
	}
	if a.IsMulticast() {
		out = append(out, "multicast")
	}
	if a.IsBroadcast() {
		out = append(out, "broadcast")
	}
	if len(out) == 0 {
		return "none"
	}
	return strings.Join(out, ", ")
}

// maskedNote says whether the prefix was written canonically.
func maskedNote(p ipaddr.Prefix) string {
	if p.IsMasked() {
		return "already the network address"
	}
	return "kept as given, not rewritten"
}

// broadcastNote names the last address for the prefixes that have one.
func broadcastNote(p ipaddr.Prefix) string {
	if p.Bits() >= 31 {
		return ""
	}
	return "the subnet broadcast address"
}

// usableNote explains the two prefix lengths where hosts are not count-2.
func usableNote(p ipaddr.Prefix) string {
	switch {
	case p.Bits() == 32:
		return "a single host, nothing to subtract"
	case p.Bits() == 31:
		return "a point-to-point link, both ends are hosts (RFC 3021)"
	default:
		return "network and broadcast addresses removed"
	}
}

// yesno renders a bool for a table cell.
func yesno(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
