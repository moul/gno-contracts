package crc32demo

import (
	"testing"

	"gno.land/p/moul/x/daily/crc32/v0"
	"gno.land/p/nt/uassert/v0"
)

// TestAvalancheClaim pins the bit count the page quotes for its last two rows.
// The page once said the two checksums share no digits, while they agree in two
// hex positions; a number checked here cannot drift that way again.
func TestAvalancheClaim(t *testing.T) {
	diff := crc32.Checksum("hello world") ^ crc32.Checksum("hello worle")
	n := 0
	for ; diff != 0; diff &= diff - 1 {
		n++
	}
	uassert.Equal(t, 15, n)
}
