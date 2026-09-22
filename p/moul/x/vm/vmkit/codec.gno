package vmkit

import "errors"

// ErrTruncated is returned by every Reader method that runs past the end of
// the buffer. A snapshot is consensus state, so a short read is always a hard
// error and never a zero value.
var ErrTruncated = errors.New("vmkit: truncated snapshot")

// ErrBadSnapshot is returned when a snapshot is well-formed but not for this
// machine: wrong magic, wrong version, or a field outside its legal range.
var ErrBadSnapshot = errors.New("vmkit: snapshot is not for this machine")

// Writer builds a snapshot. Every integer is fixed-width big-endian and every
// byte slice is length-prefixed, so the encoding is canonical: the same
// machine state always produces the same bytes, on every node.
//
// Machines are not required to use it, but a machine that invents its own
// layout owes the zoo an explanation, because the cross-VM snapshot cost
// comparison only means something when the encodings match.
type Writer struct {
	buf []byte
}

// NewWriter returns a Writer with room for n bytes reserved up front.
func NewWriter(n int) *Writer {
	if n < 0 {
		n = 0
	}
	return &Writer{buf: make([]byte, 0, n)}
}

// Byte appends one byte.
func (w *Writer) Byte(b byte) { w.buf = append(w.buf, b) }

// Uint32 appends a 4-byte big-endian value.
func (w *Writer) Uint32(v uint32) {
	w.buf = append(w.buf, byte(v>>24), byte(v>>16), byte(v>>8), byte(v))
}

// Uint64 appends an 8-byte big-endian value.
func (w *Writer) Uint64(v uint64) {
	w.buf = append(w.buf,
		byte(v>>56), byte(v>>48), byte(v>>40), byte(v>>32),
		byte(v>>24), byte(v>>16), byte(v>>8), byte(v))
}

// Int appends a signed value, zig-zag encoded into a Uint64 so that small
// negative numbers do not cost eight 0xff bytes.
func (w *Writer) Int(v int64) {
	u := uint64(v) << 1
	if v < 0 {
		u = ^u
	}
	w.Uint64(u)
}

// Bytes appends a length-prefixed byte slice.
func (w *Writer) Bytes(p []byte) {
	w.Uint32(uint32(len(p)))
	w.buf = append(w.buf, p...)
}

// String appends a length-prefixed string.
func (w *Writer) String(s string) { w.Bytes([]byte(s)) }

// Out returns the encoded bytes.
func (w *Writer) Out() []byte { return w.buf }

// Reader consumes a snapshot written by [Writer].
//
// It latches the first error it hits: a caller may decode a whole struct and
// check [Reader.Err] once at the end, instead of after every field. Every
// method returns a zero value once the Reader is in error.
type Reader struct {
	buf []byte
	pos int
	err error
}

// NewReader returns a Reader over b.
func NewReader(b []byte) *Reader { return &Reader{buf: b} }

// Err returns the first error hit, or nil.
func (r *Reader) Err() error { return r.err }

// Remaining reports how many bytes are left unread.
func (r *Reader) Remaining() int {
	if r.pos > len(r.buf) {
		return 0
	}
	return len(r.buf) - r.pos
}

// Fail latches err, so a machine can reject a field its own rules forbid and
// have it surface through [Reader.Err] like any decoding failure.
func (r *Reader) Fail(err error) {
	if r.err == nil {
		r.err = err
	}
}

func (r *Reader) take(n int) []byte {
	if r.err != nil {
		return nil
	}
	if n < 0 || r.pos+n > len(r.buf) {
		r.err = ErrTruncated
		return nil
	}
	out := r.buf[r.pos : r.pos+n]
	r.pos += n
	return out
}

// Byte reads one byte.
func (r *Reader) Byte() byte {
	p := r.take(1)
	if p == nil {
		return 0
	}
	return p[0]
}

// Uint32 reads a 4-byte big-endian value.
func (r *Reader) Uint32() uint32 {
	p := r.take(4)
	if p == nil {
		return 0
	}
	return uint32(p[0])<<24 | uint32(p[1])<<16 | uint32(p[2])<<8 | uint32(p[3])
}

// Uint64 reads an 8-byte big-endian value.
func (r *Reader) Uint64() uint64 {
	p := r.take(8)
	if p == nil {
		return 0
	}
	return uint64(p[0])<<56 | uint64(p[1])<<48 | uint64(p[2])<<40 | uint64(p[3])<<32 |
		uint64(p[4])<<24 | uint64(p[5])<<16 | uint64(p[6])<<8 | uint64(p[7])
}

// Int reads a zig-zag encoded signed value written by [Writer.Int].
func (r *Reader) Int() int64 {
	u := r.Uint64()
	v := int64(u >> 1)
	if u&1 != 0 {
		v = ^v
	}
	return v
}

// Bytes reads a length-prefixed byte slice. The result is a copy, so a
// machine can keep it without aliasing the snapshot it was handed.
func (r *Reader) Bytes() []byte {
	n := int(r.Uint32())
	p := r.take(n)
	if p == nil {
		return nil
	}
	out := make([]byte, n)
	copy(out, p)
	return out
}

// String reads a length-prefixed string.
func (r *Reader) String() string {
	p := r.take(int(r.Uint32()))
	if p == nil {
		return ""
	}
	return string(p)
}
