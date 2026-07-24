// Package staking is a simplified, accounting-only port of Synthetix
// StakingRewards to gno.land. Users stake a fungible amount; rewards accrue
// every block, proportional to each staker's share of the total staked,
// at a fixed rewardPerBlock. There is no real coin transfer — balances and
// rewards are plain uint64 accounting (a demonstration of the classic
// "reward-per-token" accumulator pattern).
package staking

import (
	"strconv"

	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

const (
	// rewardPerBlock is the fixed number of reward units distributed across
	// ALL stakers on every block, split by stake share.
	rewardPerBlock = uint64(100)
	// precision scales the reward-per-token accumulator to avoid truncation.
	precision = uint64(1_000_000)
)

type account struct {
	staked     uint64 // currently staked amount
	rewardPaid uint64 // reward-per-token snapshot at the account's last update
	reward     uint64 // accrued-but-unclaimed rewards
	minted     uint64 // rewards moved into the caller's reward balance
}

var (
	accounts          avl.Tree // address string -> *account
	totalStaked       uint64
	rewardPerTokenAcc uint64 // global accumulator, scaled by precision
	lastUpdateBlock   uint64
)

// --- pure helpers (unit-tested) ------------------------------------------

// computeRewardPerToken advances the accumulator by the rewards earned per
// staked unit over `elapsed` blocks. With no stake, the accumulator is frozen.
func computeRewardPerToken(stored, rate, elapsed, total uint64) uint64 {
	if total == 0 {
		return stored
	}
	return stored + (rate*elapsed*precision)/total
}

// computeEarned returns total rewards owed to an account given its stake, the
// current accumulator, the accumulator value already paid, and prior accrual.
func computeEarned(balance, rptCurrent, rptPaid, accrued uint64) uint64 {
	return accrued + (balance*(rptCurrent-rptPaid))/precision
}

// --- internals ------------------------------------------------------------

func currentBlock() uint64 { return uint64(runtime.ChainHeight()) }

func getOrCreate(addr string) *account {
	if v := accounts.Get(addr); v != nil {
		return v.(*account)
	}
	acc := &account{}
	accounts.Set(addr, acc)
	return acc
}

// accrue rolls the global accumulator forward to the current block and folds
// the caller's freshly-earned rewards into its stored balance. Mirrors the
// Synthetix `updateReward(account)` modifier.
func accrue(addr string) *account {
	elapsed := currentBlock() - lastUpdateBlock
	rewardPerTokenAcc = computeRewardPerToken(rewardPerTokenAcc, rewardPerBlock, elapsed, totalStaked)
	lastUpdateBlock = currentBlock()

	acc := getOrCreate(addr)
	acc.reward = computeEarned(acc.staked, rewardPerTokenAcc, acc.rewardPaid, acc.reward)
	acc.rewardPaid = rewardPerTokenAcc
	return acc
}

// --- exported transactions (crossing) ------------------------------------

// Stake adds `amount` to the caller's staked balance.
func Stake(cur realm, amount uint64) {
	if amount == 0 {
		panic("staking: amount must be > 0")
	}
	addr := unsafe.PreviousRealm().Address().String()
	acc := accrue(addr)
	acc.staked += amount
	totalStaked += amount
	chain.Emit("Staked", "addr", addr, "amount", strconv.FormatUint(amount, 10))
}

// Withdraw removes `amount` from the caller's staked balance.
func Withdraw(cur realm, amount uint64) {
	if amount == 0 {
		panic("staking: amount must be > 0")
	}
	addr := unsafe.PreviousRealm().Address().String()
	acc := accrue(addr)
	if amount > acc.staked {
		panic("staking: insufficient staked balance")
	}
	acc.staked -= amount
	totalStaked -= amount
	chain.Emit("Withdrawn", "addr", addr, "amount", strconv.FormatUint(amount, 10))
}

// GetReward mints all accrued rewards into the caller's reward balance and
// resets the accrual counter. Returns the amount minted this call.
func GetReward(cur realm) uint64 {
	addr := unsafe.PreviousRealm().Address().String()
	acc := accrue(addr)
	claimed := acc.reward
	acc.reward = 0
	acc.minted += claimed
	chain.Emit("RewardPaid", "addr", addr, "amount", strconv.FormatUint(claimed, 10))
	return claimed
}

// --- read-only ------------------------------------------------------------

// Earned reports the rewards currently owed to `addr` (accrued but unminted),
// projected to the current block without mutating any state.
func Earned(addr address) uint64 {
	v := accounts.Get(addr.String())
	if v == nil {
		return 0
	}
	acc := v.(*account)
	elapsed := currentBlock() - lastUpdateBlock
	rpt := computeRewardPerToken(rewardPerTokenAcc, rewardPerBlock, elapsed, totalStaked)
	return computeEarned(acc.staked, rpt, acc.rewardPaid, acc.reward)
}

// StakedOf reports the current staked balance of `addr`.
func StakedOf(addr address) uint64 {
	if v := accounts.Get(addr.String()); v != nil {
		return v.(*account).staked
	}
	return 0
}

// Render renders pool stats and a stakers table.
func Render(path string) string {
	out := "# Staking Rewards\n\n"
	out += "Simplified Synthetix-style staking (accounting-only, no coin transfer).\n\n"
	out += "- **Total staked:** " + strconv.FormatUint(totalStaked, 10) + "\n"
	out += "- **Reward rate:** " + strconv.FormatUint(rewardPerBlock, 10) + " / block (split across stakers)\n"
	out += "- **Block height:** " + strconv.FormatUint(currentBlock(), 10) + "\n\n"

	if accounts.Size() == 0 {
		out += "_No stakers yet. Call `Stake(amount)` to join._\n"
		return out
	}

	out += "## Stakers\n\n"
	out += "| Address | Staked | Earned (pending) | Minted |\n"
	out += "|---|---|---|---|\n"

	elapsed := currentBlock() - lastUpdateBlock
	rpt := computeRewardPerToken(rewardPerTokenAcc, rewardPerBlock, elapsed, totalStaked)
	accounts.Iterate("", "", func(key string, value interface{}) bool {
		acc := value.(*account)
		earned := computeEarned(acc.staked, rpt, acc.rewardPaid, acc.reward)
		out += "| " + key +
			" | " + strconv.FormatUint(acc.staked, 10) +
			" | " + strconv.FormatUint(earned, 10) +
			" | " + strconv.FormatUint(acc.minted, 10) + " |\n"
		return false
	})
	return out
}
