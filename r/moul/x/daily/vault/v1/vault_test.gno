package vault

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestSetAndRender(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	Set(cross(cur), "greeting", "hello")
	Set(cross(cur), "lang", "gno")

	out := renderAddress(alice.String())
	uassert.True(t, strings.Contains(out, "greeting"), "should contain key greeting")
	uassert.True(t, strings.Contains(out, "hello"), "should contain value hello")
	uassert.True(t, strings.Contains(out, "Total entries: 2"), "should count 2 entries")

	root := Render("")
	uassert.True(t, strings.Contains(root, alice.String()), "root should list alice")
}

func TestDeleteAndIsolation(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice2")
	bob := testutils.TestAddress("bob2")

	testing.SetRealm(testing.NewUserRealm(alice))
	Set(cross(cur), "shared", "alice-value")

	testing.SetRealm(testing.NewUserRealm(bob))
	Set(cross(cur), "shared", "bob-value")

	// Namespaces are isolated: same key, different owners.
	av := vaults.Get(alice.String())
	bv := vaults.Get(bob.String())
	avVal := av.(*avl.Tree).Get("shared")
	bvVal := bv.(*avl.Tree).Get("shared")
	uassert.Equal(t, "alice-value", avVal.(string))
	uassert.Equal(t, "bob-value", bvVal.(string))

	// Bob deletes his own key; alice's remains.
	Delete(cross(cur), "shared")
	bobStill := vaults.Has(bob.String())
	uassert.False(t, bobStill, "bob's vault should be gone after last key removed")
	aliceStill := vaults.Has(alice.String())
	uassert.True(t, aliceStill, "alice's vault should remain")

	// Deleting a missing key aborts.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "key not found", func() {
		Delete(cross(cur), "nope")
	})
}
