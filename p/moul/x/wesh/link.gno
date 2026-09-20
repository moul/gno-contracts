package wesh

import (
	"encoding/binary"
	"errors"
	"net/url"
	"strings"

	"gno.land/p/moul/x/daily/b58/v0"
)

// WebLinkPrefix is the prefix of a shareable Berty web link. The fragment
// marker is part of it on purpose: everything after '#' stays in the browser
// and is never sent to berty.tech, so the web host never learns the identity
// being shared.
const WebLinkPrefix = "https://berty.tech/id#"

// contactKind is the human-readable link kind for a contact invite,
// berty's BertyLink_ContactInviteV1Kind.
const contactKind = "contact"

// Protobuf field numbers, from berty's api/messengertypes/messengertypes.proto
// and weshnet's api/protocol/protocoltypes.proto. They are wire-format
// constants: changing one silently produces a link no Berty client can read.
const (
	fieldBertyLinkBertyID = 2 // BertyLink.berty_id
	fieldBertyIDSeed      = 1 // BertyID.public_rendezvous_seed
	fieldBertyIDAccountPK = 2 // BertyID.account_pk
)

var (
	ErrNotAWebLink    = errors.New("wesh: not a berty web link")
	ErrNotAContactLink = errors.New("wesh: link is not a contact invite")
	ErrBadLinkPayload = errors.New("wesh: link payload is not a valid contact")
)

// Blob returns the protobuf-encoded machine payload of a contact invite link:
// a BertyLink carrying only a BertyID with the rendezvous seed and account key.
//
// The kind and the display name are deliberately absent. berty's MarshalLink
// puts the kind in the human-readable path segment and the display name in the
// query string, so a blob that carried them would not match a link produced by
// a real Berty client. The encoding here is verified against berty's own
// golden test vector; see link_test.gno.
func (c Contact) Blob() ([]byte, error) {
	if err := c.Validate(); err != nil {
		return nil, err
	}
	id := appendBytesField(nil, fieldBertyIDSeed, c.Seed)
	id = appendBytesField(id, fieldBertyIDAccountPK, c.AccountPK)
	return appendBytesField(nil, fieldBertyLinkBertyID, id), nil
}

// WebLink returns the shareable https://berty.tech/id# link for the contact.
// Scanning or opening it in Berty starts a contact request.
func (c Contact) WebLink() (string, error) {
	blob, err := c.Blob()
	if err != nil {
		return "", err
	}
	link := WebLinkPrefix + contactKind + "/" + b58.Encode(blob)
	if c.DisplayName != "" {
		link += "/name=" + url.QueryEscape(c.DisplayName)
	}
	return link, nil
}

// ParseWebLink decodes a Berty contact web link back into a [Contact].
//
// It accepts links with or without a trailing query segment, and ignores query
// keys other than "name", matching berty's own UnmarshalLink leniency.
func ParseWebLink(link string) (Contact, error) {
	var c Contact

	if !strings.HasPrefix(link, WebLinkPrefix) {
		return c, ErrNotAWebLink
	}
	parts := strings.Split(strings.TrimPrefix(link, WebLinkPrefix), "/")
	if len(parts) < 2 {
		return c, ErrNotAWebLink
	}
	if parts[0] != contactKind {
		return c, ErrNotAContactLink
	}
	if !b58.IsValid(parts[1]) {
		return c, ErrBadLinkPayload
	}

	inner, ok := lookupBytesField(b58.Decode(parts[1]), fieldBertyLinkBertyID)
	if !ok {
		return c, ErrBadLinkPayload
	}
	seed, ok := lookupBytesField(inner, fieldBertyIDSeed)
	if !ok {
		return c, ErrBadLinkPayload
	}
	pk, ok := lookupBytesField(inner, fieldBertyIDAccountPK)
	if !ok {
		return c, ErrBadLinkPayload
	}
	c.AccountPK = pk
	c.Seed = seed

	if len(parts) > 2 {
		c.DisplayName = queryName(parts[2])
	}
	if err := c.Validate(); err != nil {
		return Contact{}, err
	}
	return c, nil
}

// queryName pulls the "name" key out of an encoded query segment, returning ""
// when it is absent or malformed. A bad display name must never fail a link
// that is otherwise valid: the name is decoration, the keys are the payload.
func queryName(q string) string {
	for _, pair := range strings.Split(q, "&") {
		if !strings.HasPrefix(pair, "name=") {
			continue
		}
		name, err := url.QueryUnescape(strings.TrimPrefix(pair, "name="))
		if err != nil || len(name) > MaxDisplayNameLen {
			return ""
		}
		return name
	}
	return ""
}

// appendBytesField appends a length-delimited (wire type 2) protobuf field.
// An empty value encodes to nothing, which is what proto3 does for a zero
// bytes field, and is why an invalid contact can never produce a short-but-
// plausible blob: Validate has already rejected it.
func appendBytesField(dst []byte, num int, val []byte) []byte {
	if len(val) == 0 {
		return dst
	}
	dst = append(dst, byte(num<<3|2))
	dst = binary.AppendUvarint(dst, uint64(len(val)))
	return append(dst, val...)
}

// lookupBytesField scans a protobuf message for the first length-delimited
// field with the given number, skipping every other field whatever its wire
// type. Unknown fields are skipped rather than rejected so a link produced by
// a newer Berty client still parses.
func lookupBytesField(buf []byte, num int) ([]byte, bool) {
	i := 0
	for i < len(buf) {
		tag, n := binary.Uvarint(buf[i:])
		if n <= 0 {
			return nil, false
		}
		i += n
		fieldNum := int(tag >> 3)
		wireType := int(tag & 0x7)

		switch wireType {
		case 0: // varint
			_, n := binary.Uvarint(buf[i:])
			if n <= 0 {
				return nil, false
			}
			i += n
		case 1: // 64-bit
			if i+8 > len(buf) {
				return nil, false
			}
			i += 8
		case 2: // length-delimited
			l, n := binary.Uvarint(buf[i:])
			if n <= 0 {
				return nil, false
			}
			i += n
			end := i + int(l)
			if end < i || end > len(buf) {
				return nil, false
			}
			if fieldNum == num {
				return buf[i:end], true
			}
			i = end
		case 5: // 32-bit
			if i+4 > len(buf) {
				return nil, false
			}
			i += 4
		default:
			return nil, false
		}
	}
	return nil, false
}
