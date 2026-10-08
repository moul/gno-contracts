// Package curated is the engine behind a curated list where being on the list
// costs something: anyone may list an entry by locking a deposit, anyone may
// challenge an entry by matching that deposit with a bond, and the loser of the
// challenge pays the winner.
//
// # Why a deposit
//
// A list anybody can write to for free is a list nobody can read, because the
// cheapest way to be on it is to be on it a thousand times. A deposit does not
// make an entry good; it makes a bad entry expensive to leave standing, because
// somebody who disagrees can put the same amount at risk and take yours. The
// list is worth reading in proportion to what it would cost to pollute it.
//
// # The model
//
//	Registry  every entry, plus the credit ledger the payouts land in
//	Entry     a key, a URL, a description, an owner, the deposit, the height
//	          it was listed at, and one of three states
//	Challenge a challenger, a matching bond, a deadline, and the votes
//
// A key is unique while it is on the list ([ValidKey] bounds it to a
// slug), and a removed key is free again: a challenge that wins removes an
// entry, it does not burn the name forever.
//
// # The money, and why nothing is ever sent from here
//
// This package moves no coins. Every payout is a credit in an internal ledger
// that the payee collects with [Registry.Withdraw], which is the pull-payment
// shape: a realm that loops over winners and sends to each one fails entirely
// when one of them cannot be paid, and hands a griefer a cheap denial of
// service. [Registry.Locked] plus [Registry.Owed] is what the holding realm
// must have at its address, and a realm can assert exactly that.
//
// # Voting is sybil-prone, deliberately and visibly
//
// [Registry.Vote] is one address, one vote, unweighted. An address is free, so
// a challenge outcome is a poll of whoever bothered to make keys, not of
// anybody in particular. That is not a gap this package can close: deciding who
// counts as a person is a different problem with a different realm behind it,
// r/moul/x/social/vouch, a sibling in this family. Until a vote is
// gated on a vouched identity, read a resolution as "nobody with a stake
// objected enough", not as a verdict.
//
// # What v0 does not do, in the order it should be fixed
//
//  1. Voters are paid nothing. Voting costs gas and returns nothing, so the
//     only addresses with a reason to vote are the two with money on the
//     outcome. A share of the loser's stake for the winning side is the
//     standard answer and it is the first thing to add.
//  2. There is no application period: [Registry.Apply] lists immediately, so a
//     bad entry is visible until somebody challenges it.
//  3. A challenge cannot be withdrawn, and a vote cannot be changed.
package curated

import (
	"chain/markdown"
	"errors"
	"strings"
)

const (
	// MaxKeyLen is the longest key accepted. A key is a name people type and
	// link to, not a payload.
	MaxKeyLen = 64

	// MaxURLLen and MaxDescLen bound what one entry can lock up of somebody
	// else's storage deposit.
	MaxURLLen  = 240
	MaxDescLen = 240

	// MaxEntries bounds the registry so a listing stays predictable in gas.
	MaxEntries = 4096

	// MaxPayees bounds the credit ledger for the same reason.
	MaxPayees = 4096
)

const maxInt64 = int64(9223372036854775807)

// The errors a caller can get back. A p/ returns them; the realm decides to
// abort.
var (
	ErrBadKey         = errors.New("curated: not a key: 1 to 64 bytes of a-z 0-9 - _ . starting alphanumeric")
	ErrBadURL         = errors.New("curated: url is empty, too long, or has a space or a control character")
	ErrBadDescription = errors.New("curated: description is empty, too long, or not a single line")
	ErrTaken          = errors.New("curated: that key is already on the list")
	ErrNoEntry        = errors.New("curated: no such entry")
	ErrWrongDeposit   = errors.New("curated: the deposit must be paid exactly")
	ErrWrongBond      = errors.New("curated: the bond must match the entry's deposit")
	ErrChallenged     = errors.New("curated: that entry is under challenge")
	ErrSelfChallenge  = errors.New("curated: an owner cannot challenge their own entry")
	ErrNoChallenge    = errors.New("curated: that entry is not under challenge")
	ErrVotingClosed   = errors.New("curated: the challenge deadline has passed")
	ErrAlreadyVoted   = errors.New("curated: one address, one vote")
	ErrTooEarly       = errors.New("curated: the challenge is still open")
	ErrNotOwner       = errors.New("curated: only the entry's owner can do that")
	ErrNothingOwed    = errors.New("curated: nothing to withdraw")
	ErrFull           = errors.New("curated: the registry is full")
	ErrOverflow       = errors.New("curated: the credit would overflow")
	ErrBadAmount      = errors.New("curated: amount must be positive")
)

// State is where an entry stands.
type State uint8

const (
	// StateListed is on the list and unchallenged.
	StateListed State = iota

	// StateChallenged is on the list with a challenge open against it. It
	// still renders: a challenge is an objection, not a verdict.
	StateChallenged

	// StateRemoved is off the list, either lost to a challenge or taken down
	// by its own owner. The key is free for anyone to apply for again.
	StateRemoved
)

// String names the state for a reader and for an event.
func (s State) String() string {
	switch s {
	case StateListed:
		return "listed"
	case StateChallenged:
		return "challenged"
	case StateRemoved:
		return "removed"
	default:
		return "unknown"
	}
}

// Challenge is an open objection to one entry.
type Challenge struct {
	Challenger address
	Bond       int64
	Deadline   int64 // block height the voting stops at, exclusive

	// Keep and Remove are the unweighted vote counts. See the package doc on
	// what they are and are not worth.
	Keep   int64
	Remove int64

	// voters is the set of addresses that have voted, so one address votes
	// once. It is unexported: a caller reads [Challenge.Voters].
	voters map[string]bool
}

// Voters is how many distinct addresses have voted.
func (c *Challenge) Voters() int {
	if c == nil {
		return 0
	}
	return len(c.voters)
}

// HasVoted reports whether who has already voted in this challenge.
func (c *Challenge) HasVoted(who address) bool {
	if c == nil {
		return false
	}
	return c.voters[who.String()]
}

// Open reports whether votes are still being taken at height now.
func (c *Challenge) Open(now int64) bool { return c != nil && now < c.Deadline }

// Entry is one row of the list.
type Entry struct {
	Key         string
	URL         string
	Description string
	Owner       address
	Deposit     int64 // what the owner locked to list it
	At          int64 // the block height it was listed at
	State       State

	// challenge is the open objection, or nil. It is cleared on resolution:
	// the outcome is in the entry's state and in the ledger, and keeping a
	// resolved challenge would be a second place to read it from.
	challenge *Challenge
}

// Live reports whether the entry is on the list, challenged or not.
func (e *Entry) Live() bool { return e != nil && e.State != StateRemoved }

// Registry is the whole list: the entries, and the credits waiting to be
// withdrawn.
type Registry struct {
	deposit         int64
	challengeBlocks int64

	entries map[string]*Entry
	order   []string // keys in the order they were first listed

	credits map[string]int64
	owed    int64
	locked  int64
}

// New returns an empty registry where listing costs deposit and a challenge
// runs for challengeBlocks blocks.
//
// Both are fixed for the life of the registry. An entry remembers the deposit
// it actually paid, so a future registry that can reprice itself still charges
// a challenger what the owner of that entry risked, and not today's number.
func New(deposit, challengeBlocks int64) *Registry {
	return &Registry{
		deposit:         deposit,
		challengeBlocks: challengeBlocks,
		entries:         map[string]*Entry{},
		credits:         map[string]int64{},
	}
}

// Deposit is what listing costs.
func (r *Registry) Deposit() int64 { return r.deposit }

// ChallengeBlocks is how long a challenge takes to resolve.
func (r *Registry) ChallengeBlocks() int64 { return r.challengeBlocks }

// Apply lists an entry immediately, in exchange for exactly the deposit.
//
// There is no application period in v0: the entry is on the list the moment the
// deposit is paid, and the check on it is that anybody can challenge it.
//
// A key whose entry was removed is free again, and applying for it writes a
// fresh entry in the same position in the listing order.
func (r *Registry) Apply(key, url, description string, owner address, paid, now int64) error {
	if !ValidKey(key) {
		return ErrBadKey
	}
	if !ValidURL(url) {
		return ErrBadURL
	}
	if !ValidDescription(description) {
		return ErrBadDescription
	}
	if paid != r.deposit {
		return ErrWrongDeposit
	}
	old, seen := r.entries[key]
	if seen && old.Live() {
		return ErrTaken
	}
	if !seen {
		if len(r.order) >= MaxEntries {
			return ErrFull
		}
		r.order = append(r.order, key)
	}
	r.entries[key] = &Entry{
		Key:         key,
		URL:         url,
		Description: description,
		Owner:       owner,
		Deposit:     paid,
		At:          now,
		State:       StateListed,
	}
	r.locked += paid
	return nil
}

// BondFor is what challenging key would cost, and whether it can be challenged
// at all.
//
// The realm reads this BEFORE it reads the envelope, so a caller who attaches
// coins to a challenge of something unchallengeable is refused on the entry and
// not on the amount.
func (r *Registry) BondFor(key string) (int64, bool) {
	e, ok := r.entries[key]
	if !ok || e.State != StateListed {
		return 0, false
	}
	return e.Deposit, true
}

// Challenge opens an objection to an entry, against a bond equal to that
// entry's deposit, and sets the deadline at now + ChallengeBlocks.
//
// An owner may not challenge their own entry. It would cost nothing (a kept
// entry credits its owner the bond, which here is their own) and it would make
// the entry immune to a real challenge for the whole window.
func (r *Registry) Challenge(key string, challenger address, bond, now int64) error {
	e, ok := r.entries[key]
	if !ok || !e.Live() {
		return ErrNoEntry
	}
	if e.State == StateChallenged {
		return ErrChallenged
	}
	if challenger == e.Owner {
		return ErrSelfChallenge
	}
	if bond != e.Deposit {
		return ErrWrongBond
	}
	e.State = StateChallenged
	e.challenge = &Challenge{
		Challenger: challenger,
		Bond:       bond,
		Deadline:   now + r.challengeBlocks,
		voters:     map[string]bool{},
	}
	r.locked += bond
	return nil
}

// Vote records one address's opinion on an open challenge: keep the entry, or
// remove it.
//
// One address, one vote, unweighted, and it cannot be changed. Anyone may vote,
// including the owner and the challenger, because excluding them would only
// move their vote to another address they control. See the package doc: this is
// sybil-prone on purpose rather than by oversight, and gating it is the job of
// the vouch realm.
func (r *Registry) Vote(key string, voter address, keep bool, now int64) error {
	e, ok := r.entries[key]
	if !ok {
		return ErrNoEntry
	}
	c := e.challenge
	if e.State != StateChallenged || c == nil {
		return ErrNoChallenge
	}
	if !c.Open(now) {
		return ErrVotingClosed
	}
	k := voter.String()
	if c.voters[k] {
		return ErrAlreadyVoted
	}
	c.voters[k] = true
	if keep {
		c.Keep++
	} else {
		c.Remove++
	}
	return nil
}

// Outcome is what a resolution decided and who it paid.
type Outcome struct {
	Key    string
	Kept   bool
	Winner address
	Amount int64 // credited to the winner
	Keep   int64
	Remove int64
}

// Resolve closes a challenge whose deadline has passed. Anyone may call it: the
// two parties both have a reason to and neither can stall the other.
//
// A majority of keep votes keeps the entry and credits its owner the
// challenger's bond. Otherwise the entry is removed and the challenger is
// credited the bond plus the deposit.
//
// A TIE KEEPS THE ENTRY, including the tie of nobody voting at all. The
// incumbent paid first and is already at risk, so the burden is on the
// challenger to produce a reason; if ties went the other way, a challenge that
// convinced nobody would still win, and listing anything would be pointless.
// The cost of that choice is the one a challenger signs up for: being wrong
// costs the bond.
func (r *Registry) Resolve(key string, now int64) (Outcome, error) {
	e, ok := r.entries[key]
	if !ok {
		return Outcome{}, ErrNoEntry
	}
	c := e.challenge
	if e.State != StateChallenged || c == nil {
		return Outcome{}, ErrNoChallenge
	}
	if c.Open(now) {
		return Outcome{}, ErrTooEarly
	}

	out := Outcome{Key: key, Kept: c.Keep >= c.Remove, Keep: c.Keep, Remove: c.Remove}
	if out.Kept {
		out.Winner, out.Amount = e.Owner, c.Bond
	} else {
		out.Winner, out.Amount = c.Challenger, c.Bond+e.Deposit
	}

	// Credit first: it is the only step that can fail, and a half-applied
	// resolution would leave an entry with no challenge and nobody paid.
	if err := r.credit(out.Winner, out.Amount); err != nil {
		return Outcome{}, err
	}
	if out.Kept {
		e.State = StateListed
		r.locked -= c.Bond
	} else {
		e.State = StateRemoved
		r.locked -= c.Bond + e.Deposit
	}
	e.challenge = nil
	return out, nil
}

// Unlist takes an owner's own entry down and credits them the deposit back.
//
// It is refused while a challenge is open, which is the whole point of the
// bond: an owner who could walk away mid-challenge would be risking nothing.
func (r *Registry) Unlist(key string, owner address) error {
	e, ok := r.entries[key]
	if !ok || !e.Live() {
		return ErrNoEntry
	}
	if e.Owner != owner {
		return ErrNotOwner
	}
	if e.State == StateChallenged {
		return ErrChallenged
	}
	if err := r.credit(owner, e.Deposit); err != nil {
		return err
	}
	e.State = StateRemoved
	r.locked -= e.Deposit
	return nil
}

// Withdraw zeroes who's credit and returns what they were owed.
//
// The holding realm sends the coins AFTER this returns. That ordering is the
// pattern: the credit is already gone from the ledger when control passes to
// the recipient, so a reentrant withdrawal finds ErrNothingOwed.
func (r *Registry) Withdraw(who address) (int64, error) {
	k := who.String()
	amount := r.credits[k]
	if amount <= 0 {
		return 0, ErrNothingOwed
	}
	delete(r.credits, k) // effects before interactions
	r.owed -= amount
	return amount, nil
}

// credit records that who is owed amount more.
func (r *Registry) credit(who address, amount int64) error {
	if amount <= 0 {
		return ErrBadAmount
	}
	k := who.String()
	have, seen := r.credits[k]
	if !seen && len(r.credits) >= MaxPayees {
		return ErrFull
	}
	if have > maxInt64-amount || r.owed > maxInt64-amount {
		return ErrOverflow
	}
	r.credits[k] = have + amount
	r.owed += amount
	return nil
}

// Get returns an entry by key, whatever its state, and whether it ever existed.
func (r *Registry) Get(key string) (*Entry, bool) {
	e, ok := r.entries[key]
	return e, ok
}

// IsListed reports whether key is on the list right now. A challenged entry is
// still listed.
func (r *Registry) IsListed(key string) bool {
	e, ok := r.entries[key]
	return ok && e.Live()
}

// Count is how many entries are on the list right now.
func (r *Registry) Count() int {
	n := 0
	for _, key := range r.order {
		if r.entries[key].Live() {
			n++
		}
	}
	return n
}

// Records is how many keys the registry has ever held, removed ones included.
func (r *Registry) Records() int { return len(r.order) }

// Listed returns every entry on the list, oldest first.
//
// The order comes from a slice and not from iterating the map, so it is a
// stable sequence a Render can be pinned against rather than an insertion order
// that a delete-and-re-add would reshuffle.
func (r *Registry) Listed() []*Entry {
	out := []*Entry{}
	for _, key := range r.order {
		if e := r.entries[key]; e.Live() {
			out = append(out, e)
		}
	}
	return out
}

// Challenged returns every entry with a challenge open against it, oldest
// listing first.
func (r *Registry) Challenged() []*Entry {
	out := []*Entry{}
	for _, key := range r.order {
		if e := r.entries[key]; e.State == StateChallenged {
			out = append(out, e)
		}
	}
	return out
}

// ChallengeOf returns the open challenge against key, if there is one.
func (r *Registry) ChallengeOf(key string) (*Challenge, bool) {
	e, ok := r.entries[key]
	if !ok || e.challenge == nil {
		return nil, false
	}
	return e.challenge, true
}

// CreditOf is what who can withdraw right now.
func (r *Registry) CreditOf(who address) int64 { return r.credits[who.String()] }

// Owed is every credit not yet withdrawn.
func (r *Registry) Owed() int64 { return r.owed }

// Locked is the deposits behind live entries plus the bonds behind open
// challenges.
//
// Locked plus [Registry.Owed] is what the holding realm must have at its
// address: every ugnot it ever took is either still backing something or
// already assigned to somebody. A realm can assert that equality against its
// own balance, and this package's tests do.
func (r *Registry) Locked() int64 { return r.locked }

// ValidKey reports whether key is usable: 1 to [MaxKeyLen] bytes of lowercase
// ASCII letters, digits, '-', '_' and '.', starting with a letter or a digit.
//
// The leading-alphanumeric rule is what stops "." and "..", and what stops a
// key that reads as punctuation in the list it is shown in. The charset is
// narrow so a key can be typed, linked and compared without surprises; it is
// still escaped at render time, because a validator and an escaper protect
// against different mistakes.
func ValidKey(key string) bool {
	if key == "" || len(key) > MaxKeyLen {
		return false
	}
	if c := key[0]; !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9') {
		return false
	}
	for i := 0; i < len(key); i++ {
		c := key[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		case c == '-' || c == '_' || c == '.':
		default:
			return false
		}
	}
	return true
}

// ValidURL reports whether url can be stored: non-empty after the render's own
// stripping and trimming, within [MaxURLLen],
// and free of spaces and control characters.
//
// No scheme is required, because a list of on-chain things is the obvious use
// and those have no host. A renderer treats a schemeless URL as a path
// relative to the chain's web root, so an on-chain target is written
// "/r/moul/home" and an off-chain one carries its own "https://".
//
// Nothing here checks that the target exists: a deposit backs the claim that
// the entry is worth listing, not the claim that it resolves.
func ValidURL(url string) bool {
	if strings.TrimSpace(markdown.StripBidiAndZeroWidth(url)) == "" || len(url) > MaxURLLen {
		return false
	}
	for i := 0; i < len(url); i++ {
		if c := url[i]; c <= 0x20 || c == 0x7f {
			return false
		}
	}
	return true
}

// ValidDescription reports whether description can be stored: non-empty after
// the render's own stripping and trimming, within [MaxDescLen], and a single line.
//
// Newlines and tabs are refused rather than stripped, because a description is
// shown back to the person who wrote it and silently rewriting it is worse than
// telling them it was refused. It lives in a table cell, which a newline would
// break out of and an escaper would then have to repair.
func ValidDescription(description string) bool {
	if len(description) > MaxDescLen || strings.TrimSpace(markdown.StripBidiAndZeroWidth(description)) == "" {
		return false
	}
	for i := 0; i < len(description); i++ {
		if c := description[i]; c < 0x20 || c == 0x7f {
			return false
		}
	}
	return true
}
