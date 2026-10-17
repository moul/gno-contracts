package bencode

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestDecodeRoundTrip(t *testing.T) {
	cases := []struct {
		name string
		in   string
	}{
		{"zero", "i0e"},
		{"positive", "i42e"},
		{"negative", "i-42e"},
		{"empty string", "0:"},
		{"string", "5:hello"},
		{"string with colon", "9:a:b:c:d:e"},
		{"empty list", "le"},
		{"list of ints", "li1ei2ei3ee"},
		{"nested list", "ll1:aee"},
		{"empty dict", "de"},
		{"dict", "d3:cow3:moo4:spam4:eggse"},
		{"dict of list", "d4:spaml1:a1:bee"},
		{"torrent-ish", "d8:announce9:udp://x:y4:infod6:lengthi1024e4:name4:fileee"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			v, err := Decode(c.in)
			uassert.NoError(t, err)
			uassert.Equal(t, c.in, v.Encode())
		})
	}
}

func TestDecodeRejects(t *testing.T) {
	cases := []struct {
		name string
		in   string
	}{
		{"empty input", ""},
		{"bare letter", "x"},
		{"unterminated int", "i42"},
		{"empty int", "ie"},
		{"int with leading zero", "i03e"},
		{"negative zero", "i-0e"},
		{"explicit plus", "i+1e"},
		{"lone minus", "i-e"},
		{"non digit int", "i4a2e"},
		{"string too short", "5:abc"},
		{"string length leading zero", "03:abc"},
		{"string without colon", "5abcde"},
		{"unterminated list", "li1e"},
		{"unterminated dict", "d3:cow3:mooe4:spam"},
		{"dict with odd entries", "d3:cowe"},
		{"dict with int key", "di1e3:mooe"},
		{"dict keys out of order", "d4:spam4:eggs3:cow3:mooe"},
		{"dict duplicate keys", "d3:cow3:moo3:cow3:mooe"},
		{"trailing data", "i1ei2e"},
		{"trailing junk", "lexx"},
		{"over MaxLen", "0:" + strings.Repeat("x", MaxLen)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			v, err := Decode(c.in)
			uassert.Error(t, err)
			if v != nil {
				t.Errorf("want nil value on error, got %s", v.Encode())
			}
		})
	}
}

func TestDecodeTooDeep(t *testing.T) {
	ok := strings.Repeat("l", MaxDepth) + strings.Repeat("e", MaxDepth)
	_, err := Decode(ok)
	uassert.NoError(t, err)

	deep := strings.Repeat("l", MaxDepth+1) + strings.Repeat("e", MaxDepth+1)
	_, err = Decode(deep)
	uassert.ErrorIs(t, err, ErrTooDeep)
}

func TestDecodeErrorKinds(t *testing.T) {
	cases := []struct {
		in   string
		want error
	}{
		{"i007e", ErrNotCanonical},
		{"d4:spam4:eggs3:cow3:mooe", ErrNotCanonical},
		{"i1ei2e", ErrTrailingData},
		{"lx", ErrSyntax},
		{"0:" + strings.Repeat("x", MaxLen), ErrTooLong},
	}
	for _, c := range cases {
		t.Run(c.in, func(t *testing.T) {
			_, err := Decode(c.in)
			uassert.ErrorIs(t, err, c.want)
		})
	}
}

func TestAccessors(t *testing.T) {
	v, err := Decode("d3:cowl1:ai7ee4:spam4:eggse")
	uassert.NoError(t, err)
	uassert.Equal(t, KindDict.String(), v.Kind().String())
	uassert.Equal(t, 2, v.Len())
	uassert.Equal(t, "cow,spam", strings.Join(v.Keys(), ","))

	cow := v.Get("cow")
	uassert.Equal(t, KindList.String(), cow.Kind().String())
	uassert.Equal(t, 2, cow.Len())
	uassert.Equal(t, "a", cow.At(0).Text())
	uassert.Equal(t, int64(7), cow.At(1).Int())

	uassert.Equal(t, "eggs", v.Get("spam").Text())
	uassert.True(t, v.Get("absent") == nil)
	uassert.True(t, cow.At(9) == nil)
	uassert.True(t, cow.At(-1) == nil)
}

func TestWrongKindAccessorsAreZero(t *testing.T) {
	s := NewString("hi")
	uassert.Equal(t, int64(0), s.Int())
	uassert.Equal(t, 0, s.Len())
	uassert.True(t, s.At(0) == nil)
	uassert.True(t, s.Get("k") == nil)
	uassert.Equal(t, 0, len(s.Keys()))

	n := NewInt(3)
	uassert.Equal(t, "", n.Text())

	var nilv *Value
	uassert.Equal(t, KindInvalid.String(), nilv.Kind().String())
	uassert.Equal(t, "", nilv.Encode())
}

func TestDictEncodesSortedWhateverTheInsertionOrder(t *testing.T) {
	d := NewDict()
	d.Set("spam", NewString("eggs"))
	d.Set("cow", NewString("moo"))
	d.Set("announce", NewInt(1))
	uassert.Equal(t, "announce,cow,spam", strings.Join(d.Keys(), ","))
	uassert.Equal(t, "d8:announcei1e3:cow3:moo4:spam4:eggse", d.Encode())
}

func TestSetReplacesInPlace(t *testing.T) {
	d := NewDict()
	d.Set("k", NewInt(1))
	d.Set("k", NewInt(2))
	uassert.Equal(t, 1, d.Len())
	uassert.Equal(t, int64(2), d.Get("k").Int())
}

func TestEncodeBuiltValues(t *testing.T) {
	l := NewList(NewInt(-3), NewString("x"), NewList())
	uassert.Equal(t, "li-3e1:xlee", l.Encode())
	uassert.Equal(t, "i-3e", NewInt(-3).Encode())
	uassert.Equal(t, "4:spam", NewString("spam").Encode())
}

func TestKindString(t *testing.T) {
	cases := []struct {
		k    Kind
		want string
	}{
		{KindInvalid, "invalid"},
		{KindInt, "int"},
		{KindString, "string"},
		{KindList, "list"},
		{KindDict, "dict"},
		{Kind(99), "invalid"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, c.k.String())
	}
}

func TestCanonicalIsAFixedPoint(t *testing.T) {
	// Every value this package builds encodes to something it accepts, and
	// decoding that again changes nothing. That is what makes a bencode
	// digest reproducible.
	d := NewDict()
	d.Set("b", NewList(NewInt(0), NewString("")))
	d.Set("a", NewDict())
	first := d.Encode()

	v, err := Decode(first)
	uassert.NoError(t, err)
	uassert.Equal(t, first, v.Encode())
}

func TestNilValuesNeverReachTheEncoding(t *testing.T) {
	// A nil child would encode to nothing, which silently produces a
	// dictionary or a list that this package's own Decode rejects.
	d := NewDict()
	d.Set("k", nil)
	uassert.Equal(t, 0, d.Len())
	uassert.Equal(t, "de", d.Encode())

	d.Set("k", NewInt(1))
	d.Set("k", nil)
	uassert.Equal(t, int64(1), d.Get("k").Int(), "a nil never removes a live entry")

	l := NewList(NewInt(1), nil, NewString("x"))
	uassert.Equal(t, 2, l.Len())
	uassert.Equal(t, "li1e1:xe", l.Encode())

	// The property that matters: anything Encode emits, Decode accepts.
	for _, enc := range []string{d.Encode(), l.Encode()} {
		_, err := Decode(enc)
		uassert.NoError(t, err)
	}
}

func TestStringLengthNeverOverflows(t *testing.T) {
	// The length literal is bounded by nothing but MaxLen, so a 19-digit
	// length fits in the input and in an int64. start+n must not be the
	// thing that decides whether the slice is in range.
	for _, in := range []string{
		"9223372036854775807:x",
		"9223372036854775806:x",
		"8000000000000000000:x",
	} {
		v, err := Decode(in)
		uassert.Error(t, err)
		uassert.True(t, v == nil)
	}
}

func TestEncodeIsTotal(t *testing.T) {
	// A caller can build what no input can produce: a cycle, or nesting past
	// MaxDepth. Encode has no error to return, so it must not be the thing
	// that aborts a realm call.
	d := NewDict()
	d.Set("self", d)
	uassert.Equal(t, 0, d.Len(), "a dictionary cannot hold itself")
	uassert.Equal(t, "de", d.Encode())

	a, b := NewDict(), NewDict()
	a.Set("b", b)
	b.Set("a", a)
	uassert.Equal(t, "", a.Encode(), "an indirect cycle encodes to nothing")
	uassert.Equal(t, "", b.Encode())

	deep := NewList()
	for i := 0; i < MaxDepth; i++ {
		deep = NewList(deep)
	}
	uassert.Equal(t, "", deep.Encode(), "past MaxDepth there is no canonical encoding")

	shallow := NewList()
	for i := 0; i < MaxDepth-1; i++ {
		shallow = NewList(shallow)
	}
	_, err := Decode(shallow.Encode())
	uassert.NoError(t, err, "and everything under it still round-trips")
}

func TestZeroValuesNeverReachTheEncoding(t *testing.T) {
	// Value is zero-constructible from outside the package, and that zero is
	// KindInvalid, which writes nothing. Retaining one would make Len lie.
	l := NewList(NewInt(1), &Value{}, NewString("x"))
	uassert.Equal(t, 2, l.Len())
	uassert.Equal(t, "li1e1:xe", l.Encode())

	d := NewDict()
	d.Set("k", &Value{})
	uassert.Equal(t, 0, d.Len())
	uassert.Equal(t, "de", d.Encode())
}

func TestSetNeverWritesThroughAStructCopy(t *testing.T) {
	// *Value is the intended handle, but the struct is copyable, and slice
	// headers in a copied struct share their backing array.
	d := NewDict()
	d.Set("a", NewInt(1))
	d.Set("b", NewInt(2))

	c := *d
	c.Set("a", NewInt(99))
	uassert.Equal(t, int64(1), d.Get("a").Int(), "the original is untouched")
	uassert.Equal(t, int64(99), c.Get("a").Int())

	c.Set("c", NewInt(3))
	uassert.Equal(t, 2, d.Len(), "and an insertion does not leak either")
	uassert.Equal(t, 3, c.Len())
}
