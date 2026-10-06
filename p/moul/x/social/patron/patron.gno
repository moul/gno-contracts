// Package patron is the engine behind recurring support for a builder: a plan
// somebody subscribes to, period after period, paid in ugnot on chain.
//
// # There is no cron on chain, so a renewal is a pull and not a push
//
// Nothing here can charge anybody. The supporter sends another payment and
// their paid-through height moves forward; there is no scheduler, no keeper,
// and no standing authority over anybody's balance. There is no way to write
// one either, because a native coin cannot be pulled at all: a banker may only
// spend its own realm's address, so the inbound path is always the holder
// signing. A reader arriving from web2 expects the opposite, and that is the
// one expectation to unlearn before reading the rest of this package.
//
// # What this adds over a tip jar
//
// A tip jar is one payment and then nothing, and the one-shot version is
// already live at gno.land/r/moul/x/daily/tipjar. The recurrence is the only
// reason this exists: a plan carries a price per period and a period measured
// in BLOCKS, a supporter buys whole periods, and anybody can ask at any height
// whether a given address is still active. It is the one piece of the x/social
// family that produces a recurring write rather than a one-off.
//
// # The model
//
//	Registry  every plan, plus the credit ledger money leaves through
//	Plan      a creator, a title, a description, a price, a period, open or not
//	Payment   what one Subscribe call bought: periods, spent, change, through
//
// # Renewing early never loses time already paid for
//
// [Registry.Subscribe] extends from whichever is LATER, now or the supporter's
// current paid-through height. Renewing two blocks before a lapse adds a whole
// period on top of what is left. Renewing after a lapse starts from now,
// because the gap was never paid for and nothing backdates it.
//
// # The change is credited back, never kept
//
// A payment buys floor(sent / price) whole periods, and the remainder under
// one period is credited to the SUPPORTER's own withdrawable balance. Keeping
// it would be a fee nobody agreed to, and a silent fee is the thing a
// subscription realm must not have. The supporter takes it back through the
// same [Registry.Withdraw] a creator uses.
//
// # Earnings are credited at the moment of payment, not streamed
//
// The creator can withdraw the whole price the instant it is paid. A supporter
// who stops being active is therefore NOT refunded, and no part of a paid
// period is ever returned. That is a real limitation and it is v0 on purpose:
// escrowed streaming, where the creator claims only what has elapsed and the
// supporter can cancel and reclaim the rest, needs a claim schedule and a
// refund path, which is a bigger realm than this one. It is the v1, and it is
// not a line that can be bolted onto this one.
//
// # Money leaves by pull, never by a push loop
//
// Nothing here moves coins. [Registry.Subscribe] credits a
// gno.land/p/moul/x/daily/pullpayment ledger, and [Registry.Withdraw] zeroes a
// credit and reports what was owed so the holding realm can transfer after
// that call, with the balance already gone when control leaves. A realm that
// looped over payees instead would fail entirely on one unpayable address and
// hand a griefer a cheap denial of service.
//
// # A title and a description are attacker-controlled markdown
//
// Both are free text. [ValidTitle] and [ValidDescription] bound them and
// refuse control characters, which is a different protection from escaping and
// not a substitute for it: a realm that renders either one escapes it with
// ui.Inline in prose or ui.Cell in a table cell.
package patron

import (
	"errors"
	"strings"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/x/daily/pullpayment/v0"
	"gno.land/p/moul/xmath/v1"
)

const (
	// MaxTitleLen and MaxDescriptionLen bound the two free-text fields. Long
	// enough to say what the plan is, short enough that opening one cannot
	// lock an unbounded storage deposit somebody else is paying for.
	MaxTitleLen       = 80
	MaxDescriptionLen = 500

	// MinPeriodBlocks and MaxPeriodBlocks bound a period both ways. A period
	// of zero blocks is not a subscription, it is a division by zero wearing
	// a price tag. The ceiling is about a year at the five second blocks the
	// test chain runs, past which "recurring" stops meaning anything and the
	// plan is a one-off with extra steps.
	MinPeriodBlocks = int64(10)
	MaxPeriodBlocks = int64(6307200)

	// MinPricePerPeriod is one ugnot, because a free plan is a tip jar
	// (gno.land/r/moul/x/daily/tipjar) and not a subscription: at a price of
	// zero there is nothing to buy a period with and every address would be
	// active forever.
	MinPricePerPeriod = int64(1)

	// MaxPeriodsPerPayment bounds what one payment may buy. It keeps
	// periods * PeriodBlocks inside an int64 by construction rather than by
	// hope, and it stops a single send from parking a paid-through height so
	// far ahead that no later arithmetic on it means anything.
	MaxPeriodsPerPayment = int64(10000)
)

// The errors a caller can get back. A p/ package returns them and the realm
// decides to abort.
var (
	ErrBadTitle          = errors.New("patron: title is empty, too long, or has control characters")
	ErrBadDescription    = errors.New("patron: description is too long or has control characters")
	ErrBadPrice          = errors.New("patron: a plan needs a price of at least one ugnot per period")
	ErrBadPeriod         = errors.New("patron: period out of range")
	ErrNoPlan            = errors.New("patron: no such plan")
	ErrPlanClosed        = errors.New("patron: this plan is closed to new subscriptions")
	ErrNotCreator        = errors.New("patron: only the plan's creator can do that")
	ErrAlreadyOpen       = errors.New("patron: the plan is already open")
	ErrAlreadyClosed     = errors.New("patron: the plan is already closed")
	ErrShortOfOnePeriod  = errors.New("patron: the payment does not cover one whole period")
	ErrTooManyPeriods    = errors.New("patron: one payment cannot buy that many periods")
	ErrNothingToWithdraw = errors.New("patron: nothing to withdraw")
)

// Plan is one creator's recurring support plan.
type Plan struct {
	Creator     address
	Title       string
	Description string

	// PricePerPeriod is what one period costs, in ugnot.
	PricePerPeriod int64

	// PeriodBlocks is how long a period lasts, in blocks. Blocks and not
	// seconds: height is the clock consensus agrees on, and a block timestamp
	// is set by proposers and is not something to build a billing cliff out
	// of at second resolution.
	PeriodBlocks int64

	// Open reports whether the plan takes NEW payments. Closing it never
	// touches a subscription already paid for, which runs to its own
	// paid-through height.
	Open bool

	// Received is the lifetime ugnot this plan credited to its creator.
	Received int64

	// paidThrough is the first height at which a supporter is no longer
	// active. A supporter is active while now < paidThrough, so a period
	// bought at height h ends at h+PeriodBlocks and the holder is inactive
	// at exactly that height.
	paidThrough map[string]int64

	// supporters is every address that has ever paid, in first-payment
	// order. It exists so a listing is deterministic without iterating a map
	// as if insertion order were a sort.
	supporters []address
}

// PaidThrough is the height who stops being active at, or zero if they never
// paid.
func (p *Plan) PaidThrough(who address) int64 {
	if p == nil {
		return 0
	}
	return p.paidThrough[who.String()]
}

// IsActive reports whether who is paid up at height now.
//
// The comparison is strict: a supporter paid through height h is active at
// h-1 and not at h. One rule, applied at both edges, so a period never
// overlaps the next one by a block.
func (p *Plan) IsActive(who address, now int64) bool {
	return p.PaidThrough(who) > now
}

// SupporterCount is how many distinct addresses have ever paid, active or not.
func (p *Plan) SupporterCount() int {
	if p == nil {
		return 0
	}
	return len(p.supporters)
}

// Supporters is every address that has ever paid, in first-payment order.
//
// It returns a copy. Handing out the stored slice would be a live mutation
// handle on realm state, which is the cheapest way for a reader to become a
// writer.
func (p *Plan) Supporters() []address {
	if p == nil {
		return nil
	}
	out := make([]address, len(p.supporters))
	copy(out, p.supporters)
	return out
}

// ActiveCount is how many supporters are paid up at height now.
func (p *Plan) ActiveCount(now int64) int {
	if p == nil {
		return 0
	}
	n := 0
	for _, who := range p.supporters {
		if p.IsActive(who, now) {
			n++
		}
	}
	return n
}

// Payment is what one [Registry.Subscribe] call bought.
type Payment struct {
	// Periods is how many whole periods the payment covered.
	Periods int64

	// Spent is the ugnot those periods cost, credited to the creator.
	Spent int64

	// Change is the remainder under one period, credited back to the
	// supporter rather than kept.
	Change int64

	// PaidThrough is the supporter's new paid-through height.
	PaidThrough int64

	// NewSupporter reports whether this address had never paid this plan
	// before, which is the signal a realm wants for an event or a counter.
	NewSupporter bool
}

// Registry holds every plan and the credit ledger money leaves through.
type Registry struct {
	plans  *store.Store
	ledger *pullpayment.Ledger

	// earned is lifetime ugnot credited per creator, which survives a
	// withdrawal. The ledger only knows what is owed RIGHT NOW, and a page
	// showing a creator zero the moment they cash out would be telling the
	// truth about the wrong question.
	earned map[string]int64
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry {
	return &Registry{
		plans:  store.Named("plan"),
		ledger: pullpayment.New(),
		earned: map[string]int64{},
	}
}

// Open creates a plan and returns its id. Anyone may open one.
func (r *Registry) Open(creator address, title, description string, pricePerPeriod, periodBlocks int64) (store.ID, error) {
	if !ValidTitle(title) {
		return 0, ErrBadTitle
	}
	if !ValidDescription(description) {
		return 0, ErrBadDescription
	}
	if pricePerPeriod < MinPricePerPeriod {
		return 0, ErrBadPrice
	}
	if periodBlocks < MinPeriodBlocks || periodBlocks > MaxPeriodBlocks {
		return 0, ErrBadPeriod
	}
	return r.plans.Add(&Plan{
		Creator:        creator,
		Title:          title,
		Description:    description,
		PricePerPeriod: pricePerPeriod,
		PeriodBlocks:   periodBlocks,
		Open:           true,
		paidThrough:    map[string]int64{},
	}), nil
}

// Subscribe buys whole periods on a plan with sent ugnot, at height now.
//
// It refuses anything short of one period, buys floor(sent / price) of them,
// and credits the remainder back to the supporter. The extension starts from
// whichever is LATER, now or the supporter's current paid-through height, so
// renewing early never discards time already paid for and renewing after a
// lapse never backdates the gap.
//
// The creator is credited at the moment of payment, not as the periods
// elapse. See the package doc for why that is v0 and what v1 would have to
// carry instead.
func (r *Registry) Subscribe(id store.ID, who address, sent, now int64) (Payment, error) {
	p, ok := r.Get(id)
	if !ok {
		return Payment{}, ErrNoPlan
	}
	if !p.Open {
		return Payment{}, ErrPlanClosed
	}
	if sent < p.PricePerPeriod {
		return Payment{}, ErrShortOfOnePeriod
	}

	// The one rounding decision in this function: periods is floor, so a
	// supporter is never sold a period they did not fully fund, and the
	// remainder is handed back below rather than kept. Neither side keeps a
	// fraction of a period.
	periods := sent / p.PricePerPeriod
	if periods > MaxPeriodsPerPayment {
		return Payment{}, ErrTooManyPeriods
	}
	spent := sent - sent%p.PricePerPeriod
	change := sent - spent

	// spent is an exact whole number of periods, so this division leaves no
	// remainder and there is no second rounding direction to choose. MulDiv
	// is here for the intermediate: spent * PeriodBlocks overflows an int64
	// for a plan priced in whole GNOT with a period measured in months, and
	// the naive product wraps to a plausible-looking height rather than to an
	// obvious one. MulDivUp would be identical on an exact division; MulDiv
	// says plainly that nothing is being rounded up.
	added := xmath.MulDiv(spent, p.PeriodBlocks, p.PricePerPeriod)

	from := now
	if pt := p.PaidThrough(who); pt > from {
		from = pt
	}
	through := from + added

	key := who.String()

	// Both credits happen before the plan is touched, and both can fail: the
	// ledger is bounded and guards its own overflow. A realm calling this
	// aborts on the error, which reverts everything written in the same
	// frame, so a half-applied subscription is not reachable from a crossing
	// call. The ordering is what makes that true for every other caller too.
	if err := r.ledger.Credit(p.Creator.String(), spent); err != nil {
		return Payment{}, err
	}
	if change > 0 {
		if err := r.ledger.Credit(key, change); err != nil {
			return Payment{}, err
		}
	}
	r.earned[p.Creator.String()] += spent

	_, seen := p.paidThrough[key]
	if !seen {
		p.supporters = append(p.supporters, who)
	}
	p.paidThrough[key] = through
	p.Received += spent

	return Payment{
		Periods:      periods,
		Spent:        spent,
		Change:       change,
		PaidThrough:  through,
		NewSupporter: !seen,
	}, nil
}

// Close stops a plan taking new subscriptions. Creator only.
//
// It does not touch anything already paid for: existing supporters run to
// their own paid-through height, which is the only behaviour that does not
// turn closing a plan into taking money back.
func (r *Registry) Close(id store.ID, who address) error {
	p, err := r.ownPlan(id, who)
	if err != nil {
		return err
	}
	if !p.Open {
		return ErrAlreadyClosed
	}
	p.Open = false
	return nil
}

// Reopen lets a closed plan take subscriptions again. Creator only.
func (r *Registry) Reopen(id store.ID, who address) error {
	p, err := r.ownPlan(id, who)
	if err != nil {
		return err
	}
	if p.Open {
		return ErrAlreadyOpen
	}
	p.Open = true
	return nil
}

// ownPlan is the shared lookup plus authority check, so Close and Reopen
// cannot drift apart on who is allowed to call them.
func (r *Registry) ownPlan(id store.ID, who address) (*Plan, error) {
	p, ok := r.Get(id)
	if !ok {
		return nil, ErrNoPlan
	}
	if p.Creator != who {
		return nil, ErrNotCreator
	}
	return p, nil
}

// Withdraw zeroes who's credit and reports what they were owed.
//
// It moves no coins. The holding realm transfers the returned amount AFTER
// this call, which is the whole point of the pattern: the credit is already
// gone from the ledger when control passes to the payee, so a reentrant call
// finds nothing and gets [ErrNothingToWithdraw].
func (r *Registry) Withdraw(who address) (int64, error) {
	amount, err := r.ledger.Withdraw(who.String())
	if err != nil {
		return 0, ErrNothingToWithdraw
	}
	return amount, nil
}

// CreditOf is what addr can withdraw right now: earnings as a creator, change
// as a supporter, or both.
func (r *Registry) CreditOf(addr address) int64 { return r.ledger.Balance(addr.String()) }

// EarnedBy is the lifetime ugnot credited to creator across every plan,
// whether or not it has been withdrawn.
func (r *Registry) EarnedBy(creator address) int64 { return r.earned[creator.String()] }

// TotalOwed is everything the holding realm must keep in reserve.
func (r *Registry) TotalOwed() int64 { return r.ledger.TotalOwed() }

// Get returns a plan by id.
func (r *Registry) Get(id store.ID) (*Plan, bool) {
	v, ok := r.plans.Get(id)
	if !ok {
		return nil, false
	}
	return v.(*Plan), true
}

// Count is how many plans exist.
func (r *Registry) Count() int { return r.plans.Len() }

// Listing is one row of [Registry.List]: the plan and the id a link needs.
type Listing struct {
	ID   store.ID
	Plan *Plan
}

// List returns one page of plans, newest first.
func (r *Registry) List(page, size int) []Listing {
	var out []Listing
	for _, e := range r.plans.PageReverse(page, size) {
		out = append(out, Listing{ID: e.ID, Plan: e.Value.(*Plan)})
	}
	return out
}

// Pages is how many pages of the given size the registry holds.
func (r *Registry) Pages(size int) int { return r.plans.Pages(size) }

// ValidTitle reports whether title can be stored: non-empty after trimming,
// within [MaxTitleLen], and free of control characters including newlines.
//
// A title is one line by construction, so a newline in one is refused rather
// than stripped: silently rewriting what somebody typed is worse than telling
// them it was refused.
func ValidTitle(title string) bool {
	if len(title) > MaxTitleLen || strings.TrimSpace(title) == "" {
		return false
	}
	for i := 0; i < len(title); i++ {
		if c := title[i]; c < 0x20 || c == 0x7f {
			return false
		}
	}
	return true
}

// ValidDescription reports whether description can be stored: within
// [MaxDescriptionLen] and free of control characters other than newline and
// tab. Empty is allowed, because a plan whose title says it all should not
// have to invent prose.
func ValidDescription(description string) bool {
	if len(description) > MaxDescriptionLen {
		return false
	}
	for i := 0; i < len(description); i++ {
		c := description[i]
		if c < 0x20 && c != '\n' && c != '\t' || c == 0x7f {
			return false
		}
	}
	return true
}

// PlanURL is the gnoweb path of one plan on the hosting realm.
func PlanURL(realmPath string, id store.ID) string {
	return RealmURL(realmPath) + ":plan/" + id.String()
}

// RealmURL is the gnoweb path of a realm given as a package path.
//
// The chain domain is the first element of a package path and a gnoweb path is
// the rest of it, so this is a prefix strip and not a hostname this package
// has to know.
func RealmURL(realmPath string) string {
	if i := strings.Index(realmPath, "/"); i >= 0 {
		return realmPath[i:]
	}
	return "/" + realmPath
}
