// Package huffman compresses a string with canonical Huffman codes: the
// classic frequency-based prefix code, in the one form that is safe to put on
// a chain.
//
// Two properties matter here and neither is about compression.
//
// The codes are CANONICAL. A plain Huffman tree is not unique: two equally
// optimal trees give the same total bit count and different codes, and which
// one you get depends on how ties are broken while merging. Canonical codes
// throw the tree away and keep only the code LENGTHS, then re-derive the bits
// by sorting on (length, symbol). The same input therefore always produces the
// same table, which is what a deterministic Render and a reproducible payload
// both need, and the table a decoder has to carry shrinks to one length per
// symbol.
//
// Decoding VALIDATES. [Encoded] is a plain struct with exported fields, so a
// caller can build one by hand or read one out of storage, and a decoder that
// trusts what it is handed will happily return a string nobody ever encoded.
// [Encoded.Decode] rebuilds the canonical table from the lengths it was given,
// refuses a payload whose own Bits disagree with it, and checks the Kraft
// equality, the bit budget and the decoded size before returning.
//
// A live demo of this package is at
// [r/moul/x/daily/huffmandemo](/r/moul/x/daily/huffmandemo/v0).
package huffman

import (
	"errors"
	"strings"
)

// MaxLen bounds input so gas stays predictable.
const MaxLen = 4096

// maxCodeLen is the longest code this package will emit or accept.
//
// It is not arbitrary. The worst case for Huffman is a Fibonacci frequency
// distribution, where n symbols need a code of n-1 bits and the input has to
// be at least F(n+2) bytes long. F(34) is 5,702,887, so reaching 32 bits needs
// megabytes of input and [MaxLen] stops at 4096, which bounds a code here to
// 18 bits. The ceiling exists so the overflow is a returned error rather than
// a shift nobody checked.
const maxCodeLen = 32

var (
	// ErrEmpty is returned for an input with no bytes in it: there is no such
	// thing as a code for an empty alphabet.
	ErrEmpty = errors.New("huffman: empty input")
	// ErrTooLong is returned when input exceeds MaxLen.
	ErrTooLong = errors.New("huffman: input too long")
	// ErrTooDeep is returned when the optimal code would be longer than 32
	// bits. Unreachable at MaxLen, and returned rather than panicked because a
	// realm's Render can never be fixed once the path is published.
	ErrTooDeep = errors.New("huffman: code longer than 32 bits")
	// ErrCorrupt is returned by Decode when the payload is not one this
	// package could have produced.
	ErrCorrupt = errors.New("huffman: corrupt payload")
)

// Code is one symbol's canonical prefix code.
type Code struct {
	Symbol byte
	Len    int    // length in bits, 1 to 32
	Bits   uint32 // the code, right aligned, most significant bit first
}

// String renders the code as its bit pattern, "110" and not "6".
func (c Code) String() string {
	var b strings.Builder
	for i := c.Len - 1; i >= 0; i-- {
		if (c.Bits>>uint(i))&1 == 1 {
			b.WriteByte('1')
		} else {
			b.WriteByte('0')
		}
	}
	return b.String()
}

// Encoded is a compressed payload: the canonical table, which is the whole
// header a decoder needs, and the packed bit stream.
type Encoded struct {
	Codes []Code // sorted by (Len, Symbol)
	Data  []byte // the bit stream, most significant bit of each byte first
	NBits int    // significant bits in Data; the rest of the last byte is padding
	Size  int    // length of the original input, in bytes
}

// Saved reports how many bits the encoding removed, which is negative when the
// alphabet is flat enough that the codes cost more than the bytes did.
func (e *Encoded) Saved() int { return e.Size*8 - e.NBits }

// BitString renders the stream as '0' and '1', padding excluded. It is meant
// for demos and error messages: the result is NBits characters long.
func (e *Encoded) BitString() string {
	var b strings.Builder
	for i := 0; i < e.NBits && i/8 < len(e.Data); i++ {
		if (e.Data[i/8]>>uint(7-i%8))&1 == 1 {
			b.WriteByte('1')
		} else {
			b.WriteByte('0')
		}
	}
	return b.String()
}

// Table returns the canonical code table for s, sorted by (Len, Symbol),
// without encoding anything.
func Table(s string) ([]Code, error) {
	if len(s) > MaxLen {
		return nil, ErrTooLong
	}
	if len(s) == 0 {
		return nil, ErrEmpty
	}

	var freq [256]int
	for i := 0; i < len(s); i++ {
		freq[s[i]]++
	}

	lengths, err := codeLengths(freq)
	if err != nil {
		return nil, err
	}

	codes := make([]Code, 0, len(lengths))
	for _, l := range lengths {
		codes = append(codes, Code{Symbol: l.Symbol, Len: l.Len})
	}
	sortCodes(codes)
	assignCanonical(codes)
	return codes, nil
}

// Encode builds the canonical table for s and packs s with it.
func Encode(s string) (*Encoded, error) {
	codes, err := Table(s)
	if err != nil {
		return nil, err
	}

	var (
		byLen    [256]int
		byBits   [256]uint32
		declared [256]bool
	)
	for _, c := range codes {
		byLen[c.Symbol] = c.Len
		byBits[c.Symbol] = c.Bits
		declared[c.Symbol] = true
	}

	e := &Encoded{Codes: codes, Size: len(s)}
	for i := 0; i < len(s); i++ {
		sym := s[i]
		if !declared[sym] {
			// Unreachable: the table is built from this very string.
			return nil, ErrCorrupt
		}
		e.writeBits(byBits[sym], byLen[sym])
	}
	return e, nil
}

// writeBits appends the low n bits of v to the stream, most significant first.
func (e *Encoded) writeBits(v uint32, n int) {
	for i := n - 1; i >= 0; i-- {
		if e.NBits%8 == 0 {
			e.Data = append(e.Data, 0)
		}
		if (v>>uint(i))&1 == 1 {
			e.Data[e.NBits/8] |= 1 << uint(7-e.NBits%8)
		}
		e.NBits++
	}
}

// Decode validates the payload and returns the original string.
//
// Everything it checks is something a hand-built or storage-read Encoded can
// get wrong: an empty or over-long table, a zero length, a table out of
// canonical order, a repeated symbol, Bits that disagree with the lengths, a
// code set that is not a complete prefix code, a zero-bit or zero-size
// payload, a Data slice that is not exactly the bytes NBits needs, nonzero
// padding in the last byte, a stream ending mid-code, and a decoded length
// that is not Size.
func (e *Encoded) Decode() (string, error) {
	if len(e.Codes) == 0 || len(e.Codes) > 256 || e.NBits < 1 || e.Size < 1 {
		// Encode refuses an empty input, so a zero-bit or zero-size payload
		// is not one this package produced. Accepting it would make "" a
		// valid decoding of a table that was never used.
		return "", ErrCorrupt
	}
	if e.Size > MaxLen {
		return "", ErrCorrupt
	}
	// Data holds exactly the bytes NBits needs, and the padding in the last
	// one is zero. Neither is cosmetic: spare bytes and dirty padding are two
	// ways to carry a second payload that decodes to the same string.
	if len(e.Data) != (e.NBits+7)/8 {
		return "", ErrCorrupt
	}
	if pad := len(e.Data)*8 - e.NBits; pad > 0 {
		if e.Data[len(e.Data)-1]&byte((1<<uint(pad))-1) != 0 {
			return "", ErrCorrupt
		}
	}

	var (
		count [maxCodeLen + 1]int
		seen  [256]bool
	)
	for i, c := range e.Codes {
		if c.Len < 1 || c.Len > maxCodeLen {
			return "", ErrCorrupt
		}
		if i > 0 {
			prev := e.Codes[i-1]
			if c.Len < prev.Len || (c.Len == prev.Len && c.Symbol <= prev.Symbol) {
				return "", ErrCorrupt
			}
		}
		// The order check only compares neighbours, so it catches a repeat at
		// the same length and misses one at two different lengths. Encode
		// never emits two codes for one byte, and a decoder that accepted it
		// would map two streams to the same string.
		if seen[c.Symbol] {
			return "", ErrCorrupt
		}
		seen[c.Symbol] = true
		count[c.Len]++
	}

	// Kraft equality: a complete prefix code fills the unit interval exactly.
	// The single-symbol alphabet is the one exception this package emits, and
	// it is incomplete by construction: its leaf has no sibling.
	if !(len(e.Codes) == 1 && e.Codes[0].Len == 1) {
		kraft := uint64(0)
		for _, c := range e.Codes {
			kraft += uint64(1) << uint(maxCodeLen-c.Len)
		}
		if kraft != uint64(1)<<uint(maxCodeLen) {
			return "", ErrCorrupt
		}
	}

	// The lengths are the header. Re-derive the bits from them and refuse a
	// payload that carries different ones.
	want := make([]Code, len(e.Codes))
	copy(want, e.Codes)
	assignCanonical(want)
	for i, c := range e.Codes {
		if c.Bits != want[i].Bits {
			return "", ErrCorrupt
		}
	}

	var (
		first    [maxCodeLen + 2]uint32
		firstIdx [maxCodeLen + 2]int
		code     uint32
		idx      int
	)
	for l := 1; l <= maxCodeLen; l++ {
		first[l] = code
		firstIdx[l] = idx
		code = (code + uint32(count[l])) << 1
		idx += count[l]
	}

	var (
		out    strings.Builder
		cur    uint32
		curLen int
	)
	for i := 0; i < e.NBits; i++ {
		cur = cur<<1 | uint32((e.Data[i/8]>>uint(7-i%8))&1)
		curLen++
		if curLen > maxCodeLen {
			return "", ErrCorrupt
		}
		if n := count[curLen]; n > 0 && cur >= first[curLen] && cur-first[curLen] < uint32(n) {
			out.WriteByte(e.Codes[firstIdx[curLen]+int(cur-first[curLen])].Symbol)
			cur, curLen = 0, 0
		}
	}
	if curLen != 0 {
		return "", ErrCorrupt // the stream ends in the middle of a code
	}
	got := out.String()
	if len(got) != e.Size {
		return "", ErrCorrupt
	}
	return got, nil
}

// node is one entry in the merge forest. A leaf carries a symbol, an internal
// node carries the two indices it was merged from.
type node struct {
	weight      int
	symbol      int // -1 for an internal node
	left, right int
}

// codeLengths returns the optimal length per present symbol, deterministically.
//
// It is the two-queue variant of Huffman's algorithm: leaves pre-sorted by
// (frequency, symbol) in one queue, merged nodes appended to a second in the
// order they are created, which is already non-decreasing. Both queues are
// then read from the front, so no priority queue and no map is involved and
// nothing depends on heap tie-breaking. Ties prefer the leaf queue, which
// keeps the shallower codes on the more frequent symbols.
func codeLengths(freq [256]int) ([]Code, error) {
	nodes := make([]node, 0, 511)
	leaves := make([]int, 0, 256)
	for sym := 0; sym < 256; sym++ {
		if freq[sym] == 0 {
			continue
		}
		nodes = append(nodes, node{weight: freq[sym], symbol: sym, left: -1, right: -1})
		leaves = append(leaves, len(nodes)-1)
	}
	sortLeaves(nodes, leaves)

	// One distinct symbol: the leaf has nothing to pair with, so the tree walk
	// below would give it a zero-bit code and no stream at all.
	if len(leaves) == 1 {
		return []Code{{Symbol: byte(nodes[leaves[0]].symbol), Len: 1}}, nil
	}

	merged := make([]int, 0, 256)
	headLeaf, headMerged := 0, 0
	pop := func() int {
		takeLeaf := headLeaf < len(leaves)
		if takeLeaf && headMerged < len(merged) {
			takeLeaf = nodes[leaves[headLeaf]].weight <= nodes[merged[headMerged]].weight
		}
		if takeLeaf {
			i := leaves[headLeaf]
			headLeaf++
			return i
		}
		i := merged[headMerged]
		headMerged++
		return i
	}
	for (len(leaves)-headLeaf)+(len(merged)-headMerged) > 1 {
		a := pop()
		b := pop()
		nodes = append(nodes, node{
			weight: nodes[a].weight + nodes[b].weight,
			symbol: -1,
			left:   a,
			right:  b,
		})
		merged = append(merged, len(nodes)-1)
	}
	root := merged[len(merged)-1]

	// Depth-first walk, explicit stack: a chain's call depth is not a place to
	// be clever, and the tree can be 18 levels deep at MaxLen.
	out := make([]Code, 0, len(leaves))
	type frame struct{ idx, depth int }
	stack := []frame{{root, 0}}
	for len(stack) > 0 {
		f := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		n := nodes[f.idx]
		if n.symbol >= 0 {
			if f.depth > maxCodeLen {
				return nil, ErrTooDeep
			}
			out = append(out, Code{Symbol: byte(n.symbol), Len: f.depth})
			continue
		}
		stack = append(stack, frame{n.left, f.depth + 1}, frame{n.right, f.depth + 1})
	}
	return out, nil
}

// sortLeaves orders leaf indices by (weight, symbol), ascending. Insertion
// sort: at most 256 entries, and gno has no sort.Slice.
func sortLeaves(nodes []node, leaves []int) {
	for i := 1; i < len(leaves); i++ {
		v := leaves[i]
		j := i - 1
		for j >= 0 && leafLess(nodes[v], nodes[leaves[j]]) {
			leaves[j+1] = leaves[j]
			j--
		}
		leaves[j+1] = v
	}
}

func leafLess(a, b node) bool {
	if a.weight != b.weight {
		return a.weight < b.weight
	}
	return a.symbol < b.symbol
}

// sortCodes orders a table by (Len, Symbol), ascending, which is the canonical
// order every other function here assumes.
func sortCodes(codes []Code) {
	for i := 1; i < len(codes); i++ {
		v := codes[i]
		j := i - 1
		for j >= 0 && codeLess(v, codes[j]) {
			codes[j+1] = codes[j]
			j--
		}
		codes[j+1] = v
	}
}

func codeLess(a, b Code) bool {
	if a.Len != b.Len {
		return a.Len < b.Len
	}
	return a.Symbol < b.Symbol
}

// assignCanonical fills in Bits from Len alone: start at zero, add one per
// code, shift left on every increase in length. The table must already be
// sorted by (Len, Symbol).
func assignCanonical(codes []Code) {
	if len(codes) == 0 {
		return
	}
	code := uint32(0)
	prev := codes[0].Len
	for i := range codes {
		code <<= uint(codes[i].Len - prev)
		prev = codes[i].Len
		codes[i].Bits = code
		code++
	}
}
