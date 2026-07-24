package faucet

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestClaimGrantsPoints(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	Claim(cross(cur))

	uassert.Equal(t, int64(ClaimAmount), BalanceOf(alice.String()),
		"first claim should grant ClaimAmount")
	uassert.Equal(t, int64(ClaimAmount), totalDistributed,
		"totalDistributed should reflect the single claim")
	uassert.Equal(t, int64(1), totalClaims, "one claim recorded")
}

func TestClaimCooldownAborts(cur realm, t *testing.T) {
	bob := testutils.TestAddress("bob")
	testing.SetRealm(testing.NewUserRealm(bob))

	// First claim succeeds at the current height.
	Claim(cross(cur))

	// Immediate second claim (same block) must abort due to cooldown.
	uassert.AbortsWithMessage(t, cur,
		"cooldown active: 100 block(s) remaining before you can claim again",
		func() {
			Claim(cross(cur))
		},
		"second immediate claim should abort on cooldown",
	)
}

func TestRenderContainsStats(cur realm, t *testing.T) {
	carol := testutils.TestAddress("carol")
	testing.SetRealm(testing.NewUserRealm(carol))
	Claim(cross(cur))

	out := Render("")
	uassert.True(t, strings.Contains(out, "# Token Faucet"), "has title")
	uassert.True(t, strings.Contains(out, "Total distributed"), "has stats")
	uassert.True(t, strings.Contains(out, carol.String()),
		"claimer address listed in table")
}
