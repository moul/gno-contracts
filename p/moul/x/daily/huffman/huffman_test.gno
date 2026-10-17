package huffman

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// "abracadabra" is the worked example: five symbols, frequencies 5/2/2/1/1,
// and one optimal length vector (a=1, the other four=3) that no tie-break can
// change. The canonical codes below are therefore the only correct answer.
func TestCanonicalTableAbracadabra(t *testing.T) {
	codes, err := Table("abracadabra")
	uassert.NoError(t, err)
	uassert.Equal(t, 5, len(codes))

	wantSymbols := "abcdr"
	wantBits := []string{"0", "100", "101", "110", "111"}
	for i, want := range wantBits {
		uassert.Equal(t, string(wantSymbols[i]), string(codes[i].Symbol))
		uassert.Equal(t, want, codes[i].String())
	}
}

// The table is sorted by (length, symbol), which is what makes it a header a
// decoder can rebuild from the lengths alone.
func TestTableIsSortedByLengthThenSymbol(t *testing.T) {
	codes, err := Table("the quick brown fox jumps over the lazy dog")
	uassert.NoError(t, err)
	uassert.True(t, len(codes) > 20, "expected one code per distinct byte")
	for i := 1; i < len(codes); i++ {
		prev, cur := codes[i-1], codes[i]
		ok := prev.Len < cur.Len || (prev.Len == cur.Len && prev.Symbol < cur.Symbol)
		uassert.True(t, ok, "table out of order")
	}
}

func TestEncodeBitStream(t *testing.T) {
	enc, err := Encode("abracadabra")
	uassert.NoError(t, err)
	// 5*1 + 2*3 + 2*3 + 1*3 + 1*3 = 23 bits, against 88 raw.
	uassert.Equal(t, 23, enc.NBits)
	uassert.Equal(t, 11, enc.Size)
	uassert.Equal(t, 3, len(enc.Data)) // 23 bits -> 3 bytes, 1 bit of padding
	uassert.Equal(t, "01001110101011001001110", enc.BitString())
}

func TestRoundTrip(t *testing.T) {
	cases := []string{
		"a",
		"aa",
		"ab",
		"abracadabra",
		"hello world",
		"the quick brown fox jumps over the lazy dog",
		strings.Repeat("x", 1000),
		strings.Repeat("ab", 500),
		"\x00\x01\x02\xff\xfe",
	}
	for _, in := range cases {
		enc, err := Encode(in)
		uassert.NoError(t, err)
		got, err := enc.Decode()
		uassert.NoError(t, err)
		uassert.Equal(t, in, got)
	}
}

// Every byte value exactly once: 256 symbols at equal frequency, so every code
// is 8 bits long and the encoding saves nothing. The flat case has to work
// before the skewed one means anything.
func TestAllByteValues(t *testing.T) {
	var b strings.Builder
	for i := 0; i < 256; i++ {
		b.WriteByte(byte(i))
	}
	in := b.String()
	enc, err := Encode(in)
	uassert.NoError(t, err)
	uassert.Equal(t, 256, len(enc.Codes))
	uassert.Equal(t, 2048, enc.NBits)
	for _, c := range enc.Codes {
		uassert.Equal(t, 8, c.Len)
	}
	got, err := enc.Decode()
	uassert.NoError(t, err)
	uassert.Equal(t, in, got)
}

// A one-symbol alphabet has no sibling to pair its leaf with. The code is one
// bit long and the Kraft sum is 1/2, the only incomplete code this package
// emits.
func TestSingleSymbol(t *testing.T) {
	enc, err := Encode("aaaaa")
	uassert.NoError(t, err)
	uassert.Equal(t, 1, len(enc.Codes))
	uassert.Equal(t, 1, enc.Codes[0].Len)
	uassert.Equal(t, 5, enc.NBits)
	uassert.Equal(t, "00000", enc.BitString())
	got, err := enc.Decode()
	uassert.NoError(t, err)
	uassert.Equal(t, "aaaaa", got)
}

func TestEmptyInput(t *testing.T) {
	_, err := Encode("")
	uassert.ErrorIs(t, err, ErrEmpty)
	_, err = Table("")
	uassert.ErrorIs(t, err, ErrEmpty)
}

func TestTooLong(t *testing.T) {
	_, err := Encode(strings.Repeat("a", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)
}

// Decode rebuilds the canonical codes from the lengths it is handed and
// refuses a payload whose own Bits disagree, because a decoder that trusts
// both fields returns a different string than the one that was encoded.
func TestDecodeRejectsCorruptPayloads(t *testing.T) {
	good, err := Encode("abracadabra")
	uassert.NoError(t, err)

	cases := []struct {
		name   string
		mutate func(e *Encoded)
	}{
		{"no codes", func(e *Encoded) { e.Codes = nil }},
		{"zero length", func(e *Encoded) { e.Codes[0].Len = 0 }},
		{"bits disagree with the canonical table", func(e *Encoded) { e.Codes[1].Bits = 7 }},
		{"table out of order", func(e *Encoded) { e.Codes[0], e.Codes[1] = e.Codes[1], e.Codes[0] }},
		{"duplicate symbol", func(e *Encoded) { e.Codes[2].Symbol = e.Codes[1].Symbol }},
		{"duplicate symbol at another length", func(e *Encoded) { e.Codes[1].Symbol = e.Codes[0].Symbol }},
		{"more bits than data", func(e *Encoded) { e.NBits = len(e.Data)*8 + 1 }},
		{"truncated stream", func(e *Encoded) { e.NBits = 2 }},
		{"size disagrees", func(e *Encoded) { e.Size = 3 }},
		{"incomplete code", func(e *Encoded) { e.Codes = e.Codes[:4] }},
		{"empty payload", func(e *Encoded) { e.NBits, e.Size = 0, 0 }},
		{"padding bits are not zero", func(e *Encoded) { e.Data[len(e.Data)-1] |= 1 }},
	}
	for _, c := range cases {
		e := &Encoded{
			Codes: append([]Code(nil), good.Codes...),
			Data:  append([]byte(nil), good.Data...),
			NBits: good.NBits,
			Size:  good.Size,
		}
		c.mutate(e)
		_, err := e.Decode()
		uassert.ErrorIs(t, err, ErrCorrupt, c.name)
	}
}

// Same input, same table, every time: a Render built on this cannot reshuffle
// between two identical calls.
func TestDeterministic(t *testing.T) {
	a, err := Encode("mississippi")
	uassert.NoError(t, err)
	b, err := Encode("mississippi")
	uassert.NoError(t, err)
	uassert.Equal(t, a.NBits, b.NBits)
	uassert.Equal(t, a.BitString(), b.BitString())
	uassert.Equal(t, len(a.Codes), len(b.Codes))
	for i := range a.Codes {
		uassert.Equal(t, a.Codes[i].String(), b.Codes[i].String())
	}
}

// The skew is the whole point: a frequency-flat input saves little, a skewed
// one saves most of its bits.
func TestSaved(t *testing.T) {
	flat, err := Encode("abcd")
	uassert.NoError(t, err)
	uassert.Equal(t, 8, flat.NBits) // four 2-bit codes
	uassert.Equal(t, 24, flat.Saved())

	skewed, err := Encode(strings.Repeat("a", 60) + "bcd")
	uassert.NoError(t, err)
	uassert.True(t, skewed.Saved() > 400, "a skewed input must save most of its bits")
}
