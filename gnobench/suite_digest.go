package main

// The digest suite: hashing and encoding, which is pure computation.
//
// Nothing here persists anything, so the storage column is zero throughout and
// the question is only gas: what one call costs, and what one byte costs. n is
// the input size in bytes rather than a number of entries, so the per-op
// column is per call and the interesting derived figure is gas per byte.
//
// Names are import paths, as everywhere: `crypto/sha256` is a gno standard
// library whose implementation is a native Go function the VM calls out to,
// `hash/adler32` is gno source the VM interprets, and that distinction is most
// of what the numbers show.

const digestTemplate = `// PKGPATH: gno.land/r/scratch/bench
package bench

import (
{{- range .Imports}}
	{{.}}
{{- end}}
)

// n is the input size in bytes.
const n = {{.N}}

{{.Decl}}

{{.Ops}}

// input is a deterministic xorshift64 byte stream, identical for every
// candidate and every size.
func input() []byte {
	b := make([]byte, n)
	s := uint64(0x9E3779B97F4A7C15)
	for i := 0; i < n; i++ {
		s ^= s << 13
		s ^= s >> 7
		s ^= s << 17
		b[i] = byte(s)
	}
	return b
}

func main() {
	data := input()
	_ = data
	acc := 0
	_ = acc

{{.Body}}
	println("done")
}

// Output:
// done
`

var digestStructures = []Structure{
	{
		Name:    "crypto/sha256",
		Group:   "digest",
		Note:    "a native function: the VM calls out to Go's implementation",
		Tags:    []string{"origin:stdlib", "impl:native", "kind:hash", "out:32B"},
		Imports: []string{`"crypto/sha256"`},
		Ops: `func opRun(b []byte) int {
	s := sha256.Sum256(b)
	return int(s[0]) + int(s[31])
}`,
	},
	{
		Name:    "crypto/keccak256",
		Group:   "digest",
		Note:    "a native function, the hash Ethereum tooling expects",
		Tags:    []string{"origin:stdlib", "impl:native", "kind:hash", "out:32B"},
		Imports: []string{`"crypto/keccak256"`},
		Ops: `func opRun(b []byte) int {
	s := keccak256.Sum256(b)
	return int(s[0]) + int(s[31])
}`,
	},
	{
		Name:    "hash/adler32",
		Group:   "digest",
		Note:    "gno source the VM interprets, not a native call: a checksum, not a hash",
		Tags:    []string{"origin:stdlib", "impl:interpreted", "kind:checksum", "out:4B"},
		Imports: []string{`"hash/adler32"`},
		Ops: `func opRun(b []byte) int {
	return int(adler32.Checksum(b))
}`,
	},
	{
		Name:    "encoding/hex",
		Group:   "digest",
		Note:    "2 output bytes per input byte",
		Tags:    []string{"origin:stdlib", "impl:interpreted", "kind:encode", "out:2x"},
		Imports: []string{`"encoding/hex"`},
		Ops: `func opRun(b []byte) int {
	return len(hex.EncodeToString(b))
}`,
	},
	{
		Name:    "encoding/base64",
		Group:   "digest",
		Note:    "4 output bytes per 3 input bytes",
		Tags:    []string{"origin:stdlib", "impl:interpreted", "kind:encode", "out:1.33x"},
		Imports: []string{`"encoding/base64"`},
		Ops: `func opRun(b []byte) int {
	return len(base64.StdEncoding.EncodeToString(b))
}`,
	},
	{
		Name:    "encoding/base32",
		Group:   "digest",
		Note:    "8 output bytes per 5 input bytes",
		Tags:    []string{"origin:stdlib", "impl:interpreted", "kind:encode", "out:1.6x"},
		Imports: []string{`"encoding/base32"`},
		Ops: `func opRun(b []byte) int {
	return len(base32.StdEncoding.EncodeToString(b))
}`,
	},
	{
		Name:    "strconv (hand-rolled hex)",
		Group:   "digest",
		Note:    "the hand-rolled version a realm writes when it does not know encoding/hex exists",
		Tags:    []string{"origin:stdlib", "impl:interpreted", "kind:encode", "out:2x"},
		Imports: []string{`"strconv"`},
		Ops: `func opRun(b []byte) int {
	out := ""
	for i := 0; i < len(b); i++ {
		s := strconv.FormatUint(uint64(b[i]), 16)
		if len(s) < 2 {
			s = "0" + s
		}
		out += s
	}
	return len(out)
}`,
	},
}

var digestWorkloads = []Workload{
	{
		Name: "base", Group: "digest", Baseline: "",
		Note: "building the input and calling nothing: the floor this suite subtracts",
		Body: "\tif len(data) != n {\n\t\tpanic(\"input\")\n\t}\n",
		Ops:  one,
	},
	{
		Name: "once", Group: "digest", Baseline: "base",
		Note: "ONE call on the whole n-byte input",
		Body: `	acc += opRun(data)
	if acc == 0 && n > 0 {
		panic("acc")
	}
`,
		Ops: one,
	},
	{
		Name: "x64", Group: "digest", Baseline: "base",
		Note: "64 calls on the same input: the per-call cost with the input build amortised away",
		Body: `	for i := 0; i < 64; i++ {
		acc += opRun(data)
	}
	if acc == 0 && n > 0 {
		panic("acc")
	}
`,
		Ops: func(n int) int { return 64 },
	},
	{
		Name: "chunked32", Group: "digest", Baseline: "base",
		Note: "the same n bytes in 32-byte calls: what a per-item loop costs against one bulk call",
		Body: `	for off := 0; off+32 <= n; off += 32 {
		acc += opRun(data[off : off+32])
	}
	if n >= 32 && acc == 0 {
		panic("acc")
	}
`,
		Ops: func(n int) int {
			if n < 32 {
				return 1
			}
			return n / 32
		},
	},
}

func init() {
	register(&Suite{
		Name:  "digest",
		Title: "Hashing and encoding a realm's bytes",
		Blurb: "Digests and encoders a gno realm can call, measured on gas alone: nothing here " +
			"persists anything. n is the input size in bytes. The axis that matters is whether the " +
			"implementation is a native call the VM makes out to Go, or gno source the VM interprets.",
		Structures: digestStructures,
		Workloads:  digestWorkloads,
		Template:   digestTemplate,
		SizeLabel:  "input bytes",
		OpLabel:    "call",
		Facets: []Facet{
			{Key: "impl", Label: "Implementation", Values: []string{"native", "interpreted"}},
			{Key: "kind", Label: "What it does", Values: []string{"hash", "checksum", "encode"}},
			{Key: "origin", Label: "Where it comes from", Values: []string{"stdlib", "p/nt", "p/moul"}},
		},
	})
}
