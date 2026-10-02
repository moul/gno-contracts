package vault

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
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

// The vault count is bounded globally, not just entries per vault.
func TestVaultCountIsBounded(cur realm, t *testing.T) {
	var added []string
	for i := 0; vaults.Size() < MaxVaults; i++ {
		k := testutils.TestAddress("v" + strconv.Itoa(i)).String()
		if vaults.Get(k) == nil {
			vaults.Set(k, &avl.Tree{})
			added = append(added, k)
		}
	}
	defer func() {
		for _, k := range added {
			vaults.Remove(k)
		}
	}()
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("latecomer")))
	uassert.AbortsContains(t, cur, "vault is full", func() { Set(cross(cur), "k", "v") })
}
