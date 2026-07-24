// Package vestoken is a fungible token where new supply is never handed out
// instantly — it ports the idea behind Solidity's VestingWallet / linear
// token-streaming contracts (e.g. Sablier) into a single gno.land realm.
//
// MintVested opens a linear vesting grant instead of crediting a balance
// directly. The beneficiary calls Claim over time to pull whatever has
// unlocked so far into their liquid, transferable balance. State is
// package-level and persistent; state-mutating functions are crossing
// functions (`cur realm`) per the gno 0.9 interrealm convention.
package vestoken

import (
	"chain/runtime"
	"errors"
	"sort"
	"strconv"
	"strings"
)

const (
	name   = "VestToken"
	symbol = "VEST"
)

// grant is one linear vesting schedule: `total` unlocks evenly from `start`
// to `start+duration` (measured in block height), and `claimed` tracks how
// much of the unlocked amount the beneficiary has already pulled.
type grant struct {
	total    uint64
	claimed  uint64
	start    int64
	duration int64
}

var (
	// balances holds liquid, already-claimed tokens — transferable like a
	// normal ERC-20 balance.
	balances = map[address]uint64{}
	// grants holds at most one active vesting schedule per beneficiary.
	grants = map[address]*grant{}
	// totalSupply is every token ever minted (vesting or liquid).
	totalSupply uint64
)

var (
	errZeroAddress   = errors.New("vestoken: zero address")
	errZeroAmount    = errors.New("vestoken: amount must be positive")
	errZeroDuration  = errors.New("vestoken: duration must be positive")
	errGrantActive   = errors.New("vestoken: beneficiary already has an unclaimed grant")
	errNoGrant       = errors.New("vestoken: no active grant for this account")
	errInsufficient  = errors.New("vestoken: insufficient balance")
	errOverflow      = errors.New("vestoken: supply overflow")
	errSpoofedRealm  = errors.New("vestoken: spoofed realm")
	errNotUser       = errors.New("vestoken: caller is not a user account")
)

// caller returns the immediate caller's address for a crossing function,
// enforcing the gno 0.9 authentication primitive: cur must be the live
// crossing frame before its Previous() is trusted.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic(errSpoofedRealm)
	}
	prev := cur.Previous()
	if !prev.IsUser() {
		panic(errNotUser)
	}
	return prev.Address()
}

// MintVested opens a new linear vesting grant for `to`: `amount` tokens
// unlock block-by-block over the next `durationBlocks` blocks, starting now.
// A beneficiary may only hold one active grant at a time. Crossing function.
func MintVested(cur realm, to address, amount uint64, durationBlocks int64) {
	_ = caller(cur) // authenticate the crossing frame; anyone may open a grant in this demo
	if !to.IsValid() {
		panic(errZeroAddress)
	}
	if amount == 0 {
		panic(errZeroAmount)
	}
	if durationBlocks <= 0 {
		panic(errZeroDuration)
	}
	if g, ok := grants[to]; ok && g.claimed < g.total {
		panic(errGrantActive)
	}
	if totalSupply+amount < totalSupply {
		panic(errOverflow)
	}
	totalSupply += amount
	grants[to] = &grant{
		total:    amount,
		start:    runtime.ChainHeight(),
		duration: durationBlocks,
	}
}

// Claim pulls whatever has unlocked so far from the caller's grant into
// their liquid balance, and returns how much was claimed. Crossing function.
func Claim(cur realm) uint64 {
	who := caller(cur)
	g, ok := grants[who]
	if !ok {
		panic(errNoGrant)
	}

	unlocked := vestedAmount(g, runtime.ChainHeight())
	claimable := unlocked - g.claimed
	if claimable == 0 {
		return 0
	}

	g.claimed = unlocked
	balances[who] += claimable
	if g.claimed >= g.total {
		delete(grants, who)
	}
	return claimable
}

// vestedAmount computes how much of g has unlocked by the given height.
func vestedAmount(g *grant, height int64) uint64 {
	elapsed := height - g.start
	if elapsed <= 0 {
		return 0
	}
	if elapsed >= g.duration {
		return g.total
	}
	return g.total * uint64(elapsed) / uint64(g.duration)
}

// Transfer moves `amount` of the caller's liquid (already-claimed) balance
// to `to`. Crossing function.
func Transfer(cur realm, to address, amount uint64) {
	from := caller(cur)
	if !to.IsValid() {
		panic(errZeroAddress)
	}
	if amount == 0 {
		return
	}
	if balances[from] < amount {
		panic(errInsufficient)
	}
	balances[from] -= amount
	balances[to] += amount
}

// BalanceOf returns the liquid (claimed, transferable) balance of holder.
func BalanceOf(holder address) uint64 {
	return balances[holder]
}

// GrantOf returns the beneficiary's active grant, if any: total amount,
// amount claimed so far, and the amount currently claimable.
func GrantOf(beneficiary address) (total uint64, claimed uint64, claimable uint64) {
	g, ok := grants[beneficiary]
	if !ok {
		return 0, 0, 0
	}
	unlocked := vestedAmount(g, runtime.ChainHeight())
	return g.total, g.claimed, unlocked - g.claimed
}

// TotalSupply returns every token ever minted, vesting or liquid.
func TotalSupply() uint64 { return totalSupply }

// Name returns the token name.
func Name() string { return name }

// Symbol returns the token symbol.
func Symbol() string { return symbol }

// Render produces the gnoweb Markdown view: metadata, active vesting
// grants, and liquid balances — both tables sorted by address for
// deterministic output. Render is NOT a crossing function.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# " + name + " (" + symbol + ")\n\n")
	b.WriteString("A linearly-vesting ERC-20-style token on gno.land — ")
	b.WriteString("new supply unlocks block-by-block instead of landing instantly.\n\n")
	b.WriteString("- **Name:** " + name + "\n")
	b.WriteString("- **Symbol:** " + symbol + "\n")
	b.WriteString("- **Total supply:** " + strconv.FormatUint(totalSupply, 10) + "\n")
	b.WriteString("- **Current height:** " + strconv.FormatInt(runtime.ChainHeight(), 10) + "\n\n")

	b.WriteString("## Active grants\n\n")
	grantKeys := sortedAddrKeys(grantAddrs())
	if len(grantKeys) == 0 {
		b.WriteString("_No active grants — call `MintVested` to open one._\n\n")
	} else {
		b.WriteString("| Beneficiary | Total | Claimed | Claimable now |\n")
		b.WriteString("| --- | ---: | ---: | ---: |\n")
		for _, k := range grantKeys {
			g := grants[address(k)]
			unlocked := vestedAmount(g, runtime.ChainHeight())
			b.WriteString("| `" + k + "` | " +
				strconv.FormatUint(g.total, 10) + " | " +
				strconv.FormatUint(g.claimed, 10) + " | " +
				strconv.FormatUint(unlocked-g.claimed, 10) + " |\n")
		}
		b.WriteString("\n")
	}

	b.WriteString("## Liquid balances\n\n")
	balKeys := sortedAddrKeys(balanceAddrs())
	if len(balKeys) == 0 {
		b.WriteString("_No claimed balances yet — call `Claim` once a grant has unlocked._\n")
		return b.String()
	}
	b.WriteString("| Address | Amount |\n")
	b.WriteString("| --- | ---: |\n")
	for _, k := range balKeys {
		b.WriteString("| `" + k + "` | " +
			strconv.FormatUint(balances[address(k)], 10) + " |\n")
	}

	return b.String()
}

func grantAddrs() []string {
	keys := make([]string, 0, len(grants))
	for addr := range grants {
		keys = append(keys, addr.String())
	}
	return keys
}

func balanceAddrs() []string {
	keys := make([]string, 0, len(balances))
	for addr, bal := range balances {
		if bal == 0 {
			continue
		}
		keys = append(keys, addr.String())
	}
	return keys
}

func sortedAddrKeys(keys []string) []string {
	sort.Strings(keys)
	return keys
}
