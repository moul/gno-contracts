// Package bencodedemo is a small gnoweb demo of the bencode codec provided by
// the [p/moul/x/daily/bencode](/p/moul/x/daily/bencode/v0) library: the four
// types, the round trip that makes an infohash reproducible, and the
// non-canonical inputs the decoder refuses instead of tidying up.
//
// It contains no codec logic of its own. Stateless, so Render is
// deterministic: every figure below is computed from the fixed tables at the
// top of this file, never from chain state.
package bencodedemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/bencode/v0"
)

// samples are valid, canonical encodings, one per type plus the composites.
var samples = []string{
	"i42e",
	"i-7e",
	"4:spam",
	"0:",
	"li1ei2ei3ee",
	"d3:cow3:moo4:spam4:eggse",
}

// torrent is the shape the format exists for: a tracker announce beside an
// info dictionary whose re-encoding is what gets hashed.
const torrent = "d8:announce21:udp://tracker.example4:infod6:lengthi262144e4:name8:disk.img12:piece lengthi16384eee"

const backLink = "[back to the demo](/r/moul/x/daily/bencodedemo/v0)\n"

// MaxInput bounds what this page will decode. The library accepts up to
// bencode.MaxLen bytes, but a Render runs under the chain's query gas meter
// and gnoweb does not bound a render argument, so the page stops well short of
// the library's own limit. 512 bytes is more than anyone pastes by hand.
const MaxInput = 512

// rejected are inputs a sloppy decoder accepts and silently rewrites. Each one
// would change the digest of whatever contained it.
var rejected = []struct {
	in  string
	why string
}{
	{"i007e", "leading zeros in an integer"},
	{"i-0e", "negative zero"},
	{"03:abc", "leading zeros in a string length"},
	{"d4:spam4:eggs3:cow3:mooe", "dictionary keys out of order"},
	{"d3:cow3:moo3:cow3:mooe", "duplicate dictionary key"},
	{"i1ei2e", "a second value after the first"},
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/")        -> the types, the round trip, the refusals
//	Render("/<bencoded value>")     -> decode that input and show the tree
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Bencode\n\n")
	b.WriteString("The BitTorrent serialization format, demoing the ")
	b.WriteString("[`p/moul/x/daily/bencode`](/p/moul/x/daily/bencode/v0) library.\n\n")

	if in := parseArg(path); in != "" {
		b.WriteString("## Your input\n\n")
		if len(in) > MaxInput {
			b.WriteString(strconv.Itoa(len(in)) + " bytes. This page decodes at most ")
			b.WriteString(strconv.Itoa(MaxInput) + ".\n\n")
			b.WriteString(backLink)
			return b.String()
		}
		b.WriteString(ui.Inline(in) + "\n\n")
		v, err := bencode.Decode(in)
		if err != nil {
			b.WriteString("Rejected: " + ui.Inline(err.Error()) + "\n\n")
			b.WriteString(backLink)
			return b.String()
		}
		tree(&b, v, 0)
		b.WriteString("\nRe-encodes to " + ui.Inline(v.Encode()))
		if v.Encode() == in {
			b.WriteString(", byte for byte.\n\n")
		} else {
			b.WriteString(", which differs from the input.\n\n")
		}
		b.WriteString(backLink)
		return b.String()
	}

	b.WriteString("## The four types\n\n")
	tt := ui.NewTable("encoding", "kind", "reads as")
	for _, s := range samples {
		v, err := bencode.Decode(s)
		if err != nil {
			tt.Row("`"+s+"`", "error", err.Error())
			continue
		}
		tt.Row("`"+s+"`", v.Kind().String(), summarize(v))
	}
	b.WriteString(tt.String() + "\n")

	b.WriteString("## A torrent, decoded\n\n")
	t, err := bencode.Decode(torrent)
	if err != nil {
		b.WriteString("the sample failed to decode: " + ui.Inline(err.Error()) + "\n")
		return b.String()
	}
	tree(&b, t, 0)
	b.WriteString("\nThe `info` sub-dictionary re-encodes to ")
	info := t.Get("info")
	b.WriteString("`" + info.Encode() + "`, ")
	b.WriteString(strconv.Itoa(len(info.Encode())) + " bytes. ")
	b.WriteString("Hash those bytes and you have the infohash, which is why the ")
	b.WriteString("decoder is not allowed to tidy anything up on the way through.\n\n")

	b.WriteString("## What it refuses\n\n")
	rt := ui.NewTable("input", "why", "error")
	for _, r := range rejected {
		_, err := bencode.Decode(r.in)
		msg := "accepted"
		if err != nil {
			msg = err.Error()
		}
		rt.Row("`"+r.in+"`", r.why, msg)
	}
	b.WriteString(rt.String() + "\n")

	b.WriteString("> Every one of those parses. A decoder that accepted them ")
	b.WriteString("and re-emitted the canonical form would change the identity ")
	b.WriteString("of the document it was handed.\n\n")
	b.WriteString("Decode your own: ")
	b.WriteString("[`d3:cow3:mooe`](/r/moul/x/daily/bencodedemo/v0:d3:cow3:mooe)\n")
	return b.String()
}

// summarize describes a value in one cell, without recursing.
func summarize(v *bencode.Value) string {
	switch v.Kind() {
	case bencode.KindInt:
		return strconv.FormatInt(v.Int(), 10)
	case bencode.KindString:
		if v.Text() == "" {
			return "_(empty string)_"
		}
		return ui.Cell(v.Text())
	case bencode.KindList:
		return strconv.Itoa(v.Len()) + " item(s)"
	case bencode.KindDict:
		return strconv.Itoa(v.Len()) + " key(s): " + ui.Cell(strings.Join(v.Keys(), ", "))
	default:
		return "_(nothing)_"
	}
}

// tree writes a value as a nested markdown list. It takes the builder rather
// than returning a string: a dictionary of a few hundred entries is reachable
// inside MaxInput, and += over that many lines copies the page once per line.
func tree(b *strings.Builder, v *bencode.Value, depth int) {
	pad := strings.Repeat("  ", depth)
	switch v.Kind() {
	case bencode.KindList:
		b.WriteString(pad + "- list, " + strconv.Itoa(v.Len()) + " item(s)\n")
		for i := 0; i < v.Len(); i++ {
			tree(b, v.At(i), depth+1)
		}
	case bencode.KindDict:
		b.WriteString(pad + "- dict, " + strconv.Itoa(v.Len()) + " key(s)\n")
		for _, k := range v.Keys() {
			child := v.Get(k)
			if child.Kind() == bencode.KindList || child.Kind() == bencode.KindDict {
				b.WriteString(pad + "  - **" + ui.Inline(k) + "**:\n")
				tree(b, child, depth+2)
				continue
			}
			b.WriteString(pad + "  - **" + ui.Inline(k) + "**: " + leaf(child) + "\n")
		}
	default:
		b.WriteString(pad + "- " + leaf(v) + "\n")
	}
}

// leaf renders an int or a string as one line.
func leaf(v *bencode.Value) string {
	switch v.Kind() {
	case bencode.KindInt:
		return "int `" + strconv.FormatInt(v.Int(), 10) + "`"
	case bencode.KindString:
		if v.Text() == "" {
			return "string, empty"
		}
		return "string " + ui.Inline(v.Text())
	default:
		return "nothing"
	}
}

// parseArg takes the whole render path as the value to decode: a bencoded
// string contains colons and digits, and splitting on them would mangle it.
func parseArg(path string) string {
	return strings.TrimPrefix(strings.TrimSpace(path), "/")
}
