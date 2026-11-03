package lzw

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// "aaaaa" is the smallest input that forces the decoder's hardest case. The
// encoder emits 'a', then the code for "aa" on the step that CREATES "aa", so
// the decoder meets code 256 before it has had a chance to add it. A decoder
// that only looks entries up in its table returns an error here, or worse
// returns four characters instead of five.
func TestCodesKwKwK(t *testing.T) {
	enc, err := Encode("aaaaa")
	uassert.NoError(t, err)

	codes, err := enc.Codes()
	uassert.NoError(t, err)
	uassert.Equal(t, 3, len(codes))
	uassert.Equal(t, 97, codes[0])  // 'a'
	uassert.Equal(t, 256, codes[1]) // "aa", on the step that creates it
	uassert.Equal(t, 256, codes[2]) // "aa" again, now a plain lookup

	got, err := enc.Decode()
	uassert.NoError(t, err)
	uassert.Equal(t, "aaaaa", got)
}

// Two inputs small enough to follow entry by entry. Both pin the dictionary's
// growth order, which is the only thing a decoder has to reproduce.
func TestCodesWorkedExamples(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want []int
	}{
		{
			// a b c a b c a b c: three new pairs, then "abc" and "cab" pay off.
			name: "abcabcabc",
			in:   "abcabcabc",
			want: []int{97, 98, 99, 256, 258, 257},
		},
		{
			// The textbook input. "is" and "si" are both reused, "ss" never is.
			name: "mississippi",
			in:   "mississippi",
			want: []int{109, 105, 115, 115, 257, 259, 112, 112, 105},
		},
	}
	for _, tc := range cases {
		enc, err := Encode(tc.in)
		uassert.NoError(t, err)
		codes, err := enc.Codes()
		uassert.NoError(t, err)
		uassert.Equal(t, len(tc.want), len(codes), tc.name+": code count")
		for i := range tc.want {
			uassert.Equal(t, tc.want[i], codes[i], tc.name+": code "+itoa(i))
		}
		got, err := enc.Decode()
		uassert.NoError(t, err)
		uassert.Equal(t, tc.in, got, tc.name+": round trip")

		// The entries are the output, cut up. Nothing is dropped and nothing
		// is invented between the code stream and the decoded string.
		steps, err := enc.Steps()
		uassert.NoError(t, err)
		uassert.Equal(t, len(tc.want), len(steps), tc.name+": step count")
		var joined string
		for _, s := range steps {
			uassert.Equal(t, 9, s.Width, tc.name+": short input stays nine bits")
			joined += s.Entry
		}
		uassert.Equal(t, tc.in, joined, tc.name+": entries rebuild the input")
	}
}

// Every one of these has to come back byte for byte, whatever the shape of the
// input. Empty is not in the table: Encode refuses it.
func TestRoundTrip(t *testing.T) {
	cases := []string{
		"a",
		"ab",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		"abababababababab",
		"mississippi",
		"TOBEORNOTTOBEORTOBEORNOT",
		"the quick brown fox jumps over the lazy dog",
		strings.Repeat("gno.land", 64),
		strings.Repeat("\x00\xff", 128),
		allBytes(),
	}
	for _, in := range cases {
		enc, err := Encode(in)
		uassert.NoError(t, err)
		got, err := enc.Decode()
		uassert.NoError(t, err)
		uassert.Equal(t, in, got)
		uassert.Equal(t, len(in), enc.Size)
	}
}

// The code width grows with the dictionary, and the decoder is always one
// entry behind the encoder. That lag is the whole difficulty of LZW: the
// encoder widens its codes after adding entry 511, the decoder has only added
// 510 by the time it reads the first wide one, so a decoder that widens on its
// own count reads every later code off by a bit and the output turns to
// garbage somewhere past the first 256 codes.
//
// The input is pseudo-random on purpose: random bytes almost never repeat, so
// the dictionary grows at close to one entry per code and 2,600 bytes cross
// both the 9->10 and the 10->11 boundary.
func TestWidthSchedule(t *testing.T) {
	in := pseudoRandom(2600)

	enc, err := Encode(in)
	uassert.NoError(t, err)

	codes, err := enc.Codes()
	uassert.NoError(t, err)
	uassert.True(t, len(codes) > 768, "input must cross the 10->11 boundary")

	// Stated as positions, which is how a decoder has to see it: the width
	// belongs to the slot in the stream, not to the code sitting in it.
	steps, err := enc.Steps()
	uassert.NoError(t, err)
	uassert.Equal(t, 9, steps[255].Width, "code 256 is still nine bits")
	uassert.Equal(t, 10, steps[256].Width, "code 257 is the first ten-bit one")
	uassert.Equal(t, 10, steps[767].Width, "code 768 is still ten bits")
	uassert.Equal(t, 11, steps[768].Width, "code 769 is the first eleven-bit one")

	// The encoder's schedule, stated independently of the encoder: codes 1 to
	// 256 are 9 bits, 257 to 768 are 10, 769 to 1792 are 11, the rest are 12.
	want := 0
	for i := 1; i <= len(codes); i++ {
		switch {
		case i <= 256:
			want += 9
		case i <= 768:
			want += 10
		case i <= 1792:
			want += 11
		default:
			want += 12
		}
	}
	uassert.Equal(t, want, enc.NBits, "packed bit count")

	got, err := enc.Decode()
	uassert.NoError(t, err)
	uassert.Equal(t, in, got)
}

// The dictionary stops growing at MaxWidth and the coder has no CLEAR code, so
// a long input past that point still round trips, just without learning
// anything new.
func TestFrozenDictionary(t *testing.T) {
	in := pseudoRandom(MaxLen)

	enc, err := Encode(in)
	uassert.NoError(t, err)
	got, err := enc.Decode()
	uassert.NoError(t, err)
	uassert.Equal(t, in, got)
}

func TestEncodeBounds(t *testing.T) {
	_, err := Encode("")
	uassert.ErrorIs(t, err, ErrEmpty)

	_, err = Encode(strings.Repeat("x", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)

	enc, err := Encode(strings.Repeat("x", MaxLen))
	uassert.NoError(t, err)
	uassert.Equal(t, MaxLen, enc.Size)
}

// Encoded has exported fields, so a caller can build one by hand or read one
// out of storage. Every case below is something a decoder that trusts its
// input would accept, and each one would return a string nobody ever encoded.
func TestDecodeRefusesCorruptPayloads(t *testing.T) {
	good, err := Encode("mississippi")
	uassert.NoError(t, err)

	cases := []struct {
		name string
		bend func(e *Encoded)
	}{
		{"zero size", func(e *Encoded) { e.Size = 0 }},
		{"negative size", func(e *Encoded) { e.Size = -1 }},
		{"size over MaxLen", func(e *Encoded) { e.Size = MaxLen + 1 }},
		{"size disagrees with the stream", func(e *Encoded) { e.Size = 10 }},
		{"no bits", func(e *Encoded) { e.NBits = 0 }},
		{"stream ends mid-code", func(e *Encoded) { e.NBits -= 4 }},
		{"spare byte", func(e *Encoded) { e.Data = append(e.Data, 0) }},
		{"short data", func(e *Encoded) { e.Data = e.Data[:len(e.Data)-1] }},
		{"dirty padding", func(e *Encoded) { e.Data[len(e.Data)-1] |= 1 }},
		// The decoder's table holds only the 256 single bytes when it reads
		// the first code, so a first code above 255 names nothing.
		{"first code is not a byte", func(e *Encoded) { e.Data[0] |= 0x80 }},
		// 511 is far beyond anything an 11-byte input could have built.
		{"code beyond the dictionary", func(e *Encoded) {
			e.Data[1] |= 0x7f
			e.Data[2] |= 0xc0
		}},
	}
	for _, tc := range cases {
		e := &Encoded{
			Data:  append([]byte(nil), good.Data...),
			NBits: good.NBits,
			Size:  good.Size,
		}
		tc.bend(e)
		got, err := e.Decode()
		uassert.ErrorIs(t, err, ErrCorrupt, tc.name)
		uassert.Equal(t, "", got, tc.name+": no output")
	}
}

// Saved is negative when the input is too short or too flat to pay for the
// nine-bit codes, which is the honest answer and not a bug.
func TestSaved(t *testing.T) {
	enc, err := Encode("abcdefgh")
	uassert.NoError(t, err)
	uassert.Equal(t, 8*8-8*9, enc.Saved()) // eight codes, no match found
	uassert.True(t, enc.Saved() < 0, "an unrepeating input costs more than it saves")

	enc, err = Encode(strings.Repeat("ab", 256))
	uassert.NoError(t, err)
	uassert.True(t, enc.Saved() > 0, "a repeating input pays")
}

// Codes and Decode read the same stream, so a payload Decode refuses is a
// payload Codes refuses too.
func TestCodesRefusesWhatDecodeRefuses(t *testing.T) {
	enc, err := Encode("mississippi")
	uassert.NoError(t, err)
	enc.NBits -= 4

	_, err = enc.Decode()
	uassert.ErrorIs(t, err, ErrCorrupt)
	_, err = enc.Codes()
	uassert.ErrorIs(t, err, ErrCorrupt)
}

// allBytes is every byte value once, which gives the encoder 256 symbols and
// nothing at all to match.
func allBytes() string {
	b := make([]byte, 256)
	for i := range b {
		b[i] = byte(i)
	}
	return string(b)
}

// pseudoRandom is a 32-bit linear congruential generator, the one from
// Numerical Recipes. It is here because the test needs an input the dictionary
// cannot compress, and it has to produce the same bytes on every node: gno has
// no rand, and a Render or a test that depended on one would be a consensus
// bug rather than a convenience.
func pseudoRandom(n int) string {
	b := make([]byte, n)
	seed := uint32(1)
	for i := range b {
		seed = seed*1664525 + 1013904223
		b[i] = byte(seed >> 24)
	}
	return string(b)
}

// itoa keeps the failure messages readable without pulling in strconv.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}
