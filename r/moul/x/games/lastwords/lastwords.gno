// Package lastwords is one string, on chain, forever.
//
// There is a single message slot. Pay more than the last writer paid and the
// slot is yours; when the clock finally runs out, whatever is in it stays there
// permanently. The artefact at the end is the point, so the game is a bidding
// war over an epitaph rather than over a prize.
//
// The three rules exist because the obvious version of this game does not end
// and does not pay:
//
//  1. THE CLOCK TERMINATES. Every write pushes the deadline a fifth of the way
//     to a hard end fixed when the slot opened, and no write can push it past
//     that. A constant extension per action has no end: the pot grows faster
//     than the price of the next write, so there is always a rational next
//     write and the game runs until everyone is bored or broke.
//  2. THE LAST WRITER DOES NOT TAKE THE POT. They take the slot, which is what
//     they were bidding for. The pot is split among everyone ELSE who wrote,
//     pro rata to what they paid. Winner-takes-all makes the second-to-last
//     writer the mark and everyone knows it, which is why nobody joins.
//  3. HALF OF EVERY PAYMENT GOES TO THE WRITER BEING DISPLACED, immediately.
//     A zero-sum game minus gas has no reason for a second player. Overwriting
//     somebody pays them, so being overwritten early is not a loss.
//
// Nothing is ever pushed: payouts are credited to an internal ledger and swept
// by Withdraw. A realm that pays inside a loop over its roster is a gas bomb
// that eventually bricks, and the bigger the game gets the more certain that
// is.
//
// The pieces are libraries, and the realm is the wiring:
// [p/moul/x/games/clock](/p/moul/x/games/clock/v0) owns the deadline and its
// guards, [p/moul/x/games/prorata](/p/moul/x/games/prorata/v0) owns the split,
// and [p/moul/x/daily/pullpayment](/p/moul/x/daily/pullpayment/v0) owns the
// credit ledger.
package lastwords

import (
	"strconv"
	"strings"

	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/moul/x/daily/pullpayment/v0"
	"gno.land/p/moul/x/games/clock/v0"
	"gno.land/p/moul/x/games/prorata/v0"
	"gno.land/p/nt/avl/v0"
)

const denom = "ugnot"

// The rules, fixed at deploy. Times are block heights.
const (
	// Window is how long the slot stays open with nobody writing.
	Window = int64(2000)
	// Floor is the minimum a write leaves on the clock, so the last stretch
	// stays long enough for a transaction to land in. Without it a decaying
	// extension shrinks to nothing and whoever holds at that moment wins by
	// being unreachable rather than by paying.
	Floor = int64(300)
	// Life is the hard end. No write can push the deadline past start+Life.
	Life = int64(100000)
	// BumpPct is how much of the gap to the hard end a write buys.
	BumpPct = int64(20)
	// DividendPct is the share of a payment credited to the writer being
	// displaced; the rest goes to the pot.
	DividendPct = int64(50)

	// MinWrite is the base price of the slot, in ugnot.
	MinWrite = int64(1000000)
	// PerByte is charged on top, in ugnot per byte of the message. The chain's
	// own storage deposit is 100 ugnot per byte, so this is that plus a premium
	// for occupying the only slot there is.
	PerByte = int64(1000)
	// MaxLen caps the message in bytes, because the message IS the storage
	// cost and an uncapped one is an unbounded write priced at a constant.
	MaxLen = 280
)

var (
	clk     *clock.Clock
	ledger  = pullpayment.New()
	message string
	author  address
	paid    int64    // what the current holder paid
	pot     int64    // what settlement will split
	writers avl.Tree // address string -> int64 total paid
	order   []string // writers in first-write order, so the split is deterministic
	writes  int64
	settled bool
)

func init() {
	open(runtime.ChainHeight())
}

// open resets the game to a fresh slot at height h. It is the only place the
// clock is built, so tests and init cannot disagree about the rules.
func open(h int64) {
	c, err := clock.New(h, Window, Floor, Life)
	if err != nil {
		panic("lastwords: " + err.Error())
	}
	clk = c
	ledger = pullpayment.New()
	message = ""
	author = ""
	paid = 0
	pot = 0
	writers = avl.Tree{}
	order = nil
	writes = 0
	settled = false
}

// Price returns what msg costs to write right now, in ugnot: a base, plus a
// charge per byte, and always at least one ugnot more than the current holder
// paid. Query it before sending; an underpaying write is refused, not refunded.
func Price(msg string) int64 {
	price := MinWrite + int64(len(msg))*PerByte
	if next := paid + 1; next > price {
		price = next
	}
	return price
}

// Write puts msg in the slot and makes the caller its holder. The caller must
// send at least Price(msg) ugnot with the transaction.
//
// Half of the payment is credited to the writer being displaced and the rest
// joins the pot. The deadline is pushed a fifth of the way toward the hard end,
// never past it, and never to less than Floor from now.
//
// Only a direct user transaction may write, so the payment envelope cannot be
// spoofed by an ephemeral MsgRun realm.
func Write(cur realm, msg string) {
	if !cur.Previous().IsUserCall() {
		panic("lastwords: write must be a direct user transaction")
	}
	h := runtime.ChainHeight()
	if clk.Expired(h) {
		panic("lastwords: the slot is closed, these are somebody's last words now")
	}
	if msg == "" {
		panic("lastwords: message must not be empty")
	}
	if len(msg) > MaxLen {
		panic("lastwords: message must be at most " + strconv.Itoa(MaxLen) + " bytes")
	}
	if strings.ContainsAny(msg, "\n\r") {
		panic("lastwords: message must be a single line")
	}

	price := Price(msg)
	sent := unsafe.OriginSend().AmountOf(denom)
	if sent < price {
		panic("lastwords: sent " + strconv.FormatInt(sent, 10) +
			" ugnot, price is " + strconv.FormatInt(price, 10))
	}

	caller := cur.Previous().Address()

	// The displaced writer is paid first, out of the payment that displaced
	// them. Credited, never sent: see the package doc.
	dividend := int64(0)
	if author != "" {
		dividend = sent * DividendPct / 100
		if err := ledger.Credit(author.String(), dividend); err != nil {
			panic("lastwords: " + err.Error())
		}
	}
	pot += sent - dividend

	key := caller.String()
	if _, seen := writers.Get(key).(int64); !seen {
		order = append(order, key)
	}
	writers.Set(key, totalPaid(key)+sent)

	message = msg
	author = caller
	paid = sent
	writes++

	deadline, err := clk.BumpShare(h, BumpPct)
	if err != nil {
		panic("lastwords: " + err.Error())
	}

	chain.Emit("Write",
		"author", key,
		"paid", strconv.FormatInt(sent, 10),
		"dividend", strconv.FormatInt(dividend, 10),
		"deadline", strconv.FormatInt(deadline, 10),
	)
}

// Settle closes the game once the clock has run out, splitting the pot among
// every writer EXCEPT the one holding the slot, pro rata to what each paid.
//
// Anyone may call it: leaving settlement to an interested party is how a pot
// stays unclaimed. It moves no coins, it credits the ledger; Withdraw is what
// pays. If the holder is the only writer there is nobody else to split with,
// so the pot returns to them.
func Settle(cur realm) {
	h := runtime.ChainHeight()
	if !clk.Expired(h) {
		panic("lastwords: still open until height " + strconv.FormatInt(clk.Deadline(), 10))
	}
	if settled {
		panic("lastwords: already settled")
	}
	settled = true
	if pot == 0 {
		return
	}

	holder := author.String()
	payees := []string{}
	weights := []int64{}
	for _, k := range order {
		if k == holder {
			continue
		}
		payees = append(payees, k)
		weights = append(weights, totalPaid(k))
	}
	if len(payees) == 0 {
		// The holder wrote every word there is. Nobody to share with.
		payees = []string{holder}
		weights = []int64{1}
	}

	shares, err := prorata.Split(pot, weights)
	if err != nil {
		panic("lastwords: " + err.Error())
	}

	// A zero share is dropped: CreditMany refuses a non-positive amount, and
	// crediting nothing is not a payment anyway.
	dst := []string{}
	amounts := []int64{}
	for i, s := range shares {
		if s > 0 {
			dst = append(dst, payees[i])
			amounts = append(amounts, s)
		}
	}
	if len(dst) > 0 {
		if err := ledger.CreditMany(dst, amounts); err != nil {
			panic("lastwords: " + err.Error())
		}
	}
	pot = 0

	chain.Emit("Settle",
		"holder", holder,
		"writes", strconv.FormatInt(writes, 10),
		"payees", strconv.Itoa(len(dst)),
	)
}

// Withdraw pays the caller everything credited to them and returns the amount.
// Dividends are claimable while the game runs; settlement shares only after
// Settle.
func Withdraw(cur realm) int64 {
	caller := cur.Previous().Address()
	amount, err := ledger.Withdraw(caller.String())
	if err != nil {
		panic("lastwords: " + err.Error())
	}
	bnk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bnk.SendCoins(cur.Address(), caller, chain.NewCoins(chain.NewCoin(denom, amount)))

	chain.Emit("Withdraw", "payee", caller.String(), "amount", strconv.FormatInt(amount, 10))
	return amount
}

// Message returns the slot's current contents, raw. Render is what escapes it.
func Message() string { return message }

// Author returns who holds the slot.
func Author() address { return author }

// Pot returns what settlement will split.
func Pot() int64 { return pot }

// Deadline returns the height the slot closes at.
func Deadline() int64 { return clk.Deadline() }

// Owed returns what an address can Withdraw right now.
func Owed(addr address) int64 { return ledger.Balance(addr.String()) }

// totalPaid returns what an address has paid in total, zero if it never wrote.
func totalPaid(key string) int64 {
	v, ok := writers.Get(key).(int64)
	if !ok {
		return 0
	}
	return v
}

func gnot(ugnot int64) string {
	whole := ugnot / 1000000
	frac := ugnot % 1000000
	s := strconv.FormatInt(whole, 10)
	if frac == 0 {
		return s
	}
	f := strconv.FormatInt(frac, 10)
	for len(f) < 6 {
		f = "0" + f
	}
	for len(f) > 1 && f[len(f)-1] == '0' {
		f = f[:len(f)-1]
	}
	return s + "." + f
}
