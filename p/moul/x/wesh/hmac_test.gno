package wesh

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// TestHMACSHA256RFC4231 checks the HMAC construction against the published
// RFC 4231 vectors. Case 6 matters most: its key is longer than the block
// size, which is the branch that hashes the key down first and the one most
// easily got wrong.
func TestHMACSHA256RFC4231(t *testing.T) {
	cases := []struct {
		name string
		key  []byte
		data []byte
		want string
	}{
		{
			"rfc4231 case 1",
			repeat(0x0b, 20),
			[]byte("Hi There"),
			"b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
		},
		{
			"rfc4231 case 2",
			[]byte("Jefe"),
			[]byte("what do ya want for nothing?"),
			"5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
		},
		{
			"rfc4231 case 6 (key longer than the block size)",
			repeat(0xaa, 131),
			[]byte("Test Using Larger Than Block-Size Key - Hash Key First"),
			"60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
		},
	}
	for _, tc := range cases {
		got := hex.EncodeToString(HMACSHA256(tc.key, tc.data))
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

// repeat returns n copies of b.
func repeat(b byte, n int) []byte {
	out := make([]byte, n)
	for i := range out {
		out[i] = b
	}
	return out
}
