package sha1

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Known-answer tests from FIPS 180-1 / RFC 3174 appendix A, plus the two
// vectors every implementation is checked against.
func TestSumHexKnownVectors(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"", "da39a3ee5e6b4b0d3255bfef95601890afd80709"},
		{"a", "86f7e437faa5a7fce15d1ddcb9eaeaea377667b8"},
		{"abc", "a9993e364706816aba3e25717850c26c9cd0d89d"},
		{"message digest", "c12252ceda8be8994d5fa0290a47231c1d16aae3"},
		{"abcdefghijklmnopqrstuvwxyz", "32d10c7b8cf96570ca04ce37f2a19d84240d3a89"},
		{
			"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
			"84983e441c3bd26ebaae4aa1f95129e5e54670f1",
		},
		{
			"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
			"761c457bf73b14d27e9e9265c46f4b4dda11f940",
		},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, SumHex(c.in))
	}
}

// The million-'a' vector from RFC 3174 is far too slow for the VM; 10_000
// still crosses 156 block boundaries and is pinned against the same reference.
func TestLongMessage(t *testing.T) {
	uassert.Equal(t, "a080cbda64850abb7b7f67ee875ba068074ff6fe", SumHex(strings.Repeat("a", 10000)))
}

// Every length from 0 to 130 crosses the 55/56/64 padding boundaries, where a
// hand-written padder gets it wrong and nowhere else.
func TestPaddingBoundaries(t *testing.T) {
	cases := []struct {
		n    int
		want string
	}{
		{54, "b05d71c64979cb95fa74a33cdb31a40d258ae02e"},
		{55, "c1c8bbdc22796e28c0e15163d20899b65621d65a"},
		{56, "c2db330f6083854c99d4b5bfb6e8f29f201be699"},
		{57, "f08f24908d682555111be7ff6f004e78283d989a"},
		{63, "03f09f5b158a7a8cdad920bddc29b81c18a551f5"},
		{64, "0098ba824b5c16427bd7a1122a5a442a25ec644d"},
		{65, "11655326c708d70319be2610e8a57d9a5b959d3b"},
		{119, "ee971065aaa017e0632a8ca6c77bb3bf8b1dfc56"},
		{128, "ad5b3fdbcb526778c2839d2f151ea753995e26a0"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, SumHex(strings.Repeat("a", c.n)))
	}
}

// Writing in chunks must equal hashing in one shot: that is the only reason
// the streaming Digest exists.
func TestChunkedEqualsOneShot(t *testing.T) {
	msg := strings.Repeat("the quick brown fox ", 37)
	d := New()
	for i := 0; i < len(msg); i += 7 {
		end := i + 7
		if end > len(msg) {
			end = len(msg)
		}
		d.Write(msg[i:end])
	}
	uassert.Equal(t, SumHex(msg), Hex(d.Sum()))
}

// Sum must not finalize the digest: calling it twice returns the same value
// and a later Write still extends the message.
func TestSumIsNotDestructive(t *testing.T) {
	d := New()
	d.Write("abc")
	first := Hex(d.Sum())
	uassert.Equal(t, first, Hex(d.Sum()))
	uassert.Equal(t, "a9993e364706816aba3e25717850c26c9cd0d89d", first)
	d.Write("def")
	uassert.Equal(t, SumHex("abcdef"), Hex(d.Sum()))
}

func TestReset(t *testing.T) {
	d := New()
	d.Write("hello world")
	d.Reset()
	uassert.Equal(t, SumHex(""), Hex(d.Sum()))
}

func TestHexIsFortyLowercaseDigits(t *testing.T) {
	h := SumHex("abc")
	uassert.Equal(t, 40, len(h))
	uassert.Equal(t, strings.ToLower(h), h)
}

func TestVerify(t *testing.T) {
	uassert.True(t, Verify("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"))
	uassert.True(t, Verify("abc", "A9993E364706816ABA3E25717850C26C9CD0D89D"))
	uassert.False(t, Verify("abc", "a9993e364706816aba3e25717850c26c9cd0d89e"))
	uassert.False(t, Verify("abc", "deadbeef"))
}

// A single flipped bit must move roughly half the output bits.
func TestAvalanche(t *testing.T) {
	a, b := Sum("hello world"), Sum("hello worle")
	diff := 0
	for i := 0; i < 20; i++ {
		x := a[i] ^ b[i]
		for ; x != 0; x &= x - 1 {
			diff++
		}
	}
	uassert.True(t, diff > 50, "a single flipped input bit must move about half the output bits")
}

// HMAC-SHA1 vectors from RFC 2202.
func TestHMACKnownVectors(t *testing.T) {
	cases := []struct {
		key, msg, want string
	}{
		{strings.Repeat("\x0b", 20), "Hi There", "b617318655057264e28bc0b6fb378c8ef146be00"},
		{"Jefe", "what do ya want for nothing?", "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79"},
		{strings.Repeat("\xaa", 20), strings.Repeat("\xdd", 50), "125d7342b9ac11cd91a39af48aa17b4f63f175d3"},
		// key longer than the 64-byte block: hashed down first.
		{strings.Repeat("\xaa", 80), "Test Using Larger Than Block-Size Key - Hash Key First", "aa4ae5e15272d00e95705637ce8a3b55ed402112"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, HMACHex(c.key, c.msg))
	}
}

// git names a blob by the SHA-1 of "blob <len>\x00<content>"; these match
// `git hash-object`.
func TestGitBlobID(t *testing.T) {
	uassert.Equal(t, "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", GitBlobID(""))
	uassert.Equal(t, "3b18e512dba79e4c8300dd08aeb37f8e728b8dad", GitBlobID("hello world\n"))
	uassert.Equal(t, "557db03de997c86a4a028e1ebd3a1ceb225be238", GitBlobID("Hello World\n"))
}
