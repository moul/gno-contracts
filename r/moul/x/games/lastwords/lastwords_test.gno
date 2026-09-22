package lastwords

import (
	"strings"
	"testing"

	"chain"
	"chain/banker"
	"chain/runtime"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var realmAddr = chain.PackageAddress("gno.land/r/moul/x/games/lastwords/v0")

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

// reset reopens the slot at the current height. Heights are relative in tests
// (SkipHeights moves forward from wherever the last test left off and there is
// no absolute setter), so nothing here asserts an absolute height.
func reset() {
	open(runtime.ChainHeight())
}

// write sends amount ugnot alongside the call, the way a real transaction
// would: the runtime deposits it at the realm's address, then OriginSend
// reports it to the crossing function.
func write(cur realm, who address, amount int64, msg string) {
	testing.IssueCoins(realmAddr, chain.Coins{{denom, amount}})
	testing.SetOriginSend(chain.Coins{{denom, amount}})
	testing.SetRealm(testing.NewUserRealm(who))
	Write(cross(cur), msg)
}

func TestWriteTakesTheSlot(cur realm, t *testing.T) {
	reset()
	uassert.Equal(t, "", Message())

	write(cur, alice, Price("hello"), "hello")
	uassert.Equal(t, "hello", Message())
	uassert.Equal(t, alice.String(), Author().String())
	uassert.Equal(t, int64(0), ledger.TotalOwed(), "nobody was displaced yet")
	uassert.Equal(t, MinWrite+5*PerByte, Pot(), "the whole first payment is the pot")
}

// TestDisplacedWriterIsPaid is rule 3: overwriting somebody pays them, so a
// second player has a reason to exist.
func TestDisplacedWriterIsPaid(cur realm, t *testing.T) {
	reset()
	write(cur, alice, Price("alice was here"), "alice was here")
	potAfterFirst := Pot()

	paidByBob := Price("no, bob was")
	write(cur, bob, paidByBob, "no, bob was")

	dividend := paidByBob * DividendPct / 100
	uassert.Equal(t, dividend, Owed(alice), "half of bob's payment, credited")
	uassert.Equal(t, potAfterFirst+paidByBob-dividend, Pot())
	uassert.Equal(t, int64(0), Owed(bob), "the holder is owed nothing yet")
}

func TestPriceRisesWithTheHolderAndTheLength(cur realm, t *testing.T) {
	reset()
	uassert.Equal(t, MinWrite, Price(""), "the base price with an empty slot")
	uassert.Equal(t, MinWrite+10*PerByte, Price("0123456789"), "ten bytes cost ten byte-prices")

	first := Price("x")
	write(cur, alice, first, "x")
	uassert.Equal(t, first+1, Price(""), "outbidding the holder is the floor")
}

func TestWriteRejectsBadInput(cur realm, t *testing.T) {
	reset()

	testing.SetOriginSend(chain.Coins{{denom, MinWrite}})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "must not be empty", func() { Write(cross(cur), "") })

	long := strings.Repeat("x", MaxLen+1)
	testing.SetOriginSend(chain.Coins{{denom, Price(long)}})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "at most", func() { Write(cross(cur), long) })

	testing.SetOriginSend(chain.Coins{{denom, Price("a\nb")}})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "single line", func() { Write(cross(cur), "a\nb") })

	testing.SetOriginSend(chain.Coins{{denom, MinWrite - 1}})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "price is", func() { Write(cross(cur), "cheapskate") })

	uassert.Equal(t, "", Message(), "none of that took the slot")
}

// TestEveryWriteExtendsButNeverPastTheHardEnd is rule 1, the terminator. A
// constant extension per write is how a pot stays open forever.
func TestEveryWriteExtendsButNeverPastTheHardEnd(cur realm, t *testing.T) {
	reset()
	start := runtime.ChainHeight()
	hardEnd := start + Life
	uassert.Equal(t, start+Window, Deadline(), "it opens with the window")

	prev := Deadline()
	for i := 0; i < 30; i++ {
		testing.SkipHeights(100)
		if runtime.ChainHeight() >= Deadline() {
			break
		}
		write(cur, alice, Price("again"), "again")
		uassert.True(t, Deadline() >= prev, "a write never shortens the clock")
		uassert.True(t, Deadline() <= hardEnd, "and never passes the hard end")
		prev = Deadline()
	}
	uassert.True(t, Deadline() <= hardEnd)
	uassert.True(t, Deadline() > start+Window, "the writes did buy time")
}

func TestClosedSlotRefusesAWrite(cur realm, t *testing.T) {
	reset()
	write(cur, alice, Price("famous last words"), "famous last words")
	testing.SkipHeights(Life + 1)

	testing.SetOriginSend(chain.Coins{{denom, Price("too late")}})
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "slot is closed", func() { Write(cross(cur), "too late") })
	uassert.Equal(t, "famous last words", Message(), "the last words stay last")
}

// TestSettleSplitsAmongEveryoneButTheHolder is rule 2, and it is the whole
// reason this is not a winner-takes-all pot.
func TestSettleSplitsAmongEveryoneButTheHolder(cur realm, t *testing.T) {
	reset()
	write(cur, alice, Price("a"), "a")
	testing.SkipHeights(10)
	write(cur, bob, Price("b"), "b")
	testing.SkipHeights(10)
	write(cur, carol, Price("c"), "c")

	beforeAlice, beforeBob := Owed(alice), Owed(bob)
	pot := Pot()
	uassert.True(t, pot > 0)

	testing.SkipHeights(Life + 1)
	testing.SetRealm(testing.NewUserRealm(bob)) // anyone may settle
	Settle(cross(cur))

	uassert.Equal(t, int64(0), Pot(), "the pot is fully distributed")
	uassert.Equal(t, int64(0), Owed(carol), "the holder takes the slot, not the pot")
	uassert.True(t, Owed(alice) > beforeAlice, "alice got a share")
	uassert.True(t, Owed(bob) > beforeBob, "bob got a share")
	split := (Owed(alice) - beforeAlice) + (Owed(bob) - beforeBob)
	uassert.Equal(t, pot, split, "and the shares add up to exactly the pot")
}

func TestSettleWithOneWriterReturnsThePot(cur realm, t *testing.T) {
	reset()
	write(cur, alice, Price("alone"), "alone")
	pot := Pot()
	testing.SkipHeights(Life + 1)

	testing.SetRealm(testing.NewUserRealm(alice))
	Settle(cross(cur))
	uassert.Equal(t, pot, Owed(alice), "nobody else to share with")
}

func TestSettleRefusesEarlyAndTwice(cur realm, t *testing.T) {
	reset()
	write(cur, alice, Price("tick"), "tick")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "still open", func() { Settle(cross(cur)) })

	testing.SkipHeights(Life + 1)
	testing.SetRealm(testing.NewUserRealm(bob))
	Settle(cross(cur))
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "already settled", func() { Settle(cross(cur)) })
}

// TestWithdrawPaysRealCoins checks the half nothing else can: the ledger and
// the realm's balance agree.
func TestWithdrawPaysRealCoins(cur realm, t *testing.T) {
	reset()
	write(cur, alice, Price("first"), "first")
	testing.SkipHeights(10)
	write(cur, bob, Price("second"), "second")

	owed := Owed(alice)
	uassert.True(t, owed > 0)

	ro := banker.NewReadonlyBanker()
	before := ro.GetCoins(alice).AmountOf(denom)

	testing.SetRealm(testing.NewUserRealm(alice))
	got := Withdraw(cross(cur))
	uassert.Equal(t, owed, got)
	uassert.Equal(t, int64(0), Owed(alice), "the credit is zeroed before the coins move")

	after := banker.NewReadonlyBanker().GetCoins(alice).AmountOf(denom)
	uassert.Equal(t, before+owed, after, "the coins actually arrived")

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "nothing to withdraw", func() { Withdraw(cross(cur)) })
}

// TestRenderEscapesTheMessage is the one bug a live deploy makes permanent: the
// realm's entire product is a string somebody else typed.
func TestRenderEscapesTheMessage(cur realm, t *testing.T) {
	reset()
	write(cur, alice, Price("[click](https://evil.example)"), "[click](https://evil.example)")

	out := Render("")
	uassert.False(t, strings.Contains(out, "](https://evil.example)"), "no live link")
	uassert.False(t, strings.Contains(out, "[click]"), "the link syntax is dead")
	uassert.True(t, strings.Contains(out, "click"), "the text is still readable")
	uassert.True(t, strings.Contains(out, "Last Words"))
}

func TestRenderCoversEveryPhase(cur realm, t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render(""), "The slot is empty"))

	write(cur, alice, Price("open for business"), "open for business")
	out := Render("")
	uassert.True(t, strings.Contains(out, "open for business"))
	uassert.True(t, strings.Contains(out, "Open for another"))

	testing.SkipHeights(Life + 1)
	out = Render("")
	uassert.True(t, strings.Contains(out, "**Closed** at height"))
	uassert.True(t, strings.Contains(out, "may call `Settle`"))

	testing.SetRealm(testing.NewUserRealm(bob))
	Settle(cross(cur))
	out = Render("")
	uassert.True(t, strings.Contains(out, "Settled"))
	uassert.True(t, strings.Contains(out, "Owed"))
}

func TestGnotFormatting(t *testing.T) {
	uassert.Equal(t, "0", gnot(0))
	uassert.Equal(t, "1", gnot(1000000))
	uassert.Equal(t, "1.5", gnot(1500000))
	uassert.Equal(t, "0.000001", gnot(1))
	uassert.Equal(t, "12.345678", gnot(12345678))
}
