package wesh

import (
	"encoding/hex"
	"testing"

	"gno.land/p/moul/x/daily/b58/v0"
	"gno.land/p/nt/uassert/v0"
)

// bertyGoldenBlob is the base58 payload from berty's own links_test.go
// ("simple-contact"), produced by MarshalLink from
// PublicRendezvousSeed = 16 x 0x01 and AccountPk = 16 x 0x02.
//
// It is the ground truth for this package's wire format. The keys are 16 bytes
// because that test predates the length rule, so the vector is checked against
// the raw encoder rather than through Contact.Blob, which would (correctly)
// reject them.
const bertyGoldenBlob = "3geQXHmsW9rxRfQFJdu8CEuPtWkfTWgJH13NzAoGatcnh4brusu3"

func TestBlobEncodingMatchesBertyGoldenVector(t *testing.T) {
	id := appendBytesField(nil, fieldBertyIDSeed, repeat(0x01, 16))
	id = appendBytesField(id, fieldBertyIDAccountPK, repeat(0x02, 16))
	blob := appendBytesField(nil, fieldBertyLinkBertyID, id)

	uassert.Equal(t,
		"12240a1001010101010101010101010101010101121002020202020202020202020202020202",
		hex.EncodeToString(blob),
		"protobuf wire bytes")
	uassert.Equal(t, bertyGoldenBlob, b58.Encode(blob), "base58 payload berty produces")
}

// TestWebLink pins the full link for a real 32-byte identity.
func TestWebLink(t *testing.T) {
	c := Contact{
		AccountPK: mustHex(t, testAccountPKHex),
		Seed:      mustHex(t, testSeedHex),
	}
	link, err := c.WebLink()
	uassert.NoError(t, err)
	uassert.Equal(t,
		"https://berty.tech/id#contact/oZBLFpzghxrATkepWvDPNX9pHYqi6BWgP45xGWhqxcwmqN2bnMMbU7UcwUuTaCcDyUvMjmWRMDWcP96bXAndcjNiAZ1Vz9X",
		link)
}

// TestWebLinkDisplayNameEscaping matches berty's url.Values encoding: space
// becomes '+', and everything outside the unreserved set is percent-escaped.
func TestWebLinkDisplayNameEscaping(t *testing.T) {
	c := Contact{
		AccountPK:   mustHex(t, testAccountPKHex),
		Seed:        mustHex(t, testSeedHex),
		DisplayName: "Hello World!",
	}
	link, err := c.WebLink()
	uassert.NoError(t, err)
	uassert.True(t, endsWith(link, "/name=Hello+World%21"), "display name is query-escaped: "+link)
}

func TestWebLinkRoundTrip(t *testing.T) {
	cases := []struct {
		name string
		in   Contact
	}{
		{"no display name", Contact{AccountPK: repeat(0x11, 32), Seed: repeat(0x22, 32)}},
		{"with a display name", Contact{AccountPK: repeat(0x11, 32), Seed: repeat(0x22, 32), DisplayName: "gno support"}},
		{"name needing escapes", Contact{AccountPK: repeat(0x11, 32), Seed: repeat(0x22, 32), DisplayName: "a/b c&d=e"}},
		{"leading zero bytes", Contact{AccountPK: repeat(0x00, 32), Seed: repeat(0x00, 32)}},
	}
	for _, tc := range cases {
		link, err := tc.in.WebLink()
		uassert.NoError(t, err, tc.name)

		got, err := ParseWebLink(link)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, hex.EncodeToString(tc.in.AccountPK), hex.EncodeToString(got.AccountPK), tc.name+": account key")
		uassert.Equal(t, hex.EncodeToString(tc.in.Seed), hex.EncodeToString(got.Seed), tc.name+": seed")
		uassert.Equal(t, tc.in.DisplayName, got.DisplayName, tc.name+": display name")
	}
}

func TestParseWebLinkRejects(t *testing.T) {
	valid, err := Contact{AccountPK: repeat(0x11, 32), Seed: repeat(0x22, 32)}.WebLink()
	uassert.NoError(t, err)

	cases := []struct {
		name string
		in   string
		want error
	}{
		{"not a berty link", "https://example.com/id#contact/abc", ErrNotAWebLink},
		{"no payload segment", WebLinkPrefix + "contact", ErrNotAWebLink},
		{"a group link, not a contact", WebLinkPrefix + "group/" + b58.Encode([]byte{1, 2, 3}), ErrNotAContactLink},
		{"payload is not base58", WebLinkPrefix + "contact/not-base58-0OIl", ErrBadLinkPayload},
		{"payload is not a BertyLink", WebLinkPrefix + "contact/" + b58.Encode([]byte{0xff, 0xff}), ErrBadLinkPayload},
		{"berty's own 16-byte golden vector is too short now", WebLinkPrefix + "contact/" + bertyGoldenBlob, ErrBadSeedLen},
		{"truncated payload", valid[:len(valid)-8], ErrBadLinkPayload},
	}
	for _, tc := range cases {
		_, err := ParseWebLink(tc.in)
		uassert.ErrorIs(t, err, tc.want, tc.name)
	}
}

// TestParseWebLinkIgnoresUnknownQueryKeys matches berty's UnmarshalLink, which
// accepts a link carrying query keys it does not know.
func TestParseWebLinkIgnoresUnknownQueryKeys(t *testing.T) {
	link, err := Contact{AccountPK: repeat(0x11, 32), Seed: repeat(0x22, 32)}.WebLink()
	uassert.NoError(t, err)

	got, err := ParseWebLink(link + "/foo=bar&name=Alice")
	uassert.NoError(t, err)
	uassert.Equal(t, "Alice", got.DisplayName)
}

// TestLookupBytesFieldSkipsOtherWireTypes covers the decoder's skip paths: a
// varint, a 64-bit and a 32-bit field ahead of the one being looked up.
func TestLookupBytesFieldSkipsOtherWireTypes(t *testing.T) {
	buf := []byte{0x08, 0x96, 0x01} // field 1, varint 150
	buf = append(buf, 0x11)         // field 2, 64-bit
	buf = append(buf, repeat(0xaa, 8)...)
	buf = append(buf, 0x1d) // field 3, 32-bit
	buf = append(buf, repeat(0xbb, 4)...)
	buf = appendBytesField(buf, 4, []byte("found"))

	got, ok := lookupBytesField(buf, 4)
	uassert.True(t, ok, "the length-delimited field is reachable past the others")
	uassert.Equal(t, "found", string(got))

	_, ok = lookupBytesField(buf, 9)
	uassert.False(t, ok, "an absent field is reported missing, not guessed")
}

func TestBlobRejectsAnInvalidContact(t *testing.T) {
	_, err := Contact{AccountPK: repeat(1, 31), Seed: repeat(2, 32)}.Blob()
	uassert.ErrorIs(t, err, ErrBadAccountPKLen)
}

func endsWith(s, suffix string) bool {
	return len(s) >= len(suffix) && s[len(s)-len(suffix):] == suffix
}
