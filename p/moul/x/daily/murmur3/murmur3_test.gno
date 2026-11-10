package murmur3

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The SMHasher self-test. This is the one assertion that matters: a single
// wrong constant, a mis-ordered tail byte or a rotate in the wrong direction
// moves it, and no amount of eyeballing the code finds that.
func TestVerificationValue(t *testing.T) {
	uassert.Equal(t, uint32(0xB0F57EE3), Verification())
}

// Published vectors for MurmurHash3 x86_32 with seed 0.
func TestSum32KnownVectors(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"", "00000000"},
		{"a", "3c2569b2"},
		{"ab", "9bbfd75f"},
		{"abc", "b3dd93fa"},
		{"abcd", "43ed676a"}, // exactly one block, empty tail
		{"abcde", "e89b9af6"},
		{"Hello, world!", "c0363e43"},
		{"123456789", "b4fef382"},
		{"The quick brown fox jumps over the lazy dog", "2e4ff723"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, SumHex(c.in))
	}
}

// The seed is not decoration: it re-keys the whole function, so the same input
// under a different seed shares nothing with the first result.
func TestSeedChangesEverything(t *testing.T) {
	cases := []struct {
		in   string
		seed uint32
		want uint32
	}{
		{"", 1, 0x514e28b7},
		{"a", 1, 0x588adce8},
		{"abc", 1, 0xaa75e9ff},
		{"hello world", 1, 0x4343ed22},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, Sum32Seed(c.in, c.seed))
	}
	uassert.NotEqual(t, Sum32("abc"), Sum32Seed("abc", 1))
}

// Every tail length 0..3 takes a different branch through the switch, and a
// fallthrough dropped from any of them only breaks one of these four.
func TestEveryTailLength(t *testing.T) {
	base := "abcdefgh" // two whole blocks
	cases := []struct {
		in   string
		want string
	}{
		{base, "49ddccc4"},
		{base + "i", "421406f0"},
		{base + "ij", "88927791"},
		{base + "ijk", "5f3b25df"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, SumHex(c.in))
	}
}

// One flipped letter must share nothing with the original.
func TestAvalanche(t *testing.T) {
	a := SumHex("hello world")
	b := SumHex("hello worle")
	uassert.Equal(t, "5e928f0f", a)
	uassert.Equal(t, "b97415bf", b)
	uassert.NotEqual(t, a, b)
}

func TestHexIsZeroPadded(t *testing.T) {
	uassert.Equal(t, "00000000", Hex(0))
	uassert.Equal(t, "0000000f", Hex(15))
	uassert.Equal(t, "ffffffff", Hex(0xFFFFFFFF))
	uassert.Equal(t, 8, len(Hex(1)))
}

// Bucket is the reason a non-cryptographic hash is worth having on chain:
// spreading keys over a fixed number of shards.
func TestBucket(t *testing.T) {
	uassert.Equal(t, 0, Bucket("anything", 1))
	uassert.Equal(t, -1, Bucket("anything", 0))
	uassert.Equal(t, -1, Bucket("anything", -3))

	for _, s := range []string{"", "a", "abc", "moul", "gno.land"} {
		got := Bucket(s, 8)
		uassert.True(t, got >= 0 && got < 8, "bucket out of range for "+s)
	}
	// Deterministic: the same key always lands in the same shard.
	uassert.Equal(t, Bucket("moul", 16), Bucket("moul", 16))
}

// 1000 keys over 16 buckets: every bucket used, none of them swallowing the
// table. A hash that returned a constant would put 1000 in one bucket and 0 in
// the other fifteen, which is exactly what this refuses.
func TestBucketSpread(t *testing.T) {
	const n = 16
	counts := make([]int, n)
	for i := 0; i < 1000; i++ {
		counts[Bucket("key-"+itoa(i), n)]++
	}
	for i := 0; i < n; i++ {
		uassert.True(t, counts[i] > 35, "bucket "+itoa(i)+" underfilled: "+itoa(counts[i]))
		uassert.True(t, counts[i] < 100, "bucket "+itoa(i)+" overfilled: "+itoa(counts[i]))
	}
}

// Length is mixed in, so padding a key with NUL bytes is a different key.
func TestLengthIsMixedIn(t *testing.T) {
	uassert.NotEqual(t, Sum32("a"), Sum32("a\x00"))
	uassert.NotEqual(t, Sum32("\x00"), Sum32(""))
}

// A long input exercises the block loop well past the tail.
func TestLongInput(t *testing.T) {
	uassert.Equal(t, "bd6bc060", SumHex(strings.Repeat("a", 32)))
}

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
