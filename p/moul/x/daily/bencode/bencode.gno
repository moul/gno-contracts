// Package bencode implements bencoding, the serialization format BitTorrent
// uses for .torrent files and tracker responses, as a pure reusable package.
//
// Four types, and that is the whole format: integers (i42e), byte strings
// (5:hello), lists (l...e) and dictionaries (d...e). There is no float, no
// boolean and no null, which is most of why the format fits in one file.
//
// The reason to reach for it over JSON is that bencode is CANONICAL: one value
// has exactly one encoding. Dictionary keys are sorted bytewise, integers carry
// no leading zeros and no negative zero, and strings carry their length instead
// of an escape syntax. An infohash is the digest of a re-encoded sub-dictionary,
// so a decoder that accepts a sloppy encoding and re-emits a tidy one silently
// changes the identity of the thing it parsed.
//
// This decoder is therefore strict: it REJECTS non-canonical input rather than
// normalizing it, so for every input it accepts, Decode followed by Encode
// returns the original bytes unchanged.
//
// A live demo of this package is at
// [r/moul/x/daily/bencodedemo](/r/moul/x/daily/bencodedemo/v0).
package bencode

import (
	"errors"
	"strconv"
	"strings"
)

// Limits, so a decode stays bounded on chain.
const (
	// MaxLen is the longest input Decode will look at.
	MaxLen = 8192
	// MaxDepth is how deeply lists and dictionaries may nest.
	MaxDepth = 16
)

// Kind is the type of a [Value]: one of the four bencode types.
type Kind int

// The four bencode types, plus the zero value.
const (
	KindInvalid Kind = iota
	KindInt
	KindString
	KindList
	KindDict
)

// String names the kind, for rendering and error messages.
func (k Kind) String() string {
	switch k {
	case KindInt:
		return "int"
	case KindString:
		return "string"
	case KindList:
		return "list"
	case KindDict:
		return "dict"
	default:
		return "invalid"
	}
}

// Errors returned by [Decode]. They are distinguishable on purpose: a caller
// feeding the decoder a user-pasted torrent wants to say which of the four
// strictness rules the paste broke.
var (
	// ErrTooLong is returned when input is longer than [MaxLen].
	ErrTooLong = errors.New("bencode: input too long")
	// ErrSyntax is returned when input is not bencode at all.
	ErrSyntax = errors.New("bencode: malformed input")
	// ErrNotCanonical is returned for input that is parseable but could never
	// have been produced by an encoder: a leading zero, a negative zero, or
	// dictionary keys that are unsorted or duplicated.
	ErrNotCanonical = errors.New("bencode: input is not canonical")
	// ErrTrailingData is returned when bytes follow the top-level value.
	ErrTrailingData = errors.New("bencode: trailing data after top-level value")
	// ErrTooDeep is returned when nesting exceeds [MaxDepth].
	ErrTooDeep = errors.New("bencode: nesting too deep")
)

// Value is one bencode value. Build one with [NewInt], [NewString], [NewList]
// or [NewDict], or get one from [Decode]. Accessors that do not match the
// value's kind return the zero value rather than panicking, so a chain of
// lookups through a document of unknown shape never aborts a realm call.
type Value struct {
	kind  Kind
	num   int64
	text  string
	elems []*Value
	keys  []string
	vals  []*Value
}

// NewInt returns an integer value.
func NewInt(n int64) *Value { return &Value{kind: KindInt, num: n} }

// NewString returns a byte-string value.
func NewString(s string) *Value { return &Value{kind: KindString, text: s} }

// NewList returns a list of the given items, in order.
func NewList(items ...*Value) *Value {
	l := &Value{kind: KindList, elems: []*Value{}}
	for _, it := range items {
		l.elems = append(l.elems, it)
	}
	return l
}

// NewDict returns an empty dictionary. Fill it with [Value.Set], in any order:
// the encoding sorts.
func NewDict() *Value {
	return &Value{kind: KindDict, keys: []string{}, vals: []*Value{}}
}

// Kind reports the value's type. A nil value is [KindInvalid].
func (v *Value) Kind() Kind {
	if v == nil {
		return KindInvalid
	}
	return v.kind
}

// Int returns the integer, or 0 for any other kind.
func (v *Value) Int() int64 {
	if v == nil || v.kind != KindInt {
		return 0
	}
	return v.num
}

// Text returns the byte string, or "" for any other kind.
func (v *Value) Text() string {
	if v == nil || v.kind != KindString {
		return ""
	}
	return v.text
}

// Len returns the number of list items or dictionary entries, 0 otherwise.
func (v *Value) Len() int {
	if v == nil {
		return 0
	}
	switch v.kind {
	case KindList:
		return len(v.elems)
	case KindDict:
		return len(v.keys)
	default:
		return 0
	}
}

// At returns the i-th list item, or the i-th dictionary value in key order.
// Out of range, or any other kind, returns nil.
func (v *Value) At(i int) *Value {
	if v == nil || i < 0 {
		return nil
	}
	switch v.kind {
	case KindList:
		if i >= len(v.elems) {
			return nil
		}
		return v.elems[i]
	case KindDict:
		if i >= len(v.vals) {
			return nil
		}
		return v.vals[i]
	default:
		return nil
	}
}

// Get returns the dictionary entry for key, or nil when it is absent or the
// value is not a dictionary.
func (v *Value) Get(key string) *Value {
	if v == nil || v.kind != KindDict {
		return nil
	}
	i, found := v.find(key)
	if !found {
		return nil
	}
	return v.vals[i]
}

// Keys returns the dictionary's keys in bytewise order, nil for other kinds.
func (v *Value) Keys() []string {
	if v == nil || v.kind != KindDict {
		return nil
	}
	out := make([]string, len(v.keys))
	copy(out, v.keys)
	return out
}

// Set inserts or replaces a dictionary entry and returns the dictionary, so
// calls chain. It is a no-op on any other kind.
func (v *Value) Set(key string, val *Value) *Value {
	if v == nil || v.kind != KindDict {
		return v
	}
	i, found := v.find(key)
	if found {
		v.vals[i] = val
		return v
	}
	v.keys = append(v.keys, "")
	v.vals = append(v.vals, nil)
	copy(v.keys[i+1:], v.keys[i:])
	copy(v.vals[i+1:], v.vals[i:])
	v.keys[i] = key
	v.vals[i] = val
	return v
}

// find returns the index of key, or where it would be inserted.
func (v *Value) find(key string) (int, bool) {
	lo, hi := 0, len(v.keys)
	for lo < hi {
		mid := (lo + hi) / 2
		if v.keys[mid] < key {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo, lo < len(v.keys) && v.keys[lo] == key
}

// Encode returns the canonical bencoding of the value. A nil value encodes to
// the empty string.
func (v *Value) Encode() string {
	var b strings.Builder
	v.writeTo(&b)
	return b.String()
}

func (v *Value) writeTo(b *strings.Builder) {
	if v == nil {
		return
	}
	switch v.kind {
	case KindInt:
		b.WriteString("i")
		b.WriteString(strconv.FormatInt(v.num, 10))
		b.WriteString("e")
	case KindString:
		b.WriteString(strconv.Itoa(len(v.text)))
		b.WriteString(":")
		b.WriteString(v.text)
	case KindList:
		b.WriteString("l")
		for _, e := range v.elems {
			e.writeTo(b)
		}
		b.WriteString("e")
	case KindDict:
		b.WriteString("d")
		for i, k := range v.keys {
			b.WriteString(strconv.Itoa(len(k)))
			b.WriteString(":")
			b.WriteString(k)
			v.vals[i].writeTo(b)
		}
		b.WriteString("e")
	}
}

// Decode parses one bencode value and rejects anything after it. It also
// rejects input that is parseable but not canonical, which is the whole point:
// see the package doc.
func Decode(s string) (*Value, error) {
	if len(s) > MaxLen {
		return nil, ErrTooLong
	}
	v, next, err := decodeValue(s, 0, 0)
	if err != nil {
		return nil, err
	}
	if next != len(s) {
		return nil, ErrTrailingData
	}
	return v, nil
}

func decodeValue(s string, i, depth int) (*Value, int, error) {
	if i >= len(s) {
		return nil, i, ErrSyntax
	}
	switch c := s[i]; {
	case c == 'i':
		return decodeInt(s, i)
	case c == 'l':
		return decodeList(s, i, depth)
	case c == 'd':
		return decodeDict(s, i, depth)
	case c >= '0' && c <= '9':
		return decodeString(s, i)
	default:
		return nil, i, ErrSyntax
	}
}

func decodeInt(s string, i int) (*Value, int, error) {
	end := strings.IndexByte(s[i:], 'e')
	if end < 0 {
		return nil, i, ErrSyntax
	}
	end += i
	body := s[i+1 : end]
	if err := checkIntLiteral(body); err != nil {
		return nil, i, err
	}
	n, err := strconv.ParseInt(body, 10, 64)
	if err != nil {
		return nil, i, ErrSyntax
	}
	return NewInt(n), end + 1, nil
}

// checkIntLiteral enforces the canonical integer grammar: optional '-', then
// digits, with no leading zero and no negative zero.
func checkIntLiteral(body string) error {
	digits := body
	neg := false
	if strings.HasPrefix(digits, "-") {
		neg = true
		digits = digits[1:]
	}
	if digits == "" {
		return ErrSyntax
	}
	for k := 0; k < len(digits); k++ {
		if digits[k] < '0' || digits[k] > '9' {
			return ErrSyntax
		}
	}
	if len(digits) > 1 && digits[0] == '0' {
		return ErrNotCanonical
	}
	if neg && digits == "0" {
		return ErrNotCanonical
	}
	return nil
}

func decodeString(s string, i int) (*Value, int, error) {
	colon := strings.IndexByte(s[i:], ':')
	if colon < 0 {
		return nil, i, ErrSyntax
	}
	colon += i
	lit := s[i:colon]
	for k := 0; k < len(lit); k++ {
		if lit[k] < '0' || lit[k] > '9' {
			return nil, i, ErrSyntax
		}
	}
	if len(lit) > 1 && lit[0] == '0' {
		return nil, i, ErrNotCanonical
	}
	n, err := strconv.Atoi(lit)
	if err != nil || n < 0 {
		return nil, i, ErrSyntax
	}
	start := colon + 1
	if start+n > len(s) {
		return nil, i, ErrSyntax
	}
	return NewString(s[start : start+n]), start + n, nil
}

func decodeList(s string, i, depth int) (*Value, int, error) {
	if depth+1 > MaxDepth {
		return nil, i, ErrTooDeep
	}
	l := NewList()
	j := i + 1
	for {
		if j >= len(s) {
			return nil, j, ErrSyntax
		}
		if s[j] == 'e' {
			return l, j + 1, nil
		}
		item, next, err := decodeValue(s, j, depth+1)
		if err != nil {
			return nil, next, err
		}
		l.elems = append(l.elems, item)
		j = next
	}
}

func decodeDict(s string, i, depth int) (*Value, int, error) {
	if depth+1 > MaxDepth {
		return nil, i, ErrTooDeep
	}
	d := NewDict()
	j := i + 1
	last := ""
	for {
		if j >= len(s) {
			return nil, j, ErrSyntax
		}
		if s[j] == 'e' {
			return d, j + 1, nil
		}
		if s[j] < '0' || s[j] > '9' {
			// A key is always a byte string. Anything else is not a dict.
			return nil, j, ErrSyntax
		}
		kv, next, err := decodeString(s, j)
		if err != nil {
			return nil, next, err
		}
		key := kv.Text()
		if len(d.keys) > 0 && key <= last {
			// Unsorted or duplicated: parseable, but no encoder emits it.
			return nil, next, ErrNotCanonical
		}
		val, next2, err := decodeValue(s, next, depth+1)
		if err != nil {
			return nil, next2, err
		}
		d.keys = append(d.keys, key)
		d.vals = append(d.vals, val)
		last = key
		j = next2
	}
}
