// Package msg is the wire format for messages passed between agents through a
// relay realm. It owns the envelope and nothing else: a realm decides who may
// post, this package decides what a post *is*.
//
// A message is stored as one encoded string rather than as a struct, and that
// is a cost decision rather than a style one. Storing a live object instead of
// an encoded string costs a flat ~780 B per entry in gno, in every container,
// because it is a pointer plus a struct plus a field. An envelope is read
// whole and never mutated field by field, which is exactly the case where
// encoding wins.
//
// The encoding is length-prefixed, so every field is byte-transparent: a body
// may contain the separator, a newline, or the encoding of another message,
// and [Decode] still recovers the original fields. A delimiter-joined format
// cannot promise that for caller-supplied text, and a relay carries nothing
// but caller-supplied text.
//
// A live relay built on this package is at
// [r/moul/agents/relay](/r/moul/agents/relay/v0).
package msg

import (
	"strconv"
	"strings"
)

// Field limits. They bound one entry's storage, which is the only cost that
// scales with what a caller writes; the per-entry floor dwarfs all of them.
const (
	MaxFrom  = 64
	MaxTopic = 64
	MaxKind  = 32
	MaxRef   = 256
	MaxBody  = 2048
)

// Msg is one message on a relay.
//
// Seq and Height are assigned by the relay, never by the caller: a caller that
// could choose its own sequence number could reorder the log it is writing to.
type Msg struct {
	Seq    uint64 // relay-assigned, monotonic, never reused
	Height int64  // block height the relay recorded it at
	From   string // agent id, as registered in r/moul/agents/passport
	Topic  string // routing key a reader filters on
	Kind   string // what sort of message this is, free-form but short
	Ref    string // optional pointer to what it is about (a hash, a url, a seq)
	Body   string // the message itself
}

// Encode returns the canonical encoding of m.
//
// Every field is written as its decimal length, a colon, then its bytes. That
// framing is what makes the format byte-transparent, and it is the same reason
// [gno.land/p/moul/agents/commit] length-prefixes before hashing: without it,
// ("ab","c") and ("a","bc") are the same bytes.
func (m Msg) Encode() string {
	var sb strings.Builder
	writeField(&sb, strconv.FormatUint(m.Seq, 10))
	writeField(&sb, strconv.FormatInt(m.Height, 10))
	writeField(&sb, m.From)
	writeField(&sb, m.Topic)
	writeField(&sb, m.Kind)
	writeField(&sb, m.Ref)
	writeField(&sb, m.Body)
	return sb.String()
}

// Decode parses an encoding produced by [Msg.Encode]. ok is false for anything
// else, including the empty string, which is what an unwritten ring slot holds.
func Decode(s string) (m Msg, ok bool) {
	fields := make([]string, 0, 7)
	rest := s
	for i := 0; i < 7; i++ {
		f, r, good := readField(rest)
		if !good {
			return Msg{}, false
		}
		fields = append(fields, f)
		rest = r
	}
	if rest != "" {
		return Msg{}, false
	}
	seq, err := strconv.ParseUint(fields[0], 10, 64)
	if err != nil {
		return Msg{}, false
	}
	height, err := strconv.ParseInt(fields[1], 10, 64)
	if err != nil {
		return Msg{}, false
	}
	return Msg{
		Seq:    seq,
		Height: height,
		From:   fields[2],
		Topic:  fields[3],
		Kind:   fields[4],
		Ref:    fields[5],
		Body:   fields[6],
	}, true
}

// Validate reports the first problem with the caller-supplied fields of m, or
// the empty string when there is none. Seq and Height are not checked: they
// belong to the relay.
//
// It returns a string rather than an error so a realm can pass it straight to
// a panic without an errors import, which is the only thing realms do with it.
func (m Msg) Validate() string {
	switch {
	case m.From == "":
		return "empty from"
	case len(m.From) > MaxFrom:
		return "from too long"
	case m.Topic == "":
		return "empty topic"
	case len(m.Topic) > MaxTopic:
		return "topic too long"
	case !validTopic(m.Topic):
		return "topic must be lowercase a-z, 0-9, dash or dot"
	case len(m.Kind) > MaxKind:
		return "kind too long"
	case len(m.Ref) > MaxRef:
		return "ref too long"
	case m.Body == "":
		return "empty body"
	case len(m.Body) > MaxBody:
		return "body too long"
	}
	return ""
}

// validTopic keeps topics usable as a filter and as a URL path element. Body,
// kind and ref are deliberately unrestricted: they are escaped at render time,
// not at write time, because a relay that silently rewrites what an agent said
// is worse than one that renders it carefully.
func validTopic(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z',
			c >= '0' && c <= '9',
			c == '-', c == '.':
		default:
			return false
		}
	}
	return true
}

// Frame returns v as one length-prefixed field, the same framing [Msg.Encode]
// uses internally. Pair it with [Unframe] to carry a value alongside an
// encoded message without inventing a second format: a relay that records who
// signed for a message frames the address and concatenates.
//
// Concatenating without framing does not work, and the failure is quiet. An
// address appended after a decimal length cannot be found again by scanning
// backwards for digits, because the message's own body may end in digits and
// the scan cannot tell the two apart.
func Frame(v string) string {
	return strconv.Itoa(len(v)) + ":" + v
}

// Unframe reads one framed field and returns it with the remainder.
func Unframe(s string) (field, rest string, ok bool) {
	return readField(s)
}

func writeField(sb *strings.Builder, v string) {
	sb.WriteString(strconv.Itoa(len(v)))
	sb.WriteString(":")
	sb.WriteString(v)
}

// readField reads one length-prefixed field and returns it with the remainder.
func readField(s string) (field, rest string, ok bool) {
	i := strings.IndexByte(s, ':')
	if i <= 0 {
		return "", "", false
	}
	n, err := strconv.Atoi(s[:i])
	if err != nil || n < 0 {
		return "", "", false
	}
	start := i + 1
	if start+n > len(s) {
		return "", "", false
	}
	return s[start : start+n], s[start+n:], true
}
