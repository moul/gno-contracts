// Package faucet hands a small amount of GNOT to someone who has none, on the
// record, in two calls that are meant to travel in one transaction.
//
// The chain's own faucet is gated and the people who most need a first coin
// are exactly the people who cannot ask for one: an empty account cannot pay
// the gas to call anything. So somebody else files the request on their
// behalf, an approver releases it, and both halves are on chain with a reason
// attached.
//
// # Why two calls and not one bank send
//
// [Request] is permissionless and [Approve] is not. Splitting them puts the
// ask, its reason and who made it on chain even when the answer is no, and
// makes every payout name the request it settles. A plain send would leave a
// transfer with no why, and no way to refuse one in public.
//
// They are meant to be sent together. A tm2 transaction carries a LIST of
// messages, runs them in order and stops at the first failure, and a failed
// transaction writes none of their state: only the fee and the sequence
// survive (tm2/pkg/sdk/baseapp.go, runMsgs and WriteCheckpoint). So a request
// and its approval in one transaction either both happen or neither does.
//
// # The id the second message cannot know yet
//
// [Approve] names a request by id, and message 2 of a transaction cannot read
// what message 1 returned. A caller therefore reads [NextID] first and writes
// that number into the approval, which is a race: another Request landing in
// between shifts the id under it, and the approval would pay a stranger.
//
// That is why [Approve] also takes the recipient and the amount it believes it
// is approving, and refuses when the stored request disagrees. The race then
// costs a failed transaction instead of the wrong person's rent.
//
// # What bounds the damage
//
// The faucet spends only what has been sent to its own address, never the
// approver's balance, so the float is the ceiling and topping it up is a
// deliberate act. [MaxPerRequest] caps any single payout under that, and
// [Withdraw] takes the float back.
package faucet

import (
	"strconv"
	"strings"

	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

const (
	// Denom is the only coin this faucet holds or pays.
	Denom = "ugnot"
	// Path is this realm's package path; its float is held at the address
	// derived from it.
	Path = "gno.land/r/moul/faucet/v0"
	// Link is Path as a gnoweb route.
	Link = "/r/moul/faucet/v0"
)

// Owner funds the faucet, approves by default, and is the only account that
// can change who else approves or take the float back.
//
// Hardcoded rather than captured from the deployer: inside a plain
// `func Test(t *testing.T)` the gno test runner reports OriginCaller() as the
// EMPTY address, so an owner seeded from it is empty in every test and
// something else on chain. That divergence is where an authorization bug
// hides, so the address is written down.
const Owner = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")

// The three states a request can be in. A request is decided exactly once.
const (
	StatusPending = "pending"
	StatusSent    = "sent"
	StatusDenied  = "denied"
)

const (
	// DefaultMaxPerRequest is the starting cap on a single payout, 200 GNOT.
	// It is a guard against a fat finger, not against a hostile approver:
	// an approver can raise nothing, but the Owner can.
	DefaultMaxPerRequest = 200_000_000

	// MaxReasonLen bounds the stored reason. It is rendered on a page, so it
	// is both a storage cost and a display one.
	MaxReasonLen = 280

	// idWidth pads the avl key. gno's ufmt supports no width flags, so the
	// padding is done by hand; unpadded numeric keys sort "1","10","2" and
	// the request list would lose its order past nine entries.
	idWidth = 12
)

// request is one ask. It is unexported because avl stores `any` and the
// readable surface of this realm is its views and its page, not a struct
// another realm would have to depend on.
type request struct {
	ID      int64
	To      address
	Amount  int64 // ugnot
	Reason  string
	By      address // who filed it, which is usually not who receives it
	Asked   int64   // chain height at filing
	Status  string
	Judge   address // who decided, zero while pending
	Decided int64   // chain height of the decision
	Note    string  // the denial reason; empty otherwise
}

var (
	requests  avl.Tree // padded id -> *request
	paid      avl.Tree // recipient address -> int64 ugnot received in total
	approvers avl.Tree // approver address -> bool

	nextID        int64
	maxPerRequest int64

	totalSent   int64
	sentCount   int64
	deniedCount int64
	pendingN    int64
)

func init() { reset() }

// reset installs an empty faucet. Also called by the tests: realm globals
// persist for a whole test binary and examples run after every Test, so a
// pinned Render has to start from a known state.
func reset() {
	requests = avl.Tree{}
	paid = avl.Tree{}
	approvers = avl.Tree{}
	approvers.Set(Owner.String(), true)
	nextID = 1
	maxPerRequest = DefaultMaxPerRequest
	totalSent, sentCount, deniedCount, pendingN = 0, 0, 0, 0
}

// Address is where the float sits: this realm's own package address. Fund the
// faucet by sending ugnot to it, with a plain bank send or with [Fund].
func Address() address { return chain.PackageAddress(Path) }

// Balance is what the faucet can actually pay out right now.
func Balance() int64 {
	return banker.NewReadonlyBanker().GetCoins(Address()).AmountOf(Denom)
}

// NextID is the id the next [Request] will be given.
//
// Read it to build the [Approve] half of a two-message transaction, and pass
// the recipient and amount to Approve so that a request landing in between
// fails the transaction instead of being paid by it.
func NextID() int64 { return nextID }

// MaxPerRequest is the current cap on a single payout, in ugnot.
func MaxPerRequest() int64 { return maxPerRequest }

// TotalSent, SentCount, DeniedCount and Pending are the running tallies.
func TotalSent() int64   { return totalSent }
func SentCount() int64   { return sentCount }
func DeniedCount() int64 { return deniedCount }
func Pending() int64     { return pendingN }

// Requests is how many requests have ever been filed.
func Requests() int { return requests.Size() }

// IsApprover reports whether addr may approve or deny.
func IsApprover(addr string) bool { return approvers.Has(addr) }

// ReceivedBy is everything this faucet has ever paid to addr.
func ReceivedBy(addr string) int64 {
	if v := paid.Get(addr); v != nil {
		return v.(int64)
	}
	return 0
}

// Status is the state of request id: "pending", "sent", "denied", or "" when
// no such request exists.
func Status(id int64) string {
	r := find(id)
	if r == nil {
		return ""
	}
	return r.Status
}

// Fund credits the ugnot sent with the call to the float. Coins sent straight
// to [Address] land there too; they just do not emit an event.
func Fund(cur realm) {
	from := unsafe.PreviousRealm().Address()
	amount := unsafe.OriginSend().AmountOf(Denom)
	if amount <= 0 {
		panic("faucet: send some " + Denom + " with the call")
	}
	chain.Emit("Fund", "from", from.String(), "amount", strconv.FormatInt(amount, 10))
}

// Request files an ask for amount ugnot to be paid to `to`, and returns its
// id. Anyone may file, for anyone, which is the point: the account that needs
// the coins is the one that cannot pay to ask for them.
//
// Filing costs the filer gas and nothing else, and moves no money.
func Request(cur realm, to string, amount int64, reason string) int64 {
	by := unsafe.PreviousRealm().Address()
	dst := address(to)
	if !dst.IsValid() {
		panic("faucet: " + to + " is not a valid address")
	}
	if amount <= 0 {
		panic("faucet: amount must be a positive number of " + Denom)
	}
	if amount > maxPerRequest {
		panic("faucet: " + strconv.FormatInt(amount, 10) + Denom +
			" is over the per-request cap of " + strconv.FormatInt(maxPerRequest, 10) + Denom)
	}
	reason = strings.TrimSpace(reason)
	if reason == "" {
		panic("faucet: say what it is for")
	}
	if len(reason) > MaxReasonLen {
		panic("faucet: reason is longer than " + strconv.Itoa(MaxReasonLen) + " bytes")
	}

	id := nextID
	nextID++
	requests.Set(key(id), &request{
		ID:     id,
		To:     dst,
		Amount: amount,
		Reason: reason,
		By:     by,
		Asked:  runtime.ChainHeight(),
		Status: StatusPending,
	})
	pendingN++

	chain.Emit("Request",
		"id", strconv.FormatInt(id, 10),
		"to", dst.String(),
		"amount", strconv.FormatInt(amount, 10),
		"by", by.String(),
	)
	return id
}

// Approve pays request id out of the float. Approvers only.
//
// wantTo and wantAmount are not redundant: they are what makes it safe to put
// Approve in the same transaction as the Request it settles. The id has to be
// guessed from [NextID] before either message is signed, and this call refuses
// when the request sitting at that id is not the one the caller described.
func Approve(cur realm, id int64, wantTo string, wantAmount int64) {
	judge := unsafe.PreviousRealm().Address()
	mustApprove(judge)

	r := find(id)
	if r == nil {
		panic("faucet: no request " + strconv.FormatInt(id, 10))
	}
	if r.Status != StatusPending {
		panic("faucet: request " + strconv.FormatInt(id, 10) + " is already " + r.Status)
	}
	if r.To.String() != wantTo || r.Amount != wantAmount {
		panic("faucet: request " + strconv.FormatInt(id, 10) + " pays " +
			strconv.FormatInt(r.Amount, 10) + Denom + " to " + r.To.String() +
			", not " + strconv.FormatInt(wantAmount, 10) + Denom + " to " + wantTo +
			"; the id moved under you, nothing was paid")
	}
	if bal := Balance(); bal < r.Amount {
		panic("faucet: float is " + strconv.FormatInt(bal, 10) + Denom +
			", request needs " + strconv.FormatInt(r.Amount, 10) + Denom)
	}

	banker.NewBanker(banker.BankerTypeRealmSend, cur).SendCoins(
		cur.Address(), r.To, chain.NewCoins(chain.NewCoin(Denom, r.Amount)))

	r.Status = StatusSent
	r.Judge = judge
	r.Decided = runtime.ChainHeight()
	paid.Set(r.To.String(), ReceivedBy(r.To.String())+r.Amount)
	totalSent += r.Amount
	sentCount++
	pendingN--

	chain.Emit("Approve",
		"id", strconv.FormatInt(id, 10),
		"to", r.To.String(),
		"amount", strconv.FormatInt(r.Amount, 10),
		"by", judge.String(),
	)
}

// Deny closes a request unpaid, with a reason that goes on the page. The
// reason is the whole value of denying in public rather than ignoring it.
func Deny(cur realm, id int64, why string) {
	judge := unsafe.PreviousRealm().Address()
	mustApprove(judge)

	r := find(id)
	if r == nil {
		panic("faucet: no request " + strconv.FormatInt(id, 10))
	}
	if r.Status != StatusPending {
		panic("faucet: request " + strconv.FormatInt(id, 10) + " is already " + r.Status)
	}
	why = strings.TrimSpace(why)
	if why == "" {
		panic("faucet: say why")
	}
	if len(why) > MaxReasonLen {
		panic("faucet: reason is longer than " + strconv.Itoa(MaxReasonLen) + " bytes")
	}

	r.Status = StatusDenied
	r.Judge = judge
	r.Decided = runtime.ChainHeight()
	r.Note = why
	deniedCount++
	pendingN--

	chain.Emit("Deny", "id", strconv.FormatInt(id, 10), "by", judge.String())
}

// AddApprover lets addr approve and deny. Owner only.
func AddApprover(cur realm, addr string) {
	mustOwn(unsafe.PreviousRealm().Address())
	a := address(addr)
	if !a.IsValid() {
		panic("faucet: " + addr + " is not a valid address")
	}
	approvers.Set(a.String(), true)
	chain.Emit("AddApprover", "addr", a.String())
}

// RemoveApprover revokes addr. Owner only, and the Owner cannot be removed:
// a faucet with no approver is a faucet with a locked float.
func RemoveApprover(cur realm, addr string) {
	mustOwn(unsafe.PreviousRealm().Address())
	if addr == Owner.String() {
		panic("faucet: the owner is always an approver")
	}
	// avl's Remove returns (value, removed), unlike Get which returns one
	// value; the comma-ok is required here and forbidden there.
	if _, removed := approvers.Remove(addr); !removed {
		panic("faucet: " + addr + " is not an approver")
	}
	chain.Emit("RemoveApprover", "addr", addr)
}

// SetMaxPerRequest changes the per-request cap, in ugnot. Owner only.
func SetMaxPerRequest(cur realm, amount int64) {
	mustOwn(unsafe.PreviousRealm().Address())
	if amount <= 0 {
		panic("faucet: cap must be positive")
	}
	maxPerRequest = amount
	chain.Emit("SetMaxPerRequest", "amount", strconv.FormatInt(amount, 10))
}

// Withdraw returns amount ugnot of the float to the Owner. Owner only.
//
// This is what makes funding the faucet reversible, and it is deliberately
// not payable to an arbitrary address: an approver who wanted to move money
// somewhere has to file a request for it like everyone else.
func Withdraw(cur realm, amount int64) {
	mustOwn(unsafe.PreviousRealm().Address())
	if amount <= 0 {
		panic("faucet: amount must be positive")
	}
	if bal := Balance(); amount > bal {
		panic("faucet: float is " + strconv.FormatInt(bal, 10) + Denom)
	}
	banker.NewBanker(banker.BankerTypeRealmSend, cur).SendCoins(
		cur.Address(), Owner, chain.NewCoins(chain.NewCoin(Denom, amount)))
	chain.Emit("Withdraw", "amount", strconv.FormatInt(amount, 10))
}

func mustOwn(caller address) {
	if caller != Owner {
		panic("faucet: owner only")
	}
}

func mustApprove(caller address) {
	if !approvers.Has(caller.String()) {
		panic("faucet: " + caller.String() + " is not an approver")
	}
}

func find(id int64) *request {
	v := requests.Get(key(id))
	if v == nil {
		return nil
	}
	return v.(*request)
}

// key pads an id to idWidth digits so the avl tree iterates in filing order.
func key(id int64) string {
	s := strconv.FormatInt(id, 10)
	for len(s) < idWidth {
		s = "0" + s
	}
	return s
}
