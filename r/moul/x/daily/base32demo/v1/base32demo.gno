// Package base32demo is a small gnoweb demo of the base32 codec provided by the
// [p/moul/x/daily/base32](/p/moul/x/daily/base32/v1) library: it shows the RFC
// 4648 vectors alongside Crockford, and the forgiving decodes Crockford allows.
//
// It contains no codec logic of its own. Stateless, so Render is deterministic.
package base32demo

import (
	"strings"

	"gno.land/p/moul/x/daily/base32/v1"
)

// The RFC 4648 §10 vectors — every partial-group length.
var vectors = []string{"", "f", "fo", "foo", "foob", "fooba", "foobar"}

// Render renders the demo for gnoweb.
//
//	Render("")       / Render("/") -> the vectors + Crockford forgiveness
//	Render("/<text>")              -> encode that text both ways
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Base32\n\n")
	b.WriteString("RFC 4648 and Crockford, demoing the ")
	b.WriteString("[`p/moul/x/daily/base32`](/p/moul/x/daily/base32/v1) library.\n\n")

	if in := parseArg(path); in != "" {
		std, _ := base32.Encode(in)
		ck, _ := base32.EncodeCrockford(in)
		b.WriteString("## `")
		b.WriteString(in)
		b.WriteString("`\n\n- RFC 4648: `")
		b.WriteString(std)
		b.WriteString("`\n- Crockford: `")
		b.WriteString(ck)
		b.WriteString("`\n")
		return b.String()
	}

	b.WriteString("| input | RFC 4648 | Crockford |\n|---|---|---|\n")
	for _, v := range vectors {
		std, _ := base32.Encode(v)
		ck, _ := base32.EncodeCrockford(v)
		b.WriteString("| ")
		if v == "" {
			b.WriteString("_(empty)_")
		} else {
			b.WriteString("`" + v + "`")
		}
		b.WriteString(" | `")
		b.WriteString(std)
		b.WriteString("` | `")
		b.WriteString(ck)
		b.WriteString("` |\n")
	}

	b.WriteString("\n## Crockford forgives\n\n")
	enc, _ := base32.EncodeCrockford("hello")
	b.WriteString("`hello` encodes to `")
	b.WriteString(enc)
	b.WriteString("`, and all of these decode back to it:\n\n")
	variants := []string{enc, strings.ToLower(enc), enc[:2] + "-" + enc[2:]}
	for _, v := range variants {
		dec, err := base32.DecodeCrockford(v)
		b.WriteString("- `")
		b.WriteString(v)
		b.WriteString("` → ")
		if err == nil && dec == "hello" {
			b.WriteString("`hello` ✅")
		} else {
			b.WriteString("❌")
		}
		b.WriteString("\n")
	}
	b.WriteString("\n> Crockford folds case, reads `I`/`L` as `1` and `O` as `0`, and ")
	b.WriteString("ignores hyphens — so an identifier survives being read aloud and typed back. ")
	b.WriteString("`U` is left out of the alphabet on purpose.\n")
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
