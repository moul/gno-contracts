package vault

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// A vault holds a bounded number of entries of bounded size; overwriting an
// existing key is always allowed.
func TestVaultIsBounded(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("bounded")))
	uassert.AbortsContains(t, cur, "too long", func() { Set(cross(cur), strings.Repeat("k", MaxKeyLen+1), "v") })
	for i := 0; i < MaxEntries; i++ {
		Set(cross(cur), "k"+strconv.Itoa(i), "v")
	}
	uassert.AbortsContains(t, cur, "at most", func() { Set(cross(cur), "one-more", "v") })
	Set(cross(cur), "k0", "overwritten")
}
