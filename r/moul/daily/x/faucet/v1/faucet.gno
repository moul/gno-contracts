// Package faucet is a toy points faucet realm for the gno.land test13 testnet.
//
// Any caller may Claim() 100 points, but only once per cooldown window of 100
// blocks. Cooldown is enforced deterministically via runtime.ChainHeight() — no
// real clocks, no RNG. Per-caller balance and last-claim height live in an
// avl.Tree so Render iterates in deterministic (address-sorted) order.
package faucet

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

const (
	// ClaimAmount is granted on every successful claim.
	ClaimAmount = 100
	// CooldownBlocks is the minimum number of blocks between two claims by the
	// same caller.
	CooldownBlocks = 100
)

// claimer holds the per-address state.
type claimer struct {
	Balance   int64 // total points accumulated
	LastClaim int64 // chain height of the last successful claim
	Claims    int64 // number of successful claims by this address
}

var (
	// claimers maps address string -> *claimer.
	claimers = avl.NewTree()
	// totalDistributed is the running sum of all points ever granted.
	totalDistributed int64
	// totalClaims is the total number of successful claims across all callers.
	totalClaims int64
)

// Claim grants ClaimAmount points to the caller, subject to the per-caller
// cooldown. It aborts (cross-realm) if the caller must still wait.
func Claim(cur realm) {
	caller := unsafe.PreviousRealm().Address()
	key := caller.String()
	height := runtime.ChainHeight()

	var c *claimer
	if v, ok := claimers.Get(key); ok {
		c = v.(*claimer)
		wait := c.LastClaim + CooldownBlocks - height
		if wait > 0 {
			panic("cooldown active: " + strconv.FormatInt(wait, 10) +
				" block(s) remaining before you can claim again")
		}
	} else {
		c = &claimer{}
	}

	c.Balance += ClaimAmount
	c.LastClaim = height
	c.Claims++
	claimers.Set(key, c)

	totalDistributed += ClaimAmount
	totalClaims++

	chain.Emit(
		"Claim",
		"caller", key,
		"amount", strconv.FormatInt(ClaimAmount, 10),
		"balance", strconv.FormatInt(c.Balance, 10),
		"height", strconv.FormatInt(height, 10),
	)
}

// BalanceOf returns the current point balance of addr (0 if never claimed).
func BalanceOf(addr string) int64 {
	if v, ok := claimers.Get(addr); ok {
		return v.(*claimer).Balance
	}
	return 0
}

// Render produces a Markdown dashboard of faucet activity.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Token Faucet\n\n")
	b.WriteString("A toy points faucet. Call `Claim` to receive **")
	b.WriteString(strconv.FormatInt(ClaimAmount, 10))
	b.WriteString(" points** — but only once every **")
	b.WriteString(strconv.FormatInt(CooldownBlocks, 10))
	b.WriteString(" blocks** per address.\n\n")

	b.WriteString("## Stats\n\n")
	b.WriteString("- Total distributed: **")
	b.WriteString(strconv.FormatInt(totalDistributed, 10))
	b.WriteString("** points\n")
	b.WriteString("- Total claims: **")
	b.WriteString(strconv.FormatInt(totalClaims, 10))
	b.WriteString("**\n")
	b.WriteString("- Unique claimers: **")
	b.WriteString(strconv.Itoa(claimers.Size()))
	b.WriteString("**\n")
	b.WriteString("- Current block height: **")
	b.WriteString(strconv.FormatInt(runtime.ChainHeight(), 10))
	b.WriteString("**\n\n")

	b.WriteString("## Claimers\n\n")
	if claimers.Size() == 0 {
		b.WriteString("_No one has claimed yet. Be the first!_\n")
		return b.String()
	}

	b.WriteString("| Address | Balance | Claims | Last claim (height) |\n")
	b.WriteString("| --- | ---: | ---: | ---: |\n")
	claimers.Iterate("", "", func(key string, value interface{}) bool {
		c := value.(*claimer)
		b.WriteString("| `")
		b.WriteString(key)
		b.WriteString("` | ")
		b.WriteString(strconv.FormatInt(c.Balance, 10))
		b.WriteString(" | ")
		b.WriteString(strconv.FormatInt(c.Claims, 10))
		b.WriteString(" | ")
		b.WriteString(strconv.FormatInt(c.LastClaim, 10))
		b.WriteString(" |\n")
		return false
	})

	return b.String()
}
