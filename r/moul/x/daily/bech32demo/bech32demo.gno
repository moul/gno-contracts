// Package bech32demo is a small gnoweb demo of the Bech32 and Bech32m codec
// provided by the [p/moul/x/daily/bech32](/p/moul/x/daily/bech32/v0) library:
// it takes a real gno.land address apart, shows the BIP-173 and BIP-350 test
// vectors side by side, and reproduces the length-extension weakness that is
// the whole reason the second variant exists.
//
// It contains no codec logic of its own. Stateless, so Render is deterministic.
package bech32demo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/bech32/v0"
	"gno.land/p/moul/x/daily/hexdump/v0"
)

// sample is a real mainnet address: human-readable part "g", 20 payload bytes.
const sample = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"

// The BIP-173 (Bech32) and BIP-350 (Bech32m) test vectors, paired by shape so
// the only difference on each row is the six-character checksum.
var vectors = [][2]string{
	{"a12uel5l", "a1lqfn3a"},
	{"?1ezyfcl", "?1v759aa"},
	{
		"split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
		"split1checkupstagehandshakeupstreamerranterredcaperredlc445v",
	},
}

// The insertion that Bech32 accepts and Bech32m refuses. Both strings below
// carry a checksum Bech32 verifies; only the second has the extra "q".
const (
	extBase     = "a1q3g6mnsp"
	extInserted = "a1q3g6mnsqp"
	extMBase    = "a1q6dp699p"
	extMInsert  = "a1q6dp699qp"
)

// Render renders the demo for gnoweb.
//
//	Render("")        / Render("/")  -> the full demo
//	Render("/<string>")              -> decode that string
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Bech32\n\n")
	b.WriteString("Addresses that carry their own error-detecting checksum, demoing the ")
	b.WriteString("[`p/moul/x/daily/bech32`](/p/moul/x/daily/bech32/v0) library.\n\n")

	if in := parseArg(path); in != "" {
		b.WriteString(decodeOne(in))
		return b.String()
	}

	b.WriteString("## A gno.land address, taken apart\n\n")
	b.WriteString(decodeOne(sample))

	b.WriteString("\n## The two variants\n\n")
	b.WriteString("Same string shape, same data, different checksum constant: ")
	b.WriteString("`1` for Bech32, `0x2bc830a3` for Bech32m.\n\n")
	vt := ui.NewTable("Bech32 (BIP-173)", "Bech32m (BIP-350)")
	for _, pair := range vectors {
		vt.Row(md.InlineCode(pair[0]), md.InlineCode(pair[1]))
	}
	b.WriteString(vt.String() + "\n")

	b.WriteString("## Why Bech32m exists\n\n")
	b.WriteString("A Bech32 string ending in `p` keeps a valid checksum when `q` ")
	b.WriteString("characters are inserted in front of that final `p`, so a reader ")
	b.WriteString("accepts a string nobody wrote. Bech32m's constant closes it:\n\n")
	wt := ui.NewTable("string", "variant", "verdict")
	for _, s := range []string{extBase, extInserted, extMBase, extMInsert} {
		_, _, v, err := bech32.Decode(s)
		if err != nil {
			wt.Row(md.InlineCode(s), "-", "rejected: "+err.Error())
			continue
		}
		wt.Row(md.InlineCode(s), v.String(), "accepted")
	}
	b.WriteString(wt.String() + "\n")

	b.WriteString("Pass a string of your own to decode it: ")
	b.WriteString("`Render(\"/<bech32 string>\")`.\n")
	return b.String()
}

// decodeOne renders one string's decode. Everything derived from the input is
// escaped: the argument reaches this realm from whoever typed the url.
func decodeOne(in string) string {
	var b strings.Builder
	b.WriteString("Decoding " + ui.Inline(in) + ":\n\n")

	hrp, payload, variant, err := bech32.DecodeBytes(in)
	if err != nil {
		b.WriteString("> " + ui.Inline(err.Error()) + "\n")
		return b.String()
	}

	t := ui.NewTable("field", "value")
	// hrp bytes run the whole printable-ASCII range, so this cell is escaped,
	// and escaped text can never sit inside a code span.
	t.Row("human-readable part", ui.Cell(hrp))
	t.Row("variant", variant.String())
	t.Row("payload", strconv.Itoa(len(payload))+" bytes")
	t.Row("payload (hex)", md.InlineCode(hexOf(payload)))
	b.WriteString(t.String())
	return b.String()
}

// hexOf renders a payload through the hexdump library, which owns the digits.
func hexOf(payload []byte) string {
	var b strings.Builder
	for _, c := range payload {
		b.WriteString(hexdump.Hex(c))
	}
	return b.String()
}

// parseArg strips the one routing slash in front of the argument and returns
// the rest verbatim. Nothing else is removed: a slash is legal in a
// human-readable part, so cutting at one refuses a valid string, and trimming
// whitespace would render a clean decode of a string nobody typed.
func parseArg(path string) string {
	return strings.TrimPrefix(path, "/")
}
