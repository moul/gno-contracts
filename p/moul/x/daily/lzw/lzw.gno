// Package lzw compresses a string with Lempel-Ziv-Welch: the dictionary coder
// behind GIF, TIFF and compress(1), in the one form that is safe to put on a
// chain.
//
// LZW learns as it reads. Both sides start from the same 256 entries, one per
// byte, and both add the same new entry after every code, so the dictionary is
// never transmitted. That is what separates it from Huffman, where the table
// IS the header: here the payload is nothing but a stream of codes, and the
// table is a consequence of the codes rather than a thing beside them.
//
// Two properties matter here and neither is about compression.
//
// The decoder is one entry BEHIND the encoder, always. The encoder emits the
// code for the longest match it has, then adds that match plus the next byte;
// the decoder cannot add anything until it has seen the code AFTER the one it
// is decoding, because the entry it must add ends in a byte it has not read
// yet. Two consequences follow, and both are where a naive implementation
// breaks. A decoder can meet a code it has not added yet, exactly one code
// ahead of its table, and must synthesise the entry rather than fail; see
// [Encoded.Decode]. And the code WIDTH, which grows with the dictionary, has
// to grow on the same code for both sides even though their tables disagree
// about how full they are, which is why the decoder widens one entry early.
//
// Decoding VALIDATES. [Encoded] is a plain struct with exported fields, so a
// caller can build one by hand or read one out of storage, and a decoder that
// trusts what it is handed will happily return a string nobody ever encoded.
// [Encoded.Decode] refuses a first code that is not a single byte, a code
// beyond what its own table could hold, a stream that ends mid-code, nonzero
// padding, a Data slice that is not exactly the bytes NBits needs, and output
// that is not Size bytes long.
//
// There is no CLEAR code. The dictionary freezes at [MaxWidth] bits and stays
// frozen, which costs a little compression on a long input whose statistics
// change halfway through, and buys a stream with exactly one interpretation.
// A reset code is a second thing the two sides must agree about, and agreeing
// about one is already the hard part.
//
// A live demo of this package is at
// [r/moul/x/daily/lzwdemo](/r/moul/x/daily/lzwdemo/v0).
package lzw

import (
	"errors"
	"strings"
)

const (
	// MaxLen bounds input so gas stays predictable.
	MaxLen = 4096

	// MinWidth is the width of the first code, in bits. The dictionary starts
	// with the 256 single bytes, so the first code that can mean anything new
	// is 256 and nine bits is the narrowest thing that holds it.
	MinWidth = 9

	// MaxWidth is where the code width stops growing, and with it the
	// dictionary: 4096 entries, then frozen for the rest of the stream.
	MaxWidth = 12

	// maxCodes is the dictionary's ceiling, 1<<MaxWidth.
	maxCodes = 1 << MaxWidth

	// firstCode is the first code that is not a single byte.
	firstCode = 256
)

var (
	// ErrEmpty is returned for an input with no bytes in it. The coder has no
	// code to emit for one, and a zero-bit payload would decode as the empty
	// string under any table at all.
	ErrEmpty = errors.New("lzw: empty input")
	// ErrTooLong is returned when input exceeds MaxLen.
	ErrTooLong = errors.New("lzw: input too long")
	// ErrCorrupt is returned by Decode and Codes when the payload is not one
	// this package could have produced.
	ErrCorrupt = errors.New("lzw: corrupt payload")
)

// Encoded is a compressed payload: the packed code stream and the two numbers
// needed to read it back. There is no table, because there never is one.
type Encoded struct {
	Data  []byte // the code stream, most significant bit of each byte first
	NBits int    // significant bits in Data; the rest of the last byte is padding
	Size  int    // length of the original input, in bytes
}

// Saved reports how many bits the encoding removed, which is negative when the
// input is too short or too varied to pay for nine-bit codes.
func (e *Encoded) Saved() int { return e.Size*8 - e.NBits }

// Encode compresses s.
//
// The loop is Welch's, unchanged: hold the longest string w that is already in
// the dictionary, extend it while it stays in, and the moment w+c is not there
// emit the code for w, add w+c, and start again from c. Every emitted code
// therefore names something both sides already know, and every added entry is
// something the decoder can derive one code later.
func Encode(s string) (*Encoded, error) {
	if len(s) == 0 {
		return nil, ErrEmpty
	}
	if len(s) > MaxLen {
		return nil, ErrTooLong
	}

	// The 256 single bytes, so that the lookup below never has to special-case
	// a one-character w. Nothing iterates this map: gno's map order is
	// unspecified and the output would not be deterministic if anything did.
	dict := make(map[string]int, 1024)
	for i := 0; i < firstCode; i++ {
		dict[string([]byte{byte(i)})] = i
	}

	e := &Encoded{Size: len(s)}
	next := firstCode
	width := MinWidth

	w := s[0:1]
	for i := 1; i < len(s); i++ {
		wc := w + s[i:i+1]
		if _, ok := dict[wc]; ok {
			w = wc
			continue
		}
		e.writeBits(uint32(dict[w]), width)
		if next < maxCodes {
			dict[wc] = next
			next++
			// The encoder widens once its table can no longer be addressed in
			// the current width. Decode widens one entry earlier, and the
			// comment there is the one that explains why.
			if next == 1<<uint(width) && width < MaxWidth {
				width++
			}
		}
		w = s[i : i+1]
	}
	e.writeBits(uint32(dict[w]), width)
	return e, nil
}

// Decode validates the payload and returns the original string.
func (e *Encoded) Decode() (string, error) {
	s, _, err := e.walk(false)
	return s, err
}

// Step is one code in the stream, with what it expanded to and how wide it
// was on the wire. Width is the interesting one: it is not a property of the
// code, it is a property of the position, and reproducing it is the whole job
// of a decoder.
type Step struct {
	Code  int
	Entry string
	Width int
}

// Steps returns the stream decoded code by code, validating it exactly as
// Decode does. It exists so that a caller showing the stream to a human does
// not have to reimplement the dictionary to label it.
func (e *Encoded) Steps() ([]Step, error) {
	_, steps, err := e.walk(true)
	return steps, err
}

// Codes returns just the code numbers, in order. The ones below 256 are
// bytes, the rest are dictionary entries the stream built on its way past.
func (e *Encoded) Codes() ([]int, error) {
	steps, err := e.Steps()
	if err != nil {
		return nil, err
	}
	codes := make([]int, len(steps))
	for i, s := range steps {
		codes[i] = s.Code
	}
	return codes, nil
}

// walk is the decoder. It is shared so that Steps can never disagree with
// Decode about whether a payload is valid.
//
// Everything it checks is something a hand-built or storage-read Encoded can
// get wrong: a zero or out-of-range Size, a Data slice that is not exactly the
// bytes NBits needs, nonzero padding in the last byte, a first code that is
// not a single byte, a code past the end of its own table, a stream ending
// mid-code, output longer than Size, and a result whose length is not Size.
func (e *Encoded) walk(collect bool) (string, []Step, error) {
	if e.Size < 1 || e.Size > MaxLen || e.NBits < MinWidth {
		return "", nil, ErrCorrupt
	}
	// Data holds exactly the bytes NBits needs, and the padding in the last
	// one is zero. Neither is cosmetic: a spare byte and dirty padding are two
	// ways to carry a second payload that decodes to the same string.
	if len(e.Data) != (e.NBits+7)/8 {
		return "", nil, ErrCorrupt
	}
	if pad := len(e.Data)*8 - e.NBits; pad > 0 {
		if e.Data[len(e.Data)-1]&byte((1<<uint(pad))-1) != 0 {
			return "", nil, ErrCorrupt
		}
	}

	dict := make([]string, firstCode, maxCodes)
	for i := 0; i < firstCode; i++ {
		dict[i] = string([]byte{byte(i)})
	}
	next := firstCode
	width := MinWidth
	pos := 0

	var steps []Step

	code, ok := e.readBits(pos, width)
	if !ok {
		return "", nil, ErrCorrupt
	}
	pos += width
	// The table holds nothing but the single bytes at this point, so a first
	// code of 256 or more names an entry that cannot exist yet.
	if int(code) >= firstCode {
		return "", nil, ErrCorrupt
	}
	prev := dict[code]
	if collect {
		steps = append(steps, Step{Code: int(code), Entry: prev, Width: width})
	}

	var out strings.Builder
	out.WriteString(prev)

	for pos < e.NBits {
		code, ok = e.readBits(pos, width)
		if !ok {
			return "", nil, ErrCorrupt // the stream ends in the middle of a code
		}
		pos += width
		stepWidth := width

		var entry string
		switch {
		case int(code) < next:
			entry = dict[code]
		case int(code) == next:
			// The case that breaks a naive decoder, and it is not rare: it
			// happens whenever the encoder emitted the code for a string on
			// the very step that created it, which any run of a repeating
			// pattern does. The entry is not in the table and cannot be,
			// because the encoder built it from w plus the first byte of the
			// string it is about to emit, which is this same w. So it is
			// prev plus prev's own first byte, and nothing else ever.
			entry = prev + prev[0:1]
		default:
			return "", nil, ErrCorrupt
		}

		if out.Len()+len(entry) > e.Size {
			return "", nil, ErrCorrupt
		}
		out.WriteString(entry)
		if collect {
			steps = append(steps, Step{Code: int(code), Entry: entry, Width: stepWidth})
		}

		if next < maxCodes {
			dict = append(dict, prev+entry[0:1])
			next++
			// One entry early, deliberately. The encoder widened after adding
			// the entry that filled the old width; at that moment the decoder
			// has added one fewer, because its first code added nothing. So
			// the two reach the same CODE at different table sizes, and the
			// stream is what has to stay in step, not the table. Widening on
			// next instead of next+1 reads every later code shifted by a bit,
			// which does not fail: it returns a different string.
			if next+1 == 1<<uint(width) && width < MaxWidth {
				width++
			}
		}
		prev = entry
	}

	got := out.String()
	if len(got) != e.Size {
		return "", nil, ErrCorrupt
	}
	return got, steps, nil
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

// readBits reads n bits from bit offset pos, most significant first. It
// reports false when the stream does not hold that many, which is how a
// payload ending mid-code is caught rather than padded with zeros.
func (e *Encoded) readBits(pos, n int) (uint32, bool) {
	if pos+n > e.NBits {
		return 0, false
	}
	v := uint32(0)
	for i := 0; i < n; i++ {
		b := pos + i
		v = v<<1 | uint32((e.Data[b/8]>>uint(7-b%8))&1)
	}
	return v, true
}
