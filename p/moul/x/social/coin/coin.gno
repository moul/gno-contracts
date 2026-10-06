// Package coin is a GRC20 that cannot exist until its author has answered the
// three questions a social app's token usually dodges: what mints it, what
// burns it, and who has a reason to buy it.
//
// # Why a package and not a convention
//
// Every app in the x/social family is asked the same question, "and can it
// have a token", and the honest answer is only yes when all three of those
// have an answer. A token with a mint rule and no sink is a scoreboard with a
// price: supply grows, nothing consumes it, and the number on the leaderboard
// is the whole product. That is the shape a chain-wide measurement keeps
// finding, and it is cheap to avoid, so [New] refuses a [Policy] with a blank
// field rather than letting the omission ship.
//
// The three strings are not validated beyond being non-empty, because no
// package can check that a sink is real. They are a declaration, rendered on
// the realm's own page by [Coin.Render], where being wrong is visible.
//
// # The model
//
//	earned  minted by the app, for the behaviour the app wants more of
//	spent   burned by the app, for the thing holders actually want
//	traded  a plain GRC20 transfer, which is what makes the sink a market
//
// Earning and spending are the app's business and go through [Coin.Earn] and
// [Coin.Spend], which keep running totals so a reader can see the two halves
// against each other. Transfers, approvals and balances are the embedded
// [grc20.Token]'s, unchanged, so wallets and indexers see an ordinary GRC20.
//
// # Usage
//
// A realm holds one Coin and never exports the ledger:
//
//	var points = coin.New("Thread Points", "THREAD", 0, 0, coin.Policy{
//		Mint:  "1 per distinct address that replies to your thread",
//		Sink:  "burned to pin a thread to the top of its page",
//		Buyer: "anyone who wants placement and has not earned it",
//	}, 0, cur)
//
// The trailing `_ int, rlm realm` is the shape a pure package has to use to
// reach the caller's frame: a p/ package may not declare a crossing function,
// so the realm token is threaded as a later parameter, exactly as grc20's own
// tellers do.
package coin

import (
	"gno.land/p/moul/kit/num/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Policy is the three declarations a Coin cannot be created without.
//
// Each one is a sentence for a human: it is rendered on the issuing realm's
// page and nothing branches on it.
type Policy struct {
	// Mint says what behaviour earns the token, precisely enough that a
	// reader can work out whether they can farm it.
	Mint string

	// Sink says what destroys it. "Nothing" is not an answer; if there is
	// no sink, there is no reason for the token to exist.
	Sink string

	// Buyer says who wants it badly enough to acquire it from someone who
	// earned it. This is the one most often left blank, and the one that
	// decides whether the other two matter.
	Buyer string
}

// Valid reports whether every field is filled in.
func (p Policy) Valid() bool {
	return p.Mint != "" && p.Sink != "" && p.Buyer != ""
}

// Coin is a GRC20 plus the policy it was issued under and the running totals
// of the two flows the policy describes.
type Coin struct {
	tok    *grc20.Token
	led    *grc20.PrivateLedger
	policy Policy

	earned int64 // cumulative minted
	spent  int64 // cumulative burned
}

// New issues the token. It panics when the policy is incomplete, which is the
// whole point of the package: the declaration happens before the first unit
// exists, not in a README written afterwards.
//
// name, symbol, decimals and id are grc20's own; id distinguishes two tokens
// issued by the same realm.
func New(name, symbol string, decimals int, id seqid.ID, policy Policy, _ int, rlm realm) *Coin {
	if !policy.Valid() {
		panic("coin: a token needs a mint rule, a sink and a buyer; one of the three is empty")
	}
	tok, led := grc20.NewToken(name, symbol, decimals, id, rlm)
	return &Coin{tok: tok, led: led, policy: policy}
}

// Token returns the GRC20 itself, for the realm to expose as its read API and
// to register with a token registry.
func (c *Coin) Token() *grc20.Token { return c.tok }

// CallerTeller is the teller that acts as the user who called the realm: it
// moves their own balance and nothing else.
//
// It is exposed, where the ledger is not, because transfer and approve are
// what make the sink a market. Mint and burn stay behind [Coin.Earn] and
// [Coin.Spend] so the mint rule keeps exactly one call site.
func (c *Coin) CallerTeller() grc20.Teller { return c.led.CallerTeller() }

// Policy returns the declarations the token was issued under.
func (c *Coin) Policy() Policy { return c.policy }

// Earn mints amount to addr. The realm calls it from the one place its mint
// rule is implemented, so that rule has exactly one call site.
//
// A non-positive amount is a no-op rather than an abort: a mint rule that
// computes zero (nothing new happened) is a normal outcome and should not
// fail the transaction that discovered it.
func (c *Coin) Earn(to address, amount int64) {
	if amount <= 0 {
		return
	}
	if err := c.led.Mint(to, amount); err != nil {
		panic("coin: mint: " + err.Error())
	}
	c.earned += amount
}

// Spend burns amount from addr, which is how the sink consumes supply.
//
// It aborts when the balance is short, naming both numbers, because the
// caller is a user who is about to be told they cannot afford something.
func (c *Coin) Spend(from address, amount int64) {
	if amount <= 0 {
		panic("coin: spend: amount must be positive")
	}
	if bal := c.tok.BalanceOf(from); bal < amount {
		panic(ufmt.Sprintf("coin: balance %d is short of %d %s", bal, amount, c.tok.GetSymbol()))
	}
	if err := c.led.Burn(from, amount); err != nil {
		panic("coin: burn: " + err.Error())
	}
	c.spent += amount
}

// BalanceOf is the holder's balance.
func (c *Coin) BalanceOf(addr address) int64 { return c.tok.BalanceOf(addr) }

// Supply is what exists right now, that is, earned minus spent.
func (c *Coin) Supply() int64 { return c.tok.TotalSupply() }

// Earned and Spent are the cumulative flows. Their difference is [Coin.Supply]
// and they are kept separately because a sink that never fires is invisible in
// the supply alone: a flat line reads the same as no sink at all.
func (c *Coin) Earned() int64 { return c.earned }

// Spent is the cumulative amount burned through [Coin.Spend].
func (c *Coin) Spent() int64 { return c.spent }

// Holders is how many addresses the ledger knows about.
func (c *Coin) Holders() int { return c.tok.KnownAccounts() }

// Render is the block a realm puts on its own page: the three declarations,
// then the two flows against each other.
//
// The policy strings are escaped: they are constants in practice, but a realm
// could build one from configuration, and this package cannot tell.
func (c *Coin) Render() string {
	out := md.H3(ui.Inline(c.tok.GetName()) + " (" + ui.Inline(c.tok.GetSymbol()) + ")")

	t := ui.NewTable("", "")
	t.Row("earns", ui.Cell(c.policy.Mint))
	t.Row("burns", ui.Cell(c.policy.Sink))
	t.Row("bought by", ui.Cell(c.policy.Buyer))
	out += t.String()

	s := ui.NewTable("supply", "earned", "burned", "holders")
	s.Row(
		num.Dec(c.Supply(), c.tok.GetDecimals()),
		num.Dec(c.earned, c.tok.GetDecimals()),
		num.Dec(c.spent, c.tok.GetDecimals()),
		ufmt.Sprintf("%d", c.Holders()),
	)
	out += s.String()

	return out
}
