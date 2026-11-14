// Package hmacdemo is a small gnoweb demo of the HMAC-SHA-256 construction
// provided by the [p/moul/x/daily/hmac](/p/moul/x/daily/hmac/v0) library.
//
// It contains no cryptography of its own. Every tag on the page is computed
// while the page renders, including the RFC 4231 conformance column, so the
// page is a measurement of the library rather than a claim about it.
//
// Stateless, so Render is deterministic.
package hmacdemo

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/hmac/v0"
)

// demoKey is printed on this page, which is the point: a realm cannot keep a
// secret, so nothing here is authenticated. The library is.
const demoKey = "moul"

const demoMessage = "gno.land"

// vector is one RFC 4231 test case, with the published tag it has to match.
type vector struct {
	label string
	key   []byte
	msg   []byte
	want  string
}

// vectors returns the five RFC 4231 cases that exercise a distinct property,
// in the RFC's own numbering. Cases 4, 6 and 7 are the interesting ones: 4 has
// a key that is not a run of one byte, and 6 and 7 are longer than SHA-256's
// 64-byte block and so are folded into their own digest before use.
func vectors() []vector {
	return []vector{
		{"1", rep(0x0b, 20), []byte("Hi There"), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"},
		{"2", []byte("Jefe"), []byte("what do ya want for nothing?"), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"},
		{"3", rep(0xaa, 20), rep(0xdd, 50), "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"},
		{"6", rep(0xaa, 131), []byte("Test Using Larger Than Block-Size Key - Hash Key First"), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"},
		{"7", rep(0xaa, 131), longData, "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"},
	}
}

var longData = []byte("This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.")

func rep(b byte, n int) []byte {
	out := make([]byte, n)
	for i := range out {
		out[i] = b
	}
	return out
}

// Render renders the demo for gnoweb.
//
//	Render("")        / Render("/")  -> the conformance table and the two traps
//	Render("/<text>")                -> tag <text> under the public demo key
func Render(path string) string {
	if in := arg(path); in != "" {
		return tagPage(in)
	}

	var b strings.Builder
	b.WriteString("# HMAC-SHA-256\n\n")
	b.WriteString("Keyed message authentication, demoing the ")
	b.WriteString("[`p/moul/x/daily/hmac`](/p/moul/x/daily/hmac/v0) library. ")
	b.WriteString("Every tag below is computed while this page renders.\n\n")

	b.WriteString("## RFC 4231, checked here\n\n")
	t := ui.NewTable("case", "key", "message", "tag", "matches")
	for _, v := range vectors() {
		got := hex.EncodeToString(hmac.SumSHA256(v.key, v.msg))
		mark := "no"
		if got == v.want {
			mark = "yes"
		}
		t.Row(v.label, size(len(v.key)), size(len(v.msg)), "`"+got+"`", mark)
	}
	b.WriteString(t.String())
	b.WriteString("\nEvery row has to say yes. One saying no means this chain is ")
	b.WriteString("serving a library that is not HMAC.\n\n")

	b.WriteString("## Two different keys, one tag\n\n")
	long := rep(0xaa, 131)
	folded := hmac.SHA256(long)
	a := hex.EncodeToString(hmac.SumSHA256(long, []byte(demoMessage)))
	c := hex.EncodeToString(hmac.SumSHA256(folded, []byte(demoMessage)))
	k := ui.NewTable("key", "bytes", "tag")
	k.Row("131 copies of `0xaa`", "131", "`"+a+"`")
	k.Row("its SHA-256", "32", "`"+c+"`")
	b.WriteString(k.String())
	b.WriteString("\nA key longer than the 64-byte block is replaced by its own ")
	b.WriteString("digest before use, so those two keys are the same key. ")
	b.WriteString("Equal: **" + yesNo(a == c) + "**. The mirror of this rule is that a ")
	b.WriteString("short key is zero-padded, so `moul` and `moul` followed by zeros ")
	b.WriteString("are also one key. Pick keys of exactly 32 random bytes and ")
	b.WriteString("neither collision class can reach you.\n\n")

	b.WriteString("## Why not sha256(key + message)\n\n")
	naive := sha256.Sum256([]byte(demoKey + demoMessage))
	n := ui.NewTable("construction", "tag")
	n.Row("`hmac(key, message)`", "`"+hmac.HexSHA256(demoKey, demoMessage)+"`")
	n.Row("`sha256(key + message)`", "`"+hex.EncodeToString(naive[:])+"`")
	b.WriteString(n.String())
	b.WriteString("\nBoth are 32 bytes and both change when either input changes, ")
	b.WriteString("which is why the second one gets written. It is not a MAC: ")
	b.WriteString("SHA-256 publishes its internal state as its output, so a holder ")
	b.WriteString("of one valid tag can append to the message and produce a valid ")
	b.WriteString("tag for the longer message without ever learning the key. HMAC ")
	b.WriteString("hashes twice and the extensible digest never leaves the ")
	b.WriteString("function.\n\n")

	b.WriteString("## Tag your own\n\n")
	b.WriteString("Append any text to the path to tag it under the key ")
	b.WriteString(md.InlineCode(demoKey) + ", which is written here in public ")
	b.WriteString("because a realm cannot hold a secret:\n\n")
	b.WriteString("[`/gno.land`](/r/moul/x/daily/hmacdemo/v0:/" + demoMessage + ") or any other text.\n")
	return b.String()
}

func tagPage(in string) string {
	var b strings.Builder
	b.WriteString("# HMAC-SHA-256\n\n")
	b.WriteString("Key " + md.InlineCode(demoKey) + ", message " + md.InlineCode(in) + ".\n\n")
	b.WriteString("`" + hmac.HexSHA256(demoKey, in) + "`\n\n")
	b.WriteString("[back to the demo](/r/moul/x/daily/hmacdemo/v0)\n")
	return b.String()
}

// size describes a length the way the RFC's own table does, in bytes, because
// printing 131 raw bytes of key into a cell says less than the number does.
func size(n int) string {
	if n == 1 {
		return "1 byte"
	}
	return ufmtInt(n) + " bytes"
}

func yesNo(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}

// ufmtInt formats a non-negative int without reaching for a formatting
// package for one call.
func ufmtInt(n int) string {
	if n == 0 {
		return "0"
	}
	var digits []byte
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	return string(digits)
}

func arg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	s = strings.TrimPrefix(s, ":")
	return s
}
