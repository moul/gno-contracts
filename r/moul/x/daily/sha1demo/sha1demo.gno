// Package sha1demo is a small gnoweb demo of the SHA-1 implementation provided
// by the [p/moul/x/daily/sha1](/p/moul/x/daily/sha1/v0) library: the published
// test vectors, the git object ids anyone can check with `git hash-object`,
// the RFC 2202 HMAC vectors, and a path that hashes whatever you give it.
//
// It contains no hashing logic of its own. Stateless, so Render is
// deterministic.
package sha1demo

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/sha1/v0"
)

// vectors are the published FIPS 180-1 / RFC 3174 answers, so the page doubles
// as a conformance test.
var vectors = []string{"", "a", "abc", "message digest", "hello world", "hello worle"}

// blobs are checkable from a terminal: `printf '%s' <content> | git hash-object --stdin`.
var blobs = []string{"", "hello world\n", "Hello World\n"}

// macs are the first three RFC 2202 HMAC-SHA1 test cases, written with keys
// that print, so the table is readable.
var macs = []struct{ key, msg string }{
	{"Jefe", "what do ya want for nothing?"},
	{"key", "The quick brown fox jumps over the lazy dog"},
	{"", ""},
}

// Render renders the demo for gnoweb.
//
//	Render("")       / Render("/") -> the vector tables
//	Render("/<text>")              -> hash that text
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# SHA-1\n\n")
	b.WriteString("Forty hex digits from any amount of input, demoing the ")
	b.WriteString("[`p/moul/x/daily/sha1`](/p/moul/x/daily/sha1/v0) library.\n\n")

	if in := parseArg(path); in != "" {
		b.WriteString("## " + ui.Inline(in) + "\n\n")
		t := ui.NewTable("what", "value")
		t.Row("sha1", md.InlineCode(sha1.SumHex(in)))
		t.Row("git blob id", md.InlineCode(sha1.GitBlobID(in)))
		t.Row("bytes", md.InlineCode(itoa(len(in))))
		b.WriteString(t.String() + "\n")
		b.WriteString("The git id is not the hash of the content: it is the hash ")
		b.WriteString("of `blob <len>\\x00<content>`, which is why the two rows ")
		b.WriteString("never agree.\n")
		return b.String()
	}

	b.WriteString("## Published vectors\n\n")
	vt := ui.NewTable("input", "sha1")
	for _, s := range vectors {
		label := "_(empty)_"
		if s != "" {
			label = md.InlineCode(s)
		}
		vt.Row(label, md.InlineCode(sha1.SumHex(s)))
	}
	b.WriteString(vt.String() + "\n")
	b.WriteString("The empty string and `abc` are the FIPS 180-1 answers every ")
	b.WriteString("implementation is checked against. The last two rows differ ")
	b.WriteString("by one letter and share no prefix: that avalanche is the ")
	b.WriteString("property worth seeing.\n\n")

	b.WriteString("## git object ids\n\n")
	bt := ui.NewTable("content", "git hash-object")
	for _, s := range blobs {
		label := "_(empty file)_"
		if s != "" {
			// Show the trailing newline as an escape rather than the byte:
			// a real newline would fold into the row above it.
			label = md.InlineCode(strings.TrimSuffix(s, "\n") + "\\n")
		}
		bt.Row(label, md.InlineCode(sha1.GitBlobID(s)))
	}
	b.WriteString(bt.String() + "\n")
	b.WriteString("`e69de29b` is the id of the empty file, the one hash a git ")
	b.WriteString("user can recognise on sight. Every row matches ")
	b.WriteString("`git hash-object`, because the header git prepends is the ")
	b.WriteString("whole difference between a blob id and a content hash.\n\n")

	b.WriteString("## HMAC-SHA1\n\n")
	mt := ui.NewTable("key", "message", "hmac")
	for _, m := range macs {
		key, msg := "_(empty)_", "_(empty)_"
		if m.key != "" {
			key = md.InlineCode(m.key)
		}
		if m.msg != "" {
			msg = md.InlineCode(m.msg)
		}
		mt.Row(key, msg, md.InlineCode(sha1.HMACHex(m.key, m.msg)))
	}
	b.WriteString(mt.String() + "\n")
	b.WriteString("Row one is RFC 2202 test case 2. A key longer than the ")
	b.WriteString("64-byte block is hashed down first, so a long key and its ")
	b.WriteString("own digest are the same key.\n\n")

	b.WriteString("## Hash your own\n\n")
	b.WriteString("`/r/moul/x/daily/sha1demo/v0:your text here`\n\n")
	b.WriteString("> ⚠️ **SHA-1 is broken as a collision-resistant hash.** ")
	b.WriteString("SHAttered produced two different PDFs with the same digest ")
	b.WriteString("in 2017, and a chosen-prefix collision followed in 2020. ")
	b.WriteString("Never use it to decide that two documents are the same ")
	b.WriteString("document. It is still the only correct answer where a format ")
	b.WriteString("specifies it: git ids, HMAC-SHA1 in TOTP, legacy interop.\n")
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

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
