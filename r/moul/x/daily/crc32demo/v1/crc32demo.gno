// Package crc32demo is a small gnoweb demo of the CRC-32 checksum provided by
// the [p/moul/x/daily/crc32](/p/moul/x/daily/crc32/v1) library: it checksums a
// few strings and shows that a one-character change moves the result
// completely.
//
// It contains no checksum logic of its own. Stateless, so Render is
// deterministic.
package crc32demo

import (
	"strings"

	"gno.land/p/moul/x/daily/crc32/v1"
)

var samples = []string{"", "a", "abc", "123456789", "hello world", "hello worle"}

// Render renders the demo for gnoweb.
//
//	Render("")       / Render("/") -> the samples table
//	Render("/<text>")              -> checksum that text
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# CRC-32\n\n")
	b.WriteString("The IEEE checksum behind zip, gzip and PNG, demoing the ")
	b.WriteString("[`p/moul/x/daily/crc32`](/p/moul/x/daily/crc32/v1) library.\n\n")

	if in := parseArg(path); in != "" {
		b.WriteString("## `")
		b.WriteString(in)
		b.WriteString("`\n\n`")
		b.WriteString(crc32.ChecksumHex(in))
		b.WriteString("`\n")
		return b.String()
	}

	b.WriteString("| input | crc32 |\n|---|---|\n")
	for _, s := range samples {
		b.WriteString("| ")
		if s == "" {
			b.WriteString("_(empty)_")
		} else {
			b.WriteString("`" + s + "`")
		}
		b.WriteString(" | `")
		b.WriteString(crc32.ChecksumHex(s))
		b.WriteString("` |\n")
	}
	b.WriteString("\n`123456789` → `cbf43926` is the standard CRC-32 check value, ")
	b.WriteString("so this table doubles as a conformance test.\n\n")
	b.WriteString("> The last two rows differ by one letter and share no digits: ")
	b.WriteString("that avalanche is the point.\n\n")
	b.WriteString("> A CRC detects **accidents**, not tampering — it is linear, so a ")
	b.WriteString("matching message is easy to craft. Never authenticate with it.\n")
	return b.String()
}

func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
