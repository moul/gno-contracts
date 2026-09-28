// Package across reads one address across fifteen other realms that are
// already live, and renders everything they will say about it on one page.
//
// It is a composability demo with a working product hiding inside it. The
// realms it reads were written months apart, by nobody coordinating, and none
// of them knows this one exists. Not a line of them changed to make this
// possible: the only requirement any of them had to meet was NOT declaring
// `private = true`, which is what lets another realm import it at all.
//
// # Why this realm holds no state and extracts no library
//
// Every other realm here splits into a pure `p/` and a thin `r/`. This one
// cannot, and that is the point: its entire content is the wiring. Fifteen
// import lines, one call each, and a table. Extract a library and what is left
// on both sides is empty.
//
// # What it measures, besides balances
//
// The signatures below are the honest half of the demo. Eight of these realms
// hold a per-address balance and they agree on nothing:
//
//	erc20, vestoken, wrapped     BalanceOf(address) uint64
//	pairs/aaa, pairs/bbb         BalanceOf(address) int64
//	grc20faucet                  BalanceOf(symbol string, owner address) int64
//	wikicoin                     BalanceOf(address) uint
//	dice                         RollsOf(addr string) []int
//
// Three integer widths, two signednesses, one that takes the address as a
// string, one that needs a symbol first. Composition works anyway, because a
// gno import is a type-checked contract with a permanent artifact behind it and
// not a call convention anyone has to agree on in advance. It just costs one
// hand-written adapter per source, which is what the report function is.
//
// # The two sources that could not be read
//
//   - r/moul/x/amm/v0 exports SharesOf(keyA, keyB string, owner address), and
//     it routes through mustPool, which PANICS when the pool does not exist.
//     A getter that panics is not composable: fifteen sources on one page means
//     one panicking source takes the whole page down, and a wrapper cannot
//     recover, because recover() does not catch a cross-realm abort. So amm
//     contributes PoolCount() to the index and nothing to a report.
//   - r/moul/demo/vault/v0 exports MyBalance() with no address parameter. It
//     answers for whoever is calling, which from here is this realm, so the
//     value is structurally unreadable from outside.
//
// Neither is a bug in those realms. Both are what a getter looks like when
// nobody has tried to call it from another realm yet.
package across

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"

	"gno.land/r/moul/demo/wikicoin/v0"
	"gno.land/r/moul/reactions/v0"
	"gno.land/r/moul/x/amm/v0"
	"gno.land/r/moul/x/daily/dice/v0"
	"gno.land/r/moul/x/daily/erc20/v0"
	"gno.land/r/moul/x/daily/lottery/v0"
	"gno.land/r/moul/x/daily/ratelimitdemo/v0"
	"gno.land/r/moul/x/daily/staking/v0"
	"gno.land/r/moul/x/daily/streak/v0"
	"gno.land/r/moul/x/daily/vestoken/v0"
	"gno.land/r/moul/x/daily/wrapped/v0"
	"gno.land/r/moul/x/grc20faucet/v0"
	"gno.land/r/moul/x/pairs/aaa/v0"
	"gno.land/r/moul/x/pairs/aaabbb/v0"
	"gno.land/r/moul/x/pairs/bbb/v0"
)

// reactionPage is the page key handed to r/moul/reactions. Reactions are keyed
// on an arbitrary page string rather than on a realm, so a reader of this
// report is asked about the same page /u/moul shows.
const reactionPage = "gno.land/r/moul/home"

// Self is this realm's own package path, exported so a caller can build a link
// back without hardcoding the version.
const Self = "gno.land/r/moul/x/across/v0"

// A fact is one answer from one source realm about one address.
//
// zero is carried separately from value because "0" and "none" are the common
// answer and the table is worth reading only for the rows that are not that.
type fact struct {
	source string // package path, without the gno.land/ prefix
	what   string
	value  string
	zero   bool
}

// Report collects what every wired source says about who.
//
// Every call in here is a plain exported read on another realm: no cur realm,
// no cross, nothing written. A read with no realm parameter is borrowed rather
// than entered (AGENTS.md), so none of these realms even observes a caller.
func Report(who address) []fact {
	out := []fact{}

	add := func(source, what string, n int64, unit string) {
		v := strconv.FormatInt(n, 10)
		if unit != "" {
			v += " " + unit
		}
		out = append(out, fact{source: source, what: what, value: v, zero: n == 0})
	}

	// Balances. Eight sources, five signatures.
	add("r/moul/x/daily/erc20/v0", "balance", int64(erc20.BalanceOf(who)), erc20.Symbol())
	add("r/moul/x/daily/vestoken/v0", "liquid balance", int64(vestoken.BalanceOf(who)), vestoken.Symbol())
	add("r/moul/x/daily/wrapped/v0", "wrapped balance", int64(wrapped.BalanceOf(who)), "WGNOT")
	add("r/moul/demo/wikicoin/v0", "balance", int64(wikicoin.BalanceOf(who)), "WIKI")
	add("r/moul/x/pairs/aaa/v0", "balance", aaa.BalanceOf(who), "AAA")
	add("r/moul/x/pairs/bbb/v0", "balance", bbb.BalanceOf(who), "BBB")
	add("r/moul/x/grc20faucet/v0", "balance", grc20faucet.BalanceOf("RED", who), "RED")
	add("r/moul/x/grc20faucet/v0", "balance", grc20faucet.BalanceOf("BLUE", who), "BLUE")

	// A grant is three numbers, so it does not fit the add helper.
	total, claimed, claimable := vestoken.GrantOf(who)
	out = append(out, fact{
		source: "r/moul/x/daily/vestoken/v0",
		what:   "vesting grant",
		value: strconv.FormatUint(total, 10) + " total, " +
			strconv.FormatUint(claimed, 10) + " claimed, " +
			strconv.FormatUint(claimable, 10) + " claimable",
		zero: total == 0,
	})

	// Positions.
	add("r/moul/x/pairs/aaabbb/v0", "LP shares", aaabbb.SharesOf(who), "")
	add("r/moul/x/daily/staking/v0", "staked", int64(staking.StakedOf(who)), "")
	add("r/moul/x/daily/staking/v0", "unclaimed rewards", int64(staking.Earned(who)), "")

	// Activity.
	add("r/moul/x/daily/streak/v0", "current streak", int64(streak.Current(who)), "day(s)")
	add("r/moul/x/daily/streak/v0", "best streak", int64(streak.Best(who)), "day(s)")
	add("r/moul/x/daily/dice/v0", "dice rolled", int64(len(dice.RollsOf(who.String()))), "")
	add("r/moul/x/daily/ratelimitdemo/v0", "rate-limit tokens left", int64(ratelimitdemo.Tokens(who)), "")

	entered := "no"
	if lottery.HasEntered(who) {
		entered = "yes, round " + strconv.Itoa(lottery.CurrentRound())
	}
	out = append(out, fact{
		source: "r/moul/x/daily/lottery/v0",
		what:   "entered the lottery",
		value:  entered,
		zero:   !lottery.HasEntered(who),
	})

	// reactions answers with a palette key, already validated at write time, so
	// it never carries caller markdown into this table.
	react := reactions.ReactionOf(reactionPage, who)
	shown := react
	if shown == "" {
		shown = "none"
	}
	out = append(out, fact{
		source: "r/moul/reactions/v0",
		what:   "reaction on " + reactionPage,
		value:  shown,
		zero:   react == "",
	})

	return out
}

// sourceRealms is every realm this one imports for its data, in import order.
// It is the single place the count comes from: the index table has one row per
// entry and TestSourcesCoverReport checks that Report names nothing else.
//
// Fifteen entries, which is the number the prose says. TestSourceCount pins it.
var sourceRealms = []string{
	"r/moul/x/daily/erc20/v0",
	"r/moul/x/daily/vestoken/v0",
	"r/moul/x/daily/wrapped/v0",
	"r/moul/demo/wikicoin/v0",
	"r/moul/x/pairs/aaa/v0",
	"r/moul/x/pairs/bbb/v0",
	"r/moul/x/grc20faucet/v0",
	"r/moul/x/pairs/aaabbb/v0",
	"r/moul/x/amm/v0",
	"r/moul/x/daily/staking/v0",
	"r/moul/x/daily/streak/v0",
	"r/moul/x/daily/dice/v0",
	"r/moul/x/daily/lottery/v0",
	"r/moul/x/daily/ratelimitdemo/v0",
	"r/moul/reactions/v0",
}

// Sources reports how many realms this one reads.
func Sources() int { return len(sourceRealms) }

func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	addr := address(path)
	if !addr.IsValid() {
		return "# across\n\n" + ui.Empty(ui.Inline(ui.Short(path))+" is not a valid address.") +
			"\n[back to the index](/r/moul/x/across/v0)\n"
	}
	return renderAddress(addr)
}

func renderAddress(who address) string {
	var b strings.Builder
	b.WriteString("# across: " + ui.AddrFull(who) + "\n\n")
	b.WriteString("What " + strconv.Itoa(Sources()) + " independently deployed realms say about this address. ")
	b.WriteString("None of them was changed to answer.\n\n")

	facts := Report(who)

	live := ui.NewTable("source", "fact", "value")
	quiet := 0
	for _, f := range facts {
		if f.zero {
			quiet++
			continue
		}
		live.Row("[`"+f.source+"`](/"+f.source+")", f.what, f.value)
	}

	if live.Len() == 0 {
		b.WriteString(ui.Empty("Every one of the " + strconv.Itoa(len(facts)) +
			" reads came back empty. This address has never touched any of them."))
		b.WriteString("\n")
	} else {
		b.WriteString("## Answers\n\n")
		b.WriteString(live.String())
		b.WriteString("\n")
		b.WriteString(strconv.Itoa(quiet) + " of " + strconv.Itoa(len(facts)) +
			" reads came back empty and are hidden.\n\n")
	}

	b.WriteString("[back to the index](/r/moul/x/across/v0)\n")
	return b.String()
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# across\n\n")
	b.WriteString("One address, read across " + strconv.Itoa(Sources()) + " realms that are already on chain.\n\n")
	b.WriteString("Open `/r/moul/x/across/v0:<address>` to get the report. ")
	b.WriteString("Example: [/r/moul/x/across/v0:" + exampleAddr + "](/r/moul/x/across/v0:" + exampleAddr + ").\n\n")

	b.WriteString("## Why this realm exists\n\n")
	b.WriteString("A gno realm that does not declare `private = true` can be imported by any ")
	b.WriteString("other realm, forever, at a path that can never be replaced. That makes every ")
	b.WriteString("exported read on it a permanent public API. This realm is what happens when ")
	b.WriteString("somebody actually uses " + strconv.Itoa(Sources()) + " of them at once.\n\n")
	b.WriteString("Nothing here was negotiated. No registry, no interface, no shared base ")
	b.WriteString("package, no version handshake, and no change to any source realm.\n\n")

	b.WriteString("## The sources, and what each one is showing right now\n\n")
	t := ui.NewTable("realm", "global reading")
	t.Row("[`r/moul/x/daily/erc20/v0`](/r/moul/x/daily/erc20/v0)",
		erc20.Symbol()+" supply "+strconv.FormatUint(erc20.TotalSupply(), 10))
	t.Row("[`r/moul/x/daily/vestoken/v0`](/r/moul/x/daily/vestoken/v0)",
		vestoken.Symbol()+" supply "+strconv.FormatUint(vestoken.TotalSupply(), 10))
	t.Row("[`r/moul/x/daily/wrapped/v0`](/r/moul/x/daily/wrapped/v0)",
		"wrapped supply "+strconv.FormatUint(wrapped.TotalSupply(), 10))
	t.Row("[`r/moul/demo/wikicoin/v0`](/r/moul/demo/wikicoin/v0)", "per-address balances only")
	t.Row("[`r/moul/x/pairs/aaa/v0`](/r/moul/x/pairs/aaa/v0)",
		"AAA supply "+strconv.FormatInt(aaa.TotalSupply(), 10))
	t.Row("[`r/moul/x/pairs/bbb/v0`](/r/moul/x/pairs/bbb/v0)",
		"BBB supply "+strconv.FormatInt(bbb.TotalSupply(), 10))
	t.Row("[`r/moul/x/grc20faucet/v0`](/r/moul/x/grc20faucet/v0)",
		"RED supply "+strconv.FormatInt(grc20faucet.TotalSupply("RED"), 10)+
			", BLUE supply "+strconv.FormatInt(grc20faucet.TotalSupply("BLUE"), 10))
	t.Row("[`r/moul/x/pairs/aaabbb/v0`](/r/moul/x/pairs/aaabbb/v0)",
		"LP shares "+strconv.FormatInt(aaabbb.TotalShares(), 10))
	t.Row("[`r/moul/x/amm/v0`](/r/moul/x/amm/v0)",
		strconv.Itoa(amm.PoolCount())+" pool(s), index only (see below)")
	t.Row("[`r/moul/x/daily/staking/v0`](/r/moul/x/daily/staking/v0)", "per-address stake and rewards")
	t.Row("[`r/moul/x/daily/streak/v0`](/r/moul/x/daily/streak/v0)",
		"day "+strconv.FormatInt(streak.Day(), 10))
	t.Row("[`r/moul/x/daily/dice/v0`](/r/moul/x/daily/dice/v0)",
		strconv.Itoa(dice.Total())+" roll(s) all time")
	t.Row("[`r/moul/x/daily/lottery/v0`](/r/moul/x/daily/lottery/v0)",
		"round "+strconv.Itoa(lottery.CurrentRound())+", "+
			strconv.Itoa(lottery.NumEntrants())+" entrant(s)")
	t.Row("[`r/moul/x/daily/ratelimitdemo/v0`](/r/moul/x/daily/ratelimitdemo/v0)", "per-address bucket")
	t.Row("[`r/moul/reactions/v0`](/r/moul/reactions/v0)",
		strconv.Itoa(reactions.Pages())+" page(s) reacted to")
	b.WriteString(t.String())
	b.WriteString("\n")

	b.WriteString("## What it cost\n\n")
	b.WriteString("Eight of these hold a per-address balance, and they share no signature: ")
	b.WriteString("`uint64` three times, `int64` twice, `uint` once, one that wants a symbol ")
	b.WriteString("before the address, one that wants the address as a `string`. Every source ")
	b.WriteString("therefore needs its own adapter line. That is the whole cost, and it is paid ")
	b.WriteString("once by the reader rather than up front by fifteen authors.\n\n")

	b.WriteString("## The two that could not be read\n\n")
	b.WriteString("- `r/moul/x/amm/v0` routes `SharesOf` through a helper that panics on an ")
	b.WriteString("unknown pool. One panicking source takes down a page built from " +
		strconv.Itoa(Sources()) + ", and ")
	b.WriteString("`recover()` does not catch a cross-realm abort, so only its `PoolCount()` is ")
	b.WriteString("safe to call from here.\n")
	b.WriteString("- `r/moul/demo/vault/v0` exports `MyBalance()` with no address parameter. It ")
	b.WriteString("answers for its caller, which from here is this realm.\n\n")
	b.WriteString("Neither is a bug. Both are what a getter looks like before anyone has tried ")
	b.WriteString("to call it from another realm.\n")

	return b.String()
}

// exampleAddr is moul's address, used only to give the index a link that
// resolves to a real report instead of an empty one.
const exampleAddr = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
