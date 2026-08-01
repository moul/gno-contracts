package staking

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # Staking Rewards
	//
	// Simplified Synthetix-style staking (accounting-only, no coin transfer).
	//
	// - **Total staked:** 0
	// - **Reward rate:** 100 / block (split across stakers)
	// - **Block height:** 123
	//
	// _No stakers yet. Call `Stake(amount)` to join._
}
