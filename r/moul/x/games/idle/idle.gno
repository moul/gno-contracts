// Package idle is a mine that keeps working while you are not looking at it.
//
// Ore accrues at a rate set by your level. Claim banks it, Upgrade spends the
// bank to dig faster, and at level 10 you may Prestige: start over at level 1
// carrying a permanent multiplier. There are no turns, no block hook and no
// keeper. The realm stores what you had and when, and everything else is
// arithmetic done at the moment somebody asks.
//
// The three decisions that make it a game rather than a counter:
//
//  1. THE MINE IS SMALL. It holds two hours of production and then spills.
//     Without a ceiling the optimal play is to never log in and claim once at
//     the end, which is not a game, it is a savings account. The ceiling is
//     what makes showing up the skill, and it scales with the rate, so two
//     hours stays two hours at every level.
//  2. UPGRADES ARE QUADRATIC AGAINST LINEAR PRODUCTION. Level L costs
//     UpgradeBase*L*L and pays L per period, so the next level always takes
//     about UpgradeBase*L periods to afford: the curve bends without ever
//     stalling. Linear against linear never ends, and exponential against
//     linear dies at level four.
//  3. PRESTIGE EXISTS. Without a reset the leaderboard is settled by whoever
//     started first and nobody else has a reason to join. Trading a level-10
//     mine for a permanent multiplier means a player who starts today has a
//     reachable ceiling.
//
// Time is unix seconds from the block, not block height. A height-denominated
// economy silently repriced itself every time the chain's block time moved,
// and gno.land's has moved from about 4.1s to 3.405s inside a month.
//
// Nothing here rolls dice. Everything a player can do is a pure function of
// when they did it, so there is no block hash to grind and no ordering to
// front-run, and the page can tell you exactly what an action will produce
// before you sign it.
//
// The arithmetic is [p/moul/x/games/accrual](/p/moul/x/games/accrual/v0),
// which owns the one rule that makes lazy time honest: how often you claim
// must not change what you end up with.
package idle

import (
	"errors"
	"strconv"
	"time"

	"gno.land/p/moul/x/games/accrual/v0"
	"gno.land/p/nt/avl/v0"
)

// The economy. Ore is a bare integer: there is no token here, and nothing
// leaves the realm.
const (
	// Period is one minute of unix time. A level-1 mine digs one ore a minute.
	Period = int64(60)
	// CapPeriods is how much production the mine holds before it spills, in
	// periods. It multiplies the rate, so the fill time is level-independent.
	CapPeriods = int64(120)
	// UpgradeBase sets the cost curve: level L costs UpgradeBase*L*L to leave.
	UpgradeBase = int64(10)
	// PrestigeAt is the level at which a reset becomes available.
	PrestigeAt = int64(10)
	// MaxLevel is a safety rail on the cost curve, not a mechanic: it is far
	// beyond anything reachable, and keeps every product inside int64.
	MaxLevel = int64(1000)
	// MaxPrestige bounds the multiplier for the same reason.
	MaxPrestige = int64(100)
)

var errNoMine = errors.New("idle: you have no mine yet, call Start first")

// mine is one player's state. pending and anchor are the accrual pair: what
// was in the mine, and as of when. Everything else is bookkeeping.
type mine struct {
	owner    address
	level    int64
	prestige int64
	pending  int64 // ore in the mine at anchor, capped
	anchor   int64 // unix seconds; the accrual clock, not "last seen"
	banked   int64 // claimed ore, spendable, uncapped
	lifetime int64 // every ore ever claimed, never reset by Prestige
	claims   int64
	started  int64
}

var mines avl.Tree // address string -> *mine

// now is the chain's own clock in unix seconds. time.Now() in a realm returns
// the block timestamp, so it is consensus-deterministic rather than wall time.
func now() int64 { return time.Now().Unix() }

// rate is the accrual Rate for a level and prestige. It is rebuilt on each
// call rather than stored, so a mine's stored state cannot disagree with the
// economy after a redeploy changes a constant.
func rate(level, prestige int64) accrual.Rate {
	perPeriod := level * (1 + prestige)
	r, err := accrual.New(perPeriod, Period, CapPeriods*perPeriod)
	if err != nil {
		panic("idle: " + err.Error())
	}
	return r
}

// upgradeCost is what it costs to leave the given level.
func upgradeCost(level int64) int64 { return UpgradeBase * level * level }

func get(owner address) (*mine, bool) {
	v := mines.Get(owner.String())
	if v == nil {
		return nil, false
	}
	return v.(*mine), true
}

// settle moves the mine's clock to at, banking nothing. It is the only place
// that writes the accrual pair, and it is deliberately the same call Render
// makes read-only, so the page can never promise a number an action will not
// honour.
func (m *mine) settle(at int64) {
	pending, anchor, err := rate(m.level, m.prestige).Advance(m.pending, m.anchor, at)
	if err != nil {
		panic("idle: " + err.Error())
	}
	m.pending, m.anchor = pending, anchor
}

// view is settle without the write, for Render and for the read helpers.
func (m *mine) view(at int64) int64 {
	pending, err := rate(m.level, m.prestige).At(m.pending, m.anchor, at)
	if err != nil {
		panic("idle: " + err.Error())
	}
	return pending
}

// fullAt is the unix second at which this mine starts wasting production.
func (m *mine) fullAt(at int64) int64 {
	pending := m.view(at)
	full, err := rate(m.level, m.prestige).Full(pending, at)
	if err != nil {
		panic("idle: " + err.Error())
	}
	return full
}

// start opens a mine for owner. Non-crossing so tests can drive the clock.
func start(owner address, at int64) string {
	if _, ok := get(owner); ok {
		panic("idle: you already have a mine")
	}
	mines.Set(owner.String(), &mine{
		owner:   owner,
		level:   1,
		anchor:  at,
		started: at,
	})
	return "Mine opened at level 1. It digs " + strconv.FormatInt(Period, 10) +
		"s per ore and holds " + strconv.FormatInt(CapPeriods, 10) + " before it spills."
}

func mustGet(owner address) *mine {
	m, ok := get(owner)
	if !ok {
		panic(errNoMine.Error())
	}
	return m
}

// claim banks everything the mine has dug.
func claim(owner address, at int64) string {
	m := mustGet(owner)
	m.settle(at)
	if m.pending == 0 {
		panic("idle: nothing to claim yet")
	}
	got := m.pending
	m.pending = 0
	m.banked += got
	m.lifetime += got
	m.claims++
	return "Claimed " + strconv.FormatInt(got, 10) + " ore. Banked: " +
		strconv.FormatInt(m.banked, 10) + "."
}

// upgrade spends the bank to raise the level.
func upgrade(owner address, at int64) string {
	m := mustGet(owner)
	m.settle(at)
	if m.level >= MaxLevel {
		panic("idle: this mine is at the maximum level")
	}
	cost := upgradeCost(m.level)
	if m.banked < cost {
		panic("idle: upgrade costs " + strconv.FormatInt(cost, 10) +
			" ore, you have " + strconv.FormatInt(m.banked, 10))
	}
	m.banked -= cost
	m.level++
	return "Level " + strconv.FormatInt(m.level, 10) + ". Digging " +
		strconv.FormatInt(m.level*(1+m.prestige), 10) + " ore per period."
}

// prestige trades the mine for a permanent multiplier.
func prestige(owner address, at int64) string {
	m := mustGet(owner)
	m.settle(at)
	if m.level < PrestigeAt {
		panic("idle: prestige unlocks at level " + strconv.FormatInt(PrestigeAt, 10) +
			", you are at " + strconv.FormatInt(m.level, 10))
	}
	if m.prestige >= MaxPrestige {
		panic("idle: this mine is at the maximum prestige")
	}
	m.prestige++
	m.level = 1
	m.pending = 0
	m.banked = 0
	m.anchor = at
	return "Prestige " + strconv.FormatInt(m.prestige, 10) +
		". Back to level 1, digging " + strconv.FormatInt(1+m.prestige, 10) +
		" ore per period. Lifetime ore: " + strconv.FormatInt(m.lifetime, 10) + "."
}

// Start opens a mine for the caller. One per address, forever: Prestige is the
// only way to start over, and it keeps your lifetime total.
func Start(cur realm) string {
	return start(cur.Previous().Address(), now())
}

// Claim banks whatever the mine has dug since the last claim. Claiming often
// and claiming rarely pay exactly the same, by construction: see accrual.
func Claim(cur realm) string {
	return claim(cur.Previous().Address(), now())
}

// Upgrade spends banked ore to raise the level, which raises both the rate and
// the ceiling.
func Upgrade(cur realm) string {
	return upgrade(cur.Previous().Address(), now())
}

// Prestige resets a level-10 mine to level 1 for a permanent +1 multiplier.
// Banked and pending ore are burned; the lifetime total is not.
func Prestige(cur realm) string {
	return prestige(cur.Previous().Address(), now())
}

// Pending reports what is sitting in an address's mine right now, unclaimed.
func Pending(owner address) int64 {
	m, ok := get(owner)
	if !ok {
		return 0
	}
	return m.view(now())
}

// Banked reports an address's spendable ore.
func Banked(owner address) int64 {
	m, ok := get(owner)
	if !ok {
		return 0
	}
	return m.banked
}

// Level reports an address's level and prestige.
func Level(owner address) (int64, int64) {
	m, ok := get(owner)
	if !ok {
		return 0, 0
	}
	return m.level, m.prestige
}

// FullAt reports the unix second at which an address's mine starts wasting
// what it digs, which is the only deadline in this game.
func FullAt(owner address) int64 {
	m, ok := get(owner)
	if !ok {
		return 0
	}
	return m.fullAt(now())
}
