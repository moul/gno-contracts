// Package crowdfund is an accounting-only port of the classic Solidity
// Kickstarter-style crowdfunding contract to a gno.land realm.
//
// A creator Launches a campaign with a funding goal and a duration (in blocks).
// Backers Pledge (and may Unpledge before the deadline). After the deadline the
// creator can Claim if the goal was met, otherwise backers can Refund.
//
// No real coin moves: pledges are tracked as plain uint64 accounting, exactly
// like the mapping(address => uint) balances of the Solidity original.
package crowdfund

import (
	"strconv"

	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// Campaign holds the state of a single crowdfunding campaign.
type Campaign struct {
	ID       int
	Creator  address
	Goal     uint64
	Deadline int64     // block height after which the campaign is closed
	Pledged  uint64    // running total pledged
	Claimed  bool      // creator already claimed the funds
	pledges  *avl.Tree // backer address (string) -> pledged uint64
}

var (
	campaigns = avl.NewTree() // padded id -> *Campaign (ordered by id)
	nextID    = 1
)

// key zero-pads an id so avl iteration is in numeric order.
func key(id int) string {
	s := strconv.Itoa(id)
	for len(s) < 12 {
		s = "0" + s
	}
	return s
}

func mustGet(id int) *Campaign {
	v := campaigns.Get(key(id))
	if v == nil {
		panic("campaign not found")
	}
	return v.(*Campaign)
}

// Launch creates a new campaign owned by the caller and returns its id.
func Launch(cur realm, goal uint64, durationBlocks int) int {
	if goal == 0 {
		panic("goal must be > 0")
	}
	if durationBlocks <= 0 {
		panic("duration must be > 0")
	}
	caller := unsafe.PreviousRealm().Address()
	id := nextID
	nextID++
	c := &Campaign{
		ID:       id,
		Creator:  caller,
		Goal:     goal,
		Deadline: runtime.ChainHeight() + int64(durationBlocks),
		pledges:  avl.NewTree(),
	}
	campaigns.Set(key(id), c)
	chain.Emit("Launch",
		"id", strconv.Itoa(id),
		"creator", caller.String(),
		"goal", strconv.FormatUint(goal, 10))
	return id
}

// Pledge backs campaign id with amount (before the deadline).
func Pledge(cur realm, id int, amount uint64) {
	if amount == 0 {
		panic("amount must be > 0")
	}
	c := mustGet(id)
	if runtime.ChainHeight() > c.Deadline {
		panic("campaign ended")
	}
	caller := unsafe.PreviousRealm().Address()
	prev := uint64(0)
	if v := c.pledges.Get(caller.String()); v != nil {
		prev = v.(uint64)
	}
	c.pledges.Set(caller.String(), prev+amount)
	c.Pledged += amount
	chain.Emit("Pledge",
		"id", strconv.Itoa(id),
		"from", caller.String(),
		"amount", strconv.FormatUint(amount, 10))
}

// Unpledge withdraws amount from the caller's pledge (before the deadline).
func Unpledge(cur realm, id int, amount uint64) {
	if amount == 0 {
		panic("amount must be > 0")
	}
	c := mustGet(id)
	if runtime.ChainHeight() > c.Deadline {
		panic("campaign ended")
	}
	caller := unsafe.PreviousRealm().Address()
	v := c.pledges.Get(caller.String())
	if v == nil {
		panic("nothing pledged")
	}
	have := v.(uint64)
	if amount > have {
		panic("amount exceeds pledge")
	}
	if remaining := have - amount; remaining == 0 {
		c.pledges.Remove(caller.String())
	} else {
		c.pledges.Set(caller.String(), remaining)
	}
	c.Pledged -= amount
	chain.Emit("Unpledge",
		"id", strconv.Itoa(id),
		"from", caller.String(),
		"amount", strconv.FormatUint(amount, 10))
}

// Claim lets the creator take the funds if the goal was met after the deadline.
func Claim(cur realm, id int) {
	c := mustGet(id)
	if runtime.ChainHeight() <= c.Deadline {
		panic("campaign not ended")
	}
	caller := unsafe.PreviousRealm().Address()
	if caller != c.Creator {
		panic("only creator can claim")
	}
	if c.Pledged < c.Goal {
		panic("goal not reached")
	}
	if c.Claimed {
		panic("already claimed")
	}
	c.Claimed = true
	chain.Emit("Claim",
		"id", strconv.Itoa(id),
		"amount", strconv.FormatUint(c.Pledged, 10))
}

// Refund returns the caller's pledge if the campaign failed after the deadline.
func Refund(cur realm, id int) {
	c := mustGet(id)
	if runtime.ChainHeight() <= c.Deadline {
		panic("campaign not ended")
	}
	if c.Pledged >= c.Goal {
		panic("campaign succeeded, no refund")
	}
	caller := unsafe.PreviousRealm().Address()
	v := c.pledges.Get(caller.String())
	if v == nil {
		panic("nothing to refund")
	}
	amount := v.(uint64)
	c.pledges.Remove(caller.String())
	c.Pledged -= amount
	chain.Emit("Refund",
		"id", strconv.Itoa(id),
		"to", caller.String(),
		"amount", strconv.FormatUint(amount, 10))
}

// --- pure/read-only helpers (also used by Render) ---

// pct returns the funded percentage (0..100).
func pct(pledged, goal uint64) int {
	if goal == 0 {
		return 0
	}
	p := int(pledged * 100 / goal)
	if p > 100 {
		p = 100
	}
	return p
}

// progressBar renders a fixed-width ▓░ bar for pledged/goal.
func progressBar(pledged, goal uint64) string {
	const width = 20
	filled := 0
	if goal > 0 {
		filled = int(pledged * width / goal)
		if filled > width {
			filled = width
		}
	}
	bar := ""
	for i := 0; i < width; i++ {
		if i < filled {
			bar += "▓"
		} else {
			bar += "░"
		}
	}
	return bar
}

// state describes a campaign relative to a given block height.
func state(c *Campaign, height int64) string {
	if height <= c.Deadline {
		return "Active"
	}
	if c.Pledged >= c.Goal {
		if c.Claimed {
			return "Funded (claimed)"
		}
		return "Funded"
	}
	return "Failed"
}

// Render shows all campaigns with a progress bar, goal, pledged and state.
func Render(path string) string {
	if campaigns.Size() == 0 {
		return "# Crowdfund\n\nNo campaigns yet. Call `Launch(goal, durationBlocks)` to start one.\n"
	}
	height := runtime.ChainHeight()
	out := "# Crowdfund\n\n"
	out += "Current block height: **" + strconv.FormatInt(height, 10) + "**\n\n"
	campaigns.Iterate("", "", func(k string, v any) bool {
		c := v.(*Campaign)
		out += "## Campaign #" + strconv.Itoa(c.ID) + "\n\n"
		out += "`" + progressBar(c.Pledged, c.Goal) + "` " + strconv.Itoa(pct(c.Pledged, c.Goal)) + "%\n\n"
		out += "- State: **" + state(c, height) + "**\n"
		out += "- Goal: " + strconv.FormatUint(c.Goal, 10) + "\n"
		out += "- Pledged: " + strconv.FormatUint(c.Pledged, 10) + "\n"
		out += "- Deadline: block " + strconv.FormatInt(c.Deadline, 10) + "\n"
		out += "- Creator: `" + c.Creator.String() + "`\n\n"
		return false
	})
	return out
}
