// Package vouch is the engine behind a web of trust: one address says it
// stands behind another, in writing, optionally with its own money locked
// against the claim.
//
// # What it is for
//
// It is a sybil gate, and it exists because the apps around it do not have
// one. A realm that mints a point per distinct replier is farmed by two
// addresses replying to each other; a realm that counts one vote per address
// is farmed by holding a hundred addresses. Neither can fix that alone,
// because neither knows anything about the people behind the addresses.
//
// This package knows one thing: who was willing to say, on chain and under
// their own name, that an address is a person they stand behind. A realm asks
// [Graph.IsTrusted] and gates on the answer. That is the whole product, and
// every other read here exists to make that one legible.
//
// # The model
//
//	Graph   every vouch, in both directions, plus the refund ledger
//	Vouch   a directed statement: from, for, reason, bond, heights
//
// A vouch is directed and at most one exists per ordered pair. A second
// [Graph.Record] from the same address to the same target UPDATES the reason
// and ADDS to the bond rather than counting twice, which is what makes the
// score a count of people instead of a count of transactions. An address
// cannot vouch for itself.
//
// # The bond
//
// A vouch may lock coins. The engine only counts them: it takes the amount as
// an argument, tracks who posted how much on whom, and on [Graph.Revoke] moves
// that amount into a withdrawal ledger the voucher pulls from. It moves
// nothing itself. The realm holding the coins performs the transfer AFTER
// [Graph.Withdraw] has zeroed the credit, which is the ordering the
// pull-payment pattern demands.
//
// # No slashing, and why that is the hard part
//
// A bond here is value at risk only in the sense that it is illiquid: it can
// be withdrawn by revoking, and nothing can take it away. That is deliberate
// for a v0, and the missing half is not the accounting.
//
// Slashing needs an arbiter: somebody has to decide that a vouch was a lie.
// Every candidate is a design question with teeth. A DAO vote is a popularity
// contest against whoever is unpopular this month. A challenge market pays
// whoever is loudest and turns the graph into a griefing surface. An oracle is
// one key that can confiscate anyone's money. Shipping any of them by default
// would be shipping the wrong one, so this version ships the part that is
// uncontroversial: who said what, who put money behind it, and the gate that
// reads it.
//
// # Reasons are attacker-controlled markdown
//
// A reason is free text. [ValidReason] bounds it to [MaxReasonLen] bytes on
// one line and refuses control characters, but everything inside that is
// allowed and must be escaped where it is shown: ui.Inline in prose, ui.Cell
// in a table cell.
package vouch

import (
	"errors"
	"strconv"
	"strings"

	"gno.land/p/moul/addrset/v1"
	"gno.land/p/moul/kit/num/v0"
	"gno.land/p/moul/kit/tally/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/pullpayment/v0"
)

// MaxReasonLen is the longest reason accepted, in bytes. Long enough to say
// how you know somebody, short enough that one call cannot lock an unbounded
// storage deposit the realm's deployer is paying for.
const MaxReasonLen = 200

const maxInt64 = int64(9223372036854775807)

// The errors a caller can get back. A p/ returns them; the realm decides to
// abort.
var (
	ErrSelfVouch   = errors.New("vouch: an address cannot vouch for itself")
	ErrBadReason   = errors.New("vouch: reason is empty, too long, multi-line, or has control characters")
	ErrBadBond     = errors.New("vouch: a bond cannot be negative")
	ErrNoVouch     = errors.New("vouch: no such vouch")
	ErrNothingOwed = errors.New("vouch: nothing to withdraw")
	ErrOverflow    = errors.New("vouch: bond would overflow")
)

// Vouch is one directed statement of trust.
type Vouch struct {
	From   address
	For    address
	Reason string

	// Bond is the amount locked on this vouch, in the realm's denom. It is
	// the sum of every bond sent with this pair, since a repeated vouch
	// adds to it rather than replacing it.
	Bond int64

	// At is the height the vouch was first made, UpdatedAt the height it
	// last changed. They are equal until the voucher restates it.
	At        int64
	UpdatedAt int64
}

// Graph is the whole web of trust: every vouch, both directions of every
// edge, what is bonded on whom, and what revoking owes back to whom.
type Graph struct {
	edges    map[string]*Vouch       // "from|for" -> the vouch
	inbound  map[string]*addrset.Set // target -> who vouches for them
	outbound map[string]*addrset.Set // voucher -> who they vouch for
	bonded   map[string]int64        // target -> total bonded on them

	// people is every address with at least one inbound vouch, sorted, so
	// a listing never has to iterate a map to build rendered output.
	people addrset.Set

	refunds     *pullpayment.Ledger
	count       int
	totalBonded int64
}

// NewGraph returns an empty graph.
func NewGraph() *Graph {
	return &Graph{
		edges:    map[string]*Vouch{},
		inbound:  map[string]*addrset.Set{},
		outbound: map[string]*addrset.Set{},
		bonded:   map[string]int64{},
		refunds:  pullpayment.New(),
	}
}

// Record writes from's vouch for target and reports whether it replaced one
// that already existed.
//
// A repeated vouch is an update and not a second voice: the reason is
// replaced, the bond is added to the one already posted, and the score does
// not move. bond may be zero, which is the ordinary case.
func (g *Graph) Record(from, target address, reason string, bond, at int64) (updated bool, err error) {
	if from == target {
		return false, ErrSelfVouch
	}
	if !ValidReason(reason) {
		return false, ErrBadReason
	}
	if bond < 0 {
		return false, ErrBadBond
	}
	tk := target.String()
	if g.bonded[tk] > maxInt64-bond || g.totalBonded > maxInt64-bond {
		return false, ErrOverflow
	}

	if v, ok := g.edges[key(from, target)]; ok {
		if v.Bond > maxInt64-bond {
			return false, ErrOverflow
		}
		v.Reason = reason
		v.Bond += bond
		v.UpdatedAt = at
		g.bonded[tk] += bond
		g.totalBonded += bond
		return true, nil
	}

	g.edges[key(from, target)] = &Vouch{
		From:      from,
		For:       target,
		Reason:    reason,
		Bond:      bond,
		At:        at,
		UpdatedAt: at,
	}
	g.set(g.inbound, tk).Add(from)
	g.set(g.outbound, from.String()).Add(target)
	g.people.Add(target)
	g.bonded[tk] += bond
	g.totalBonded += bond
	g.count++
	return false, nil
}

// Revoke removes from's vouch for target and credits the bond back to from,
// returning the amount credited.
//
// The coins are not sent here and this package never holds any: the credit
// waits in the refund ledger until from calls [Graph.Withdraw].
func (g *Graph) Revoke(from, target address) (refund int64, err error) {
	v, ok := g.edges[key(from, target)]
	if !ok {
		return 0, ErrNoVouch
	}
	// Credit first, because it is the only step that can fail. Nothing is
	// mutated until the refund is certain, so a full ledger leaves the
	// graph exactly as it was rather than half revoked.
	if v.Bond > 0 {
		if err := g.refunds.Credit(from.String(), v.Bond); err != nil {
			return 0, err
		}
	}

	delete(g.edges, key(from, target))
	tk, fk := target.String(), from.String()

	if in, ok := g.inbound[tk]; ok {
		in.Remove(from)
		if in.Size() == 0 {
			delete(g.inbound, tk)
			g.people.Remove(target)
		}
	}
	if out, ok := g.outbound[fk]; ok {
		out.Remove(target)
		if out.Size() == 0 {
			delete(g.outbound, fk)
		}
	}

	g.bonded[tk] -= v.Bond
	if g.bonded[tk] == 0 {
		delete(g.bonded, tk)
	}
	g.totalBonded -= v.Bond
	g.count--
	return v.Bond, nil
}

// Withdraw zeroes what the graph owes who and returns it, so the realm can
// send exactly that much.
//
// The credit is gone from the ledger before this returns, which is what makes
// a reentrant call find nothing: the realm transfers after, never before.
func (g *Graph) Withdraw(who address) (int64, error) {
	amount, err := g.refunds.Withdraw(who.String())
	if err != nil {
		return 0, ErrNothingOwed
	}
	return amount, nil
}

// Get returns one vouch.
func (g *Graph) Get(from, target address) (*Vouch, bool) {
	v, ok := g.edges[key(from, target)]
	return v, ok
}

// ScoreOf is how many distinct addresses vouch for addr.
//
// It counts people and not statements: restating a vouch does not raise it,
// and revoking lowers it.
func (g *Graph) ScoreOf(addr address) int {
	if in, ok := g.inbound[addr.String()]; ok {
		return in.Size()
	}
	return 0
}

// BondedFor is the total locked on addr by everyone vouching for them.
func (g *Graph) BondedFor(addr address) int64 { return g.bonded[addr.String()] }

// IsTrusted reports whether addr is vouched for by at least min distinct
// addresses. It is the gate another realm calls, and the reason this package
// exists.
//
// A min below one is raised to one. A gate that lets everybody through is a
// bug at the call site rather than an answer worth returning, and silently
// agreeing with it is how a sybil check ships disabled.
//
// What it cannot tell you is whether those vouchers are distinct PEOPLE. Two
// addresses vouching for each other both reach a score of one for the price of
// two transactions, which is why [Graph.Mutual] is exported and why a gate
// that matters should ask for more than one.
func (g *Graph) IsTrusted(addr address, min int) bool {
	if min < 1 {
		min = 1
	}
	return g.ScoreOf(addr) >= min
}

// VouchedBy is every address that vouches for addr, sorted.
//
// Sorted and not chronological: the set is the storage, the order is a total
// order on the address, and two identical calls therefore render identically.
func (g *Graph) VouchedBy(addr address) []address {
	return collect(g.inbound[addr.String()])
}

// VouchesOf is every address addr vouches for, sorted. It is the other
// direction of [Graph.VouchedBy].
func (g *Graph) VouchesOf(addr address) []address {
	return collect(g.outbound[addr.String()])
}

// Mutual reports whether a and b vouch for each other.
//
// A mutual pair is the cheapest sybil shape there is, so this is here to be
// discounted by a caller that cares, not as a badge.
func (g *Graph) Mutual(a, b address) bool {
	if a == b {
		return false
	}
	_, there := g.edges[key(a, b)]
	_, back := g.edges[key(b, a)]
	return there && back
}

// ReasonFrom is what from wrote about target, or the empty string when there
// is no such vouch. It is raw caller text: escape it where it is shown.
func (g *Graph) ReasonFrom(from, target address) string {
	if v, ok := g.edges[key(from, target)]; ok {
		return v.Reason
	}
	return ""
}

// BondFrom is what from locked on target, or zero.
func (g *Graph) BondFrom(from, target address) int64 {
	if v, ok := g.edges[key(from, target)]; ok {
		return v.Bond
	}
	return 0
}

// Count is how many vouches exist, across everybody.
func (g *Graph) Count() int { return g.count }

// People is how many addresses have at least one vouch for them.
func (g *Graph) People() int { return g.people.Size() }

// Owed is what revoking has credited to addr and nobody has withdrawn yet.
func (g *Graph) Owed(addr address) int64 { return g.refunds.Balance(addr.String()) }

// TotalOwed is every unwithdrawn refund. The realm must hold at least
// TotalOwed plus [Graph.TotalBonded] to be solvent.
func (g *Graph) TotalOwed() int64 { return g.refunds.TotalOwed() }

// TotalBonded is everything locked on every vouch that still stands.
func (g *Graph) TotalBonded() int64 { return g.totalBonded }

// Ranked is one row of [Graph.Leaderboard].
type Ranked struct {
	Addr   address
	Score  int
	Bonded int64
}

// Leaderboard is the most vouched for addresses, highest score first, ties
// broken by address so the order is total and a Render never reshuffles.
//
// limit at or below zero returns nothing.
func (g *Graph) Leaderboard(limit int) []Ranked {
	if limit <= 0 || g.people.Size() == 0 {
		return nil
	}
	entries := make([]tally.Entry, 0, g.people.Size())
	g.people.IterateByOffset(0, g.people.Size(), func(a address) bool {
		entries = append(entries, tally.Entry{Key: a.String(), Score: int64(g.ScoreOf(a))})
		return false
	})
	top := tally.Top(entries, limit)

	out := make([]Ranked, 0, len(top))
	for _, e := range top {
		a := address(e.Key)
		out = append(out, Ranked{Addr: a, Score: int(e.Score), Bonded: g.bonded[e.Key]})
	}
	return out
}

// ValidReason reports whether reason can be stored: non-empty after trimming,
// within [MaxReasonLen], on one line, and free of control characters.
//
// One line is a deliberate bound rather than a rendering workaround. A reason
// is shown in a table cell beside the address it is about, and a writer who
// needs a second paragraph is writing something other than a reason.
//
// Control characters are refused rather than stripped because the text is
// shown back to whoever wrote it, and silently rewriting what somebody said is
// worse than telling them it was refused. Everything else is allowed and
// escaped at render time, since a validator and an escaper protect against
// different mistakes.
func ValidReason(reason string) bool {
	if len(reason) > MaxReasonLen || strings.TrimSpace(reason) == "" {
		return false
	}
	for i := 0; i < len(reason); i++ {
		if c := reason[i]; c < 0x20 || c == 0x7f {
			return false
		}
	}
	return true
}

// Badge is the one-line trust mark, for a realm that wants to show what the
// gate it just called was reading.
//
// It takes the numbers rather than the graph because the realm holding the
// graph is the only one that can read it: everybody else has the two integers
// from a cross-realm call and needs nothing more to render them.
func Badge(realmPath string, addr address, score int, bonded int64) string {
	if score == 0 {
		return md.Link("not vouched for", AddrURL(realmPath, addr))
	}
	word := " vouchers"
	if score == 1 {
		word = " voucher"
	}
	out := "\U0001F91D " + md.Link(strconv.Itoa(score)+word, AddrURL(realmPath, addr))
	if bonded > 0 {
		out += " · " + num.GNOTf(bonded) + " bonded"
	}
	return out
}

// AddrURL is the gnoweb path of one address's page on the hosting realm.
func AddrURL(realmPath string, addr address) string {
	return RealmURL(realmPath) + ":addr/" + addr.String()
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

// key is the storage key of one directed edge. Addresses are fixed-length
// bech32, so the separator is belt and braces rather than load-bearing.
func key(from, target address) string { return from.String() + "|" + target.String() }

// set returns the address set stored under k, creating it on first use.
func (g *Graph) set(m map[string]*addrset.Set, k string) *addrset.Set {
	if s, ok := m[k]; ok {
		return s
	}
	s := &addrset.Set{}
	m[k] = s
	return s
}

// collect reads a set out in sorted order.
func collect(s *addrset.Set) []address {
	if s == nil || s.Size() == 0 {
		return nil
	}
	out := make([]address, 0, s.Size())
	s.IterateByOffset(0, s.Size(), func(a address) bool {
		out = append(out, a)
		return false
	})
	return out
}
