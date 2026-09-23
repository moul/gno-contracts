// Realm vesting answers one question for a gno.land account: of the coins it
// holds, how many can actually move right now.
//
// # Read this before you trust a number here
//
// A realm CANNOT read an account's vesting schedule. The VM's whole view of an
// account is banker.GetCoins, which returns the TOTAL balance with the locked
// part included, and no native exposes std.VestingSchedule. So this realm
// reads two things from the chain and is told the third:
//
//	balance     read from the chain, banker.GetCoins   always true
//	now         read from the chain, block time        always true
//	schedule    supplied, see below                    only as good as its source
//
// Every rendered figure says which of the two it rests on. Nothing here is
// presented as verified when it is not.
//
// # Where a schedule comes from
//
// Either the query string, for a one-off calculation that stores nothing, or
// the registry. [Declare] writes a schedule for the CALLER'S OWN address and
// no other, which is the whole trust model: an address can only misdescribe
// itself, and a wrong entry misleads nobody but its author.
//
// Anyone can read their real schedule in one command and declare it:
//
//	gnokey query auth/accounts/g1youraddress -remote https://rpc.gno.land:443
//
// # Why the schedule can be cached at all
//
// Because it can never change. std.SetVesting has exactly one caller in the
// monorepo, gno.land/pkg/gnoland/app.go, during genesis balance loading, and
// no message type creates or modifies a schedule. A schedule declared once is
// correct forever, which is what makes a registry honest rather than stale.
package vesting

import (
	"strconv"
	"strings"
	"time"

	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"

	"gno.land/p/moul/vesting/v0"
)

const (
	// Path is this realm's package path.
	Path = "gno.land/r/moul/vesting/v0"
	// Link is Path as a gnoweb route.
	Link = "/r/moul/vesting/v0"
	// Denom is the only coin this realm reports on.
	Denom = "ugnot"
)

// seeded are the schedules this realm ships with, restored by init() after
// every redeploy.
//
// They are source constants and not registry rows on purpose: the realm is
// private = true, so a redeploy wipes realm state, and the one schedule the
// page exists to show should not need a transaction to come back. Each is
// copied from the genesis allocation sheet that built mainnet, which is the
// public, pinned input named in misc/deployments/mainnet.gno.land/gen-genesis.sh.
var seeded = []struct {
	addr     address
	label    string
	original int64
	start    int64
	end      int64
	delayed  bool
}{
	{
		addr:     "g1manfred47kzduec920z88wfr64ylksmdcedlf5",
		label:    "moul",
		original: 106560000000,
		start:    1789225200,
		end:      1852383600,
	},
}

// declared maps an address to the schedule that address declared for itself.
var declared avl.Tree

// entry is one row of the registry.
type entry struct {
	schedule vesting.Schedule
	label    string // non-empty only for a seeded row
	seeded   bool
	at       int64 // block height the row was written at; 0 for a seeded row
}

func init() { reset() }

// reset restores the registry to exactly what the source declares. init() is
// its only caller on chain; a test calls it to render a page that does not
// depend on what the test before it wrote, since an Example runs after every
// Test in the package and sees the state they left.
func reset() {
	declared = avl.Tree{}
	for _, s := range seeded {
		typ := vesting.Continuous
		if s.delayed {
			typ = vesting.Delayed
		}
		sch, err := vesting.New(s.original, s.start, s.end, typ)
		if err != nil {
			panic("vesting: seeded schedule for " + s.label + ": " + err.Error())
		}
		declared.Set(s.addr.String(), &entry{schedule: sch, label: s.label, seeded: true})
	}
}

// Declare records the caller's own vesting schedule, replacing any previous
// one. It cannot write a row for anybody else, which is what keeps the
// registry honest without the realm being able to verify a thing.
//
// Pass original = 0 to declare that the address has no schedule at all.
func Declare(cur realm, original, start, end int64, delayed bool) {
	typ := vesting.Continuous
	if delayed {
		typ = vesting.Delayed
	}
	sch, err := vesting.New(original, start, end, typ)
	if err != nil {
		panic(err.Error())
	}
	who := unsafe.PreviousRealm().Address()
	if e, ok := lookup(who); ok && e.seeded {
		panic("vesting: " + who.String() + " is seeded in the source; edit the realm instead")
	}
	declared.Set(who.String(), &entry{schedule: sch, at: chainHeight()})
	chain.Emit("declared", "addr", who.String(),
		"original", strconv.FormatInt(original, 10),
		"start", strconv.FormatInt(start, 10),
		"end", strconv.FormatInt(end, 10),
		"type", typ.String())
}

// Forget removes the caller's own declaration.
func Forget(cur realm) {
	who := unsafe.PreviousRealm().Address()
	e, ok := lookup(who)
	if !ok {
		panic("vesting: nothing declared for " + who.String())
	}
	if e.seeded {
		panic("vesting: " + who.String() + " is seeded in the source; edit the realm instead")
	}
	declared.Remove(who.String())
	chain.Emit("forgot", "addr", who.String())
}

// Count returns how many schedules the registry holds.
func Count() int { return declared.Size() }

// ScheduleOf returns the declared schedule for addr, and whether there is one.
func ScheduleOf(addr address) (original, start, end int64, delayed, ok bool) {
	e, found := lookup(addr)
	if !found {
		return 0, 0, 0, false, false
	}
	s := e.schedule
	return s.Original, s.Start, s.End, s.Type == vesting.Delayed, true
}

// SpendableOf returns what addr can move right now, and whether the answer
// rests on a declared schedule. With ok false the figure is the whole balance,
// which is correct only if the address really has no schedule.
func SpendableOf(addr address) (spendable int64, ok bool) {
	bal := balanceOf(addr)
	e, found := lookup(addr)
	if !found {
		return bal, false
	}
	return e.schedule.Spendable(bal, now()), true
}

// LockedOf returns what addr cannot move right now, and whether the answer
// rests on a declared schedule.
func LockedOf(addr address) (locked int64, ok bool) {
	e, found := lookup(addr)
	if !found {
		return 0, false
	}
	bal := balanceOf(addr)
	l := e.schedule.Locked(now())
	if l > bal {
		l = bal // cannot lock more than is there
	}
	return l, true
}

// lookup reads a row. avl's Get returns ONE value and nil for a miss, unlike
// Remove which returns two; that asymmetry is a documented gno-vs-Go trap.
func lookup(addr address) (*entry, bool) {
	v := declared.Get(addr.String())
	if v == nil {
		return nil, false
	}
	return v.(*entry), true
}

// balanceOf reads the address's TOTAL ugnot, locked included. That is what
// banker.GetCoins reports and the only balance figure a realm can obtain.
// A readonly banker takes no realm, so this works from inside Render.
func balanceOf(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf(Denom)
}

// gnot renders a ugnot amount as GNOT with six decimals and no float.
func gnot(u int64) string {
	neg := u < 0
	if neg {
		u = -u
	}
	whole, frac := u/1_000_000, u%1_000_000
	s := ufmt.Sprintf("%d.%s", whole, pad6(frac))
	if neg {
		s = "-" + s
	}
	return s + " GNOT"
}

// pad6 left-pads to six digits. ufmt has no width flags, so this is by hand.
func pad6(n int64) string {
	s := strconv.FormatInt(n, 10)
	for len(s) < 6 {
		s = "0" + s
	}
	return s
}

// permille renders tenths of a percent as a percentage with one decimal.
func permille(p int64) string {
	return ufmt.Sprintf("%d.%d%%", p/10, p%10)
}

// duration renders a span of seconds as days and hours, which is the only
// resolution worth reading on a two-year schedule.
func duration(sec int64) string {
	if sec <= 0 {
		return "complete"
	}
	d, h := sec/86400, (sec%86400)/3600
	var b strings.Builder
	if d > 0 {
		b.WriteString(strconv.FormatInt(d, 10))
		b.WriteString("d ")
	}
	b.WriteString(strconv.FormatInt(h, 10))
	b.WriteString("h")
	return b.String()
}

// isAddr is a cheap shape check, so a typo renders as "not an address" rather
// than as an account with a zero balance.
func isAddr(s string) bool {
	if len(s) != 40 || !strings.HasPrefix(s, "g1") {
		return false
	}
	for _, r := range s {
		if !(r >= 'a' && r <= 'z') && !(r >= '0' && r <= '9') {
			return false
		}
	}
	return true
}

// now is the chain's own clock, in unix seconds. time.Now() in a realm returns
// the BLOCK time, not a wall clock, which is exactly the value the ante
// handler compares a vesting schedule against.
func now() int64 { return time.Now().Unix() }

func chainHeight() int64 { return runtime.ChainHeight() }
