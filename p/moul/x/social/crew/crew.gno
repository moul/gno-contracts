// Package crew is small-group coordination as a product rather than as a
// framework: three to fifteen people with a shared pot, a way to decide, and a
// way to leave with their share.
//
// # Why not a DAO framework
//
// A framework asks you to pick a governance module, a voting strategy and a
// treasury adapter before anybody has put in a single ugnot. The targets here
// are real and already exist: a validator set, a working group, a hackathon
// team, a five-person company. They want the thing you can create in one
// transaction. [gno.land/p/moul/grants] and daokit are the framework layer, and
// this package is deliberately underneath them: one call to open a crew, one to
// join it, one to leave with what your shares are worth.
//
// # The model
//
//	Crews     every crew, plus the credit ledger every payout goes through
//	Crew      a name, a creation height, members with shares, a treasury, proposals
//	Proposal  advisory text with a deadline and a share-weighted tally
//
// Shares are the whole design. They are the vote weight and the claim on the
// treasury at the same time, minted by [Crews.Join] and burned by
// [Crews.Ragequit], so leaving is priced by the same number that decides. There
// is no separate token to issue, distribute or forget to make meaningful.
//
// # Rounding, which is the part that has to be right
//
// Every division here rounds DOWN, and both of them therefore round in the
// crew's favour:
//
//   - joining mints amount * totalShares / treasury, so a late joiner buys
//     exactly what they paid for at the CURRENT per-share value and never a
//     share more. Rounding up would hand them a sliver of value the existing
//     members built, which is the whole reason a flat price is wrong here.
//   - ragequitting credits shares * treasury / totalShares, so a leaver takes
//     no more than their slice and the remainder stays with the people who
//     stayed.
//
// The dust that accrues from both is never stranded: the last member to
// ragequit holds every outstanding share, so their MulDiv is exact and the
// treasury empties to the last ugnot. [Crews.Ragequit] has a test for that.
//
// # What v0 deliberately does not do
//
// A proposal is advisory text. Passing one executes nothing, moves nothing and
// binds nothing; it records that the crew agreed by share weight at a point in
// time. Executing a payout is the obvious next step and the one that turns this
// into a treasury contract rather than a notice board.
//
// A vote is weighed at the moment it is cast. A member who votes and then
// ragequits leaves their weight behind in the tally, because unwinding it would
// mean re-weighing every ballot on every share change.
//
// # Errors, not aborts
//
// This is a p/, so it returns errors and declares no crossing function: the
// caller, the height and the amount all arrive as plain arguments and the realm
// that wires it to the chain decides what to abort on.
package crew

import (
	"errors"
	"strings"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/xmath/v1"
)

const (
	// MaxMembers is the upper end of "three to fifteen people". It is a
	// product constraint and not a technical one: above it the share math
	// still works and the thing stops being a crew.
	MaxMembers = 15

	// InitialPricePerShare is what a share costs in ugnot before the crew
	// has a treasury to price against: at creation, and again if every
	// member has left. 1000 ugnot makes 1 GNOT worth 1000 shares, which
	// keeps the integer arithmetic far away from both zero and overflow.
	InitialPricePerShare = int64(1000)

	// VoteBlocks is how long a proposal stays open, in blocks.
	VoteBlocks = int64(1000)

	// MaxNameLen and MaxTextLen bound what one call can make the crew's
	// members pay a storage deposit on.
	MaxNameLen = 60
	MaxTextLen = 500

	// ExcerptLen is how much of a proposal a listing shows.
	ExcerptLen = 60
)

// maxInt64 is the largest int64, spelled out because the overflow guards
// compare against it directly.
const maxInt64 = int64(9223372036854775807)

// The errors a caller can get back.
var (
	ErrBadName     = errors.New("crew: name is empty, too long, or has control characters")
	ErrBadText     = errors.New("crew: text is empty, too long, or has control characters")
	ErrBadAmount   = errors.New("crew: amount must be positive")
	ErrNoCrew      = errors.New("crew: no such crew")
	ErrNoProposal  = errors.New("crew: no such proposal")
	ErrNotMember   = errors.New("crew: not a member of this crew")
	ErrIsMember    = errors.New("crew: already a member of this crew")
	ErrFull        = errors.New("crew: the crew is full")
	ErrNoShares    = errors.New("crew: the amount sent buys no whole share")
	ErrVoteClosed  = errors.New("crew: the proposal is no longer open")
	ErrVoteOpen    = errors.New("crew: the proposal is still open")
	ErrNothing     = errors.New("crew: nothing to withdraw")
	ErrWouldExceed = errors.New("crew: the amount would overflow the ledger")
)

// Crew is one group: who is in it, what it holds, and what it is deciding.
type Crew struct {
	Name      string
	CreatedAt int64 // block height
	Treasury  int64 // ugnot, accounted here and held at the realm's address

	// TotalShares is every share outstanding. It is the denominator of both
	// the join price and the ragequit payout, so it is maintained here
	// rather than summed over the members on demand.
	TotalShares int64

	shares    map[string]int64 // address -> shares held
	order     []address        // members in join order, so output never iterates a map
	proposals []store.ID
}

// SharesOf is how many shares who holds, zero when they hold none.
func (c *Crew) SharesOf(who address) int64 {
	if c == nil {
		return 0
	}
	return c.shares[who.String()]
}

// IsMember reports whether who holds any share.
func (c *Crew) IsMember(who address) bool { return c.SharesOf(who) > 0 }

// MemberCount is how many addresses hold shares.
func (c *Crew) MemberCount() int {
	if c == nil {
		return 0
	}
	return len(c.order)
}

// Members returns the members in join order. The slice is a copy, so a caller
// rendering it cannot reorder the crew.
func (c *Crew) Members() []address {
	if c == nil {
		return nil
	}
	out := make([]address, len(c.order))
	copy(out, c.order)
	return out
}

// Proposals returns this crew's proposal ids, oldest first, as a copy.
func (c *Crew) Proposals() []store.ID {
	if c == nil {
		return nil
	}
	out := make([]store.ID, len(c.proposals))
	copy(out, c.proposals)
	return out
}

// ValuePerShare is what one share is worth in ugnot right now, rounded down.
//
// It is a display figure and nothing computes against it: [Crews.Join] and
// [Crews.Ragequit] divide by the real totals, so a crew whose treasury is
// smaller than its share count still prices both correctly while this reads 0.
func (c *Crew) ValuePerShare() int64 {
	if c == nil || c.TotalShares == 0 {
		return 0
	}
	return c.Treasury / c.TotalShares
}

// PricePerShare is what the next share costs a joiner, rounded down, which is
// [Crew.ValuePerShare] except on a crew nobody holds a share in.
func (c *Crew) PricePerShare() int64 {
	if c == nil || c.TotalShares == 0 || c.Treasury == 0 {
		return InitialPricePerShare
	}
	return c.Treasury / c.TotalShares
}

// ballot is one member's vote: which way, and what it weighed when cast.
type ballot struct {
	yes    bool
	weight int64
}

// Proposal is a question put to a crew. v0 proposals are advisory text and
// execute nothing: see the package doc.
type Proposal struct {
	CrewID   store.ID
	Author   address
	Text     string
	OpenedAt int64
	Deadline int64 // OpenedAt + VoteBlocks, exclusive

	// Yes and No are the running share-weighted tally, maintained on every
	// vote so reading it never walks the ballots.
	Yes int64
	No  int64

	Closed bool
	Passed bool

	votes map[string]ballot
}

// Open reports whether the proposal still accepts votes at height now.
func (p *Proposal) Open(now int64) bool {
	return p != nil && !p.Closed && now < p.Deadline
}

// VoteOf reports how who voted and what it weighed, and whether they voted at
// all.
func (p *Proposal) VoteOf(who address) (yes bool, weight int64, voted bool) {
	if p == nil {
		return false, 0, false
	}
	b, ok := p.votes[who.String()]
	return b.yes, b.weight, ok
}

// Voters is how many members have cast a ballot.
func (p *Proposal) Voters() int {
	if p == nil {
		return 0
	}
	return len(p.votes)
}

// Crews holds every crew, every proposal, and the credit ledger each payout
// goes through.
type Crews struct {
	crews *store.Store
	props *store.Store

	credit map[string]int64 // address -> ugnot owed
	owed   int64            // the sum of the above, which the holder must reserve
}

// New returns an empty Crews.
func New() *Crews {
	return &Crews{
		crews:  store.Named("crew"),
		props:  store.Named("proposal"),
		credit: map[string]int64{},
	}
}

// Create opens a crew with founder as its only member, their shares bought out
// of amount at [InitialPricePerShare].
//
// The remainder below one whole share stays in the treasury rather than being
// refunded, which is the same direction every other division here rounds.
func (cs *Crews) Create(name string, founder address, amount, at int64) (store.ID, error) {
	if !ValidName(name) {
		return 0, ErrBadName
	}
	if amount <= 0 {
		return 0, ErrBadAmount
	}
	shares := amount / InitialPricePerShare
	if shares < 1 {
		return 0, ErrNoShares
	}
	c := &Crew{
		Name:        name,
		CreatedAt:   at,
		Treasury:    amount,
		TotalShares: shares,
		shares:      map[string]int64{founder.String(): shares},
		order:       []address{founder},
	}
	return cs.crews.Add(c), nil
}

// Join mints who shares at the crew's CURRENT per-share value and adds amount
// to its treasury.
//
// amount * totalShares / treasury, rounded down. That is the whole anti-dilution
// rule: a crew that turned 10 GNOT into 20 sells the next share for what a share
// is worth now, not for what the founders paid, and the rounding remainder stays
// with the crew rather than with the joiner.
func (cs *Crews) Join(id store.ID, who address, amount int64) (int64, error) {
	c, ok := cs.Get(id)
	if !ok {
		return 0, ErrNoCrew
	}
	if amount <= 0 {
		return 0, ErrBadAmount
	}
	if c.IsMember(who) {
		return 0, ErrIsMember
	}
	if len(c.order) >= MaxMembers {
		return 0, ErrFull
	}
	if c.Treasury > maxInt64-amount {
		return 0, ErrWouldExceed
	}

	var shares int64
	if c.TotalShares == 0 || c.Treasury == 0 {
		// Nobody holds a share, so there is no value to price against and
		// the crew is back at its opening price.
		shares = amount / InitialPricePerShare
	} else {
		shares = xmath.MulDiv(amount, c.TotalShares, c.Treasury)
	}
	if shares < 1 {
		return 0, ErrNoShares
	}
	if c.TotalShares > maxInt64-shares {
		return 0, ErrWouldExceed
	}

	c.shares[who.String()] = shares
	c.order = append(c.order, who)
	c.TotalShares += shares
	c.Treasury += amount
	return shares, nil
}

// Fund adds amount to a crew's treasury and mints nothing.
//
// It is what makes the join price mean anything: a crew whose treasury only
// ever moves with its share count prices every joiner identically forever, and
// the anti-dilution rule in [Crews.Join] would be decorative. Revenue, a grant
// and a member topping the pot up all arrive this way, and every existing share
// is worth more afterwards.
func (cs *Crews) Fund(id store.ID, amount int64) error {
	c, ok := cs.Get(id)
	if !ok {
		return ErrNoCrew
	}
	if amount <= 0 {
		return ErrBadAmount
	}
	if c.Treasury > maxInt64-amount {
		return ErrWouldExceed
	}
	c.Treasury += amount
	return nil
}

// Propose opens an advisory question, open for [VoteBlocks] blocks. Any member
// may propose.
func (cs *Crews) Propose(id store.ID, who address, text string, at int64) (store.ID, error) {
	c, ok := cs.Get(id)
	if !ok {
		return 0, ErrNoCrew
	}
	if !c.IsMember(who) {
		return 0, ErrNotMember
	}
	if !ValidText(text) {
		return 0, ErrBadText
	}
	p := &Proposal{
		CrewID:   id,
		Author:   who,
		Text:     text,
		OpenedAt: at,
		Deadline: at + VoteBlocks,
		votes:    map[string]ballot{},
	}
	pid := cs.props.Add(p)
	c.proposals = append(c.proposals, pid)
	return pid, nil
}

// Vote records who's ballot, weighted by the shares they hold right now.
//
// One ballot per member, changeable while the proposal is open: a second call
// replaces the first, tally and weight both, so changing your mind after buying
// more shares counts the shares you now hold.
func (cs *Crews) Vote(pid store.ID, who address, yes bool, at int64) error {
	p, ok := cs.Proposal(pid)
	if !ok {
		return ErrNoProposal
	}
	if !p.Open(at) {
		return ErrVoteClosed
	}
	c, ok := cs.Get(p.CrewID)
	if !ok {
		return ErrNoCrew
	}
	weight := c.SharesOf(who)
	if weight <= 0 {
		return ErrNotMember
	}

	key := who.String()
	if prev, voted := p.votes[key]; voted {
		if prev.yes {
			p.Yes -= prev.weight
		} else {
			p.No -= prev.weight
		}
	}
	p.votes[key] = ballot{yes: yes, weight: weight}
	if yes {
		p.Yes += weight
	} else {
		p.No += weight
	}
	return nil
}

// Close records a proposal as passed or failed by share weight, once its
// deadline has gone by. Anyone may call it: closing is bookkeeping, not
// authority, and a proposal nobody closes is simply never recorded.
//
// A tie fails. There is no quorum in v0: a crew where one member votes and the
// rest ignore it passes the proposal, which is exactly as advisory as the text
// it carries.
func (cs *Crews) Close(pid store.ID, at int64) (bool, error) {
	p, ok := cs.Proposal(pid)
	if !ok {
		return false, ErrNoProposal
	}
	if p.Closed {
		return p.Passed, ErrVoteClosed
	}
	if at < p.Deadline {
		return false, ErrVoteOpen
	}
	p.Closed = true
	p.Passed = p.Yes > p.No
	return p.Passed, nil
}

// Ragequit burns every share who holds, credits them their pro-rata slice of
// the treasury and removes them from the crew.
//
// shares * treasury / totalShares, rounded down, so the remainder stays with
// the members who stayed. This is what makes a share mean something: the exit
// is priced by the same number that votes, and nobody has to agree to let you
// out.
//
// The payout is credited, never sent. The caller moves the coins after this
// returns, which is the ordering the pull-payment pattern exists for.
func (cs *Crews) Ragequit(id store.ID, who address) (shares, amount int64, err error) {
	c, ok := cs.Get(id)
	if !ok {
		return 0, 0, ErrNoCrew
	}
	shares = c.SharesOf(who)
	if shares <= 0 {
		return 0, 0, ErrNotMember
	}

	amount = xmath.MulDiv(shares, c.Treasury, c.TotalShares)
	c.TotalShares -= shares
	c.Treasury -= amount
	delete(c.shares, who.String())
	c.order = dropAddress(c.order, who)

	if amount > 0 {
		if err := cs.credits(who, amount); err != nil {
			return 0, 0, err
		}
	}
	return shares, amount, nil
}

// credits adds to an address's withdrawable balance.
func (cs *Crews) credits(who address, amount int64) error {
	key := who.String()
	if cs.credit[key] > maxInt64-amount || cs.owed > maxInt64-amount {
		return ErrWouldExceed
	}
	cs.credit[key] += amount
	cs.owed += amount
	return nil
}

// Withdraw zeroes who's credit and returns what they were owed.
//
// The balance is gone from the ledger before this returns, so the caller can
// move the coins afterwards and a reentrant call finds nothing: effects, then
// interactions.
func (cs *Crews) Withdraw(who address) (int64, error) {
	key := who.String()
	amount, ok := cs.credit[key]
	if !ok || amount == 0 {
		return 0, ErrNothing
	}
	delete(cs.credit, key)
	cs.owed -= amount
	return amount, nil
}

// CreditOf is what who can withdraw right now.
func (cs *Crews) CreditOf(who address) int64 { return cs.credit[who.String()] }

// TotalOwed is the sum of every outstanding credit, which is what the holding
// realm must keep in reserve on top of every crew's treasury.
func (cs *Crews) TotalOwed() int64 { return cs.owed }

// Get returns a crew by id.
func (cs *Crews) Get(id store.ID) (*Crew, bool) {
	v, ok := cs.crews.Get(id)
	if !ok {
		return nil, false
	}
	return v.(*Crew), true
}

// Proposal returns a proposal by id.
func (cs *Crews) Proposal(pid store.ID) (*Proposal, bool) {
	v, ok := cs.props.Get(pid)
	if !ok {
		return nil, false
	}
	return v.(*Proposal), true
}

// Len is how many crews exist.
func (cs *Crews) Len() int { return cs.crews.Len() }

// ProposalCount is how many proposals exist, across every crew.
func (cs *Crews) ProposalCount() int { return cs.props.Len() }

// Listing is one row of [Crews.List]: the crew and the id a link needs.
type Listing struct {
	ID   store.ID
	Crew *Crew
}

// List returns up to limit crews, newest first. limit below 1 returns nothing.
func (cs *Crews) List(limit int) []Listing {
	var out []Listing
	for _, e := range cs.crews.PageReverse(1, limit) {
		out = append(out, Listing{ID: e.ID, Crew: e.Value.(*Crew)})
	}
	return out
}

// ValidName reports whether name can be stored: non-empty after trimming,
// within [MaxNameLen], free of control characters including newlines, and
// free of the pipe character.
//
// The pipe is the one restriction that is not obvious, and it is here because
// a name is rendered as the TITLE of a link inside a table cell. md.Link
// escapes its title with the inline-text escaper, which deliberately leaves
// "|" alone because a pipe is markdown-inert outside a table, and wrapping the
// title in ui.Cell on top of that would double-escape and render the
// backslashes. Refusing the character at write time is the only place left
// where the fix is one rule rather than one exception per call site.
//
// A proposal's text has no such restriction: [ValidText] allows a pipe and the
// render escapes it with ui.Cell, because free prose legitimately contains one
// and a name does not.
func ValidName(name string) bool {
	if len(name) > MaxNameLen || strings.TrimSpace(name) == "" {
		return false
	}
	for i := 0; i < len(name); i++ {
		c := name[i]
		if c < 0x20 || c == 0x7f || c == '|' {
			return false
		}
	}
	return true
}

// ValidText reports whether a proposal body can be stored: non-empty after
// trimming, within [MaxTextLen], and free of control characters other than
// newline and tab.
//
// Control characters are refused rather than stripped because the text is shown
// back to its author, and silently rewriting what somebody wrote is worse than
// telling them it was refused. Everything else is allowed and escaped at render
// time: a validator and an escaper protect against different mistakes.
func ValidText(text string) bool {
	if len(text) > MaxTextLen || strings.TrimSpace(text) == "" {
		return false
	}
	for i := 0; i < len(text); i++ {
		c := text[i]
		if c < 0x20 && c != '\n' && c != '\t' || c == 0x7f {
			return false
		}
	}
	return true
}

// dropAddress returns addrs without who, in a freshly allocated slice.
//
// It allocates rather than shortening in place: a slice is one persisted object
// and the storage deposit only comes back when that object is dropped, so
// append(s[:i], s[i+1:]...) would keep the peak allocation charged forever.
func dropAddress(addrs []address, who address) []address {
	out := make([]address, 0, len(addrs))
	for _, a := range addrs {
		if a != who {
			out = append(out, a)
		}
	}
	return out
}
