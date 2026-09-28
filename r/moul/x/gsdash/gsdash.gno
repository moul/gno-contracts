// Package gsdash renders one address's whole GnoSwap footprint on chain, with
// no indexer and no off-chain query: balances, liquidity positions, what each
// one is worth right now, and what it has earned but not collected.
//
// It reads GnoSwap through the unversioned proxy paths (r/gnoswap/position and
// friends) rather than their /vN implementations, so a GnoSwap implementation
// upgrade does not reach this realm.
package gsdash

import (
	"chain"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/nt/ufmt/v0"

	"gno.land/r/gnoswap/gnft"
	"gno.land/r/gnoswap/gns"
	"gno.land/r/gnoswap/gov/xgns"
	"gno.land/r/gnoswap/position"
	"gno.land/r/gnoswap/staker"
)

// scanWindow is how many stored position records one page walks.
//
// There is no address-to-positions index anywhere in GnoSwap: gnft is a plain
// grc721 with no enumerable extension, so the only way to find an address's
// positions is to walk the records and ask each one who owns it. GnoSwap's own
// position realm renders a keyed lookup and says out loud that it "does not
// enumerate positions", which is the same ceiling talking. Queries get
// 3,000,000,000 gas (maxGasQuery, gno.land/pkg/sdk/vm/keeper.go), so the walk
// is paged rather than unbounded, and the page footer links the next one.
const scanWindow = 250

// stakerPath is the realm that custodies a staked position's NFT. Staking
// transfers the token to it, so for anything staked the grc721 owner is this
// address and not a person: see resolveOwner.
const stakerPath = "gno.land/r/gnoswap/staker"

// Render serves three routes: the index, an address page, and the next page of
// an address whose records did not fit in one scan window.
//
//	""                  the index
//	"g1..."             that address, scanning from record 0
//	"g1.../from/500"    the same, scanning from record 500
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}

	addrPart, offset, ok := parsePath(path)
	if !ok {
		return ui.Empty("Not a route. Try `" + shortSelf + ":g1...`.")
	}
	addr := address(addrPart)
	if !addr.IsValid() {
		// Escaped rather than echoed: the path is whatever the reader typed.
		return ui.Empty("Not a valid address: " + ui.Inline(addrPart))
	}
	return renderAddress(addr, offset)
}

// shortSelf is this realm's own render prefix, used in the links it prints.
const shortSelf = "/r/moul/x/gsdash/v0"

func renderIndex() string {
	s := "# GnoSwap dashboard\n\n"
	s += "Everything one address has on GnoSwap, read live from the chain: GNS and xGNS " +
		"balances, every liquidity position with what it holds right now, the fees it has " +
		"accrued, and the emission rewards waiting to be collected.\n\n"
	s += ufmt.Sprintf("Open an address: `%s:g1...`\n\n", shortSelf)

	t := ui.NewTable("What", "Now")
	t.Row("Stored position records", ufmt.Sprintf("%d", position.GetPositions().Size()))
	t.Row("Position NFTs in circulation", ufmt.Sprintf("%d", gnft.TotalSupply()))
	t.Row("Records walked per page", ufmt.Sprintf("%d", scanWindow))
	s += t.String()

	s += "\nRecords include burned positions, so the count is not a count of live liquidity.\n"
	return s
}

func renderAddress(addr address, offset int) string {
	s := ufmt.Sprintf("# %s\n\n", ui.AddrFull(addr))

	nfts, err := gnft.BalanceOf(addr)
	if err != nil {
		nfts = 0
	}
	t := ui.NewTable("GNS", "xGNS", "Position NFTs held")
	t.Row(
		ufmt.Sprintf("%d", gns.BalanceOf(addr)),
		ufmt.Sprintf("%d", xgns.BalanceOf(addr)),
		ufmt.Sprintf("%d", nfts),
	)
	s += t.String() + "\n"

	s += ufmt.Sprintf("## Positions\n\nRecords %d to %d of %d.\n\n",
		offset, offset+scanWindow, position.GetPositions().Size())
	s += renderPositions(addr, offset)

	if next := offset + scanWindow; next < position.GetPositions().Size() {
		s += ufmt.Sprintf("\n[Next %d records](%s:%s/from/%d)\n", scanWindow, shortSelf, addr.String(), next)
	}
	return s
}

// renderPositions walks one window of the position records and prints the rows
// belonging to addr.
//
// The walk is deliberately cheap per record and expensive per hit: identifying
// the owner is one or two tree lookups, while the price math behind IsInRange,
// the token balances and the unclaimed fees costs far more. Only a row that is
// actually printed pays for it.
func renderPositions(addr address, offset int) string {
	t := ui.NewTable("ID", "Pool", "Ticks", "Liquidity", "In range", "Holds", "Uncollected fees", "Staked", "Reward")

	position.GetPositions().IterateByOffset(offset, scanWindow, func(key string, _ any) bool {
		id, err := strconv.ParseUint(key, 10, 64)
		if err != nil {
			return false
		}
		owner, staked, ok := resolveOwner(id)
		if !ok || owner != addr {
			return false
		}
		t.Row(row(id, staked)...)
		return false
	})

	return t.OrEmpty("No positions in this window.")
}

// row is the expensive half: everything here reads pool price state or recomputes
// a fee, so it runs for a matched position and never for a scanned one.
func row(id uint64, staked bool) []string {
	poolKey, _ := position.GetPositionPoolKey(id)
	lower, upper, _ := position.GetPositionTicks(id)
	liquidity, _ := position.GetPositionLiquidity(id)
	inRange, _ := position.IsInRange(id)
	amount0, amount1, _ := position.GetPositionTokenBalances(id)
	fee0, fee1, _ := position.GetUnclaimedFee(id)

	reward := "-"
	if staked {
		if r, err := staker.CollectableEmissionReward(id); err == nil {
			reward = ufmt.Sprintf("%d", r)
		}
	}

	return []string{
		ufmt.Sprintf("%d", id),
		ui.Cell(shortPool(poolKey)),
		ufmt.Sprintf("%d to %d", lower, upper),
		ui.Cell(liquidity),
		yesNo(inRange),
		ufmt.Sprintf("%d / %d", amount0, amount1),
		ui.Cell(fee0) + " / " + ui.Cell(fee1),
		yesNo(staked),
		reward,
	}
}

// resolveOwner answers who a position really belongs to, and whether it is staked.
//
// Staking transfers the position NFT to the staker realm, so for every staked
// position the grc721 owner is that realm's address and not the person's. A
// dashboard that trusts the NFT owner alone shows an empty page to everyone who
// staked, which is most of them. The deposit record is what still names the
// person.
func resolveOwner(id uint64) (owner address, staked bool, ok bool) {
	held, err := position.GetPositionOwner(id)
	if err != nil {
		return "", false, false
	}
	if held != chain.PackageAddress(stakerPath) {
		return held, false, true
	}
	deposited, err := staker.GetDepositOwner(id)
	if err != nil {
		// Custodied by the staker with no deposit behind it: in flight, or a
		// record this realm does not understand. Better to say nothing than to
		// attribute it to the staker realm as if it were a user.
		return "", true, false
	}
	return deposited, true, true
}

// parsePath splits an address route from its optional scan offset.
func parsePath(path string) (addr string, offset int, ok bool) {
	addr, rest, found := strings.Cut(path, "/")
	if !found {
		return addr, 0, true
	}
	after, found := strings.CutPrefix(rest, "from/")
	if !found {
		return "", 0, false
	}
	n, err := strconv.Atoi(after)
	if err != nil || n < 0 {
		return "", 0, false
	}
	return addr, n, true
}

// shortPool turns a pool key ("<token0 path>.<symbol>:<token1 path>.<symbol>:<fee>")
// into something that fits a table cell.
func shortPool(poolKey string) string {
	parts := strings.Split(poolKey, ":")
	if len(parts) != 3 {
		return poolKey
	}
	return symbolOf(parts[0]) + "/" + symbolOf(parts[1]) + " " + parts[2]
}

// symbolOf takes the symbol off a GnoSwap token key, which is the grc20 registry
// form "<pkgpath>.<Symbol>".
func symbolOf(tokenKey string) string {
	if i := strings.LastIndex(tokenKey, "."); i >= 0 {
		return tokenKey[i+1:]
	}
	return tokenKey
}

func yesNo(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
