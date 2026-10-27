// Package smallgrants is a small-grant desk, run in the open.
//
// Anyone files a request for a small amount of GNOT, for themselves or for
// someone else. The controllers decide on it in public, and the yes that
// makes a majority pays it, in the same transaction, out of this realm's own
// balance. Every request, decision and payout stays on the page.
//
// # A demo, asking for a home
//
// This deployment is a working preview. The real desk is meant for a shared
// namespace, gno.land/r/nt or gno.land/r/gnoland, and this one exists so that the decision to put it there
// is taken on something that runs. Single role on purpose: who decides grants
// and who administers the deciders is a choice for the real deployment.
//
// # Decisions
//
// A controller decides a request one of three ways, each with an optional
// reason: [Accept] pays it in full, [AcceptPart] pays a part the controller
// names, [Refuse] pays nothing. When the yes side reaches a majority the
// request pays the smallest amount any counted yes named, because that is the
// one amount every one of them agreed to, and it is closed: a part payment
// leaves no remainder open. The payee files a new request for the rest, and
// that one is decided on its own, under the same cap.
//
// Only a yes ever pays or seats anyone. A refusal or a no can close a
// decision, never carry it.
//
// # One set decides each decision
//
// Every decision is taken by the controllers as they are when the deciding
// ballot is cast, and only their ballots cast since the set last changed
// count. Seating or removing a controller voids every ballot on every
// pending request and motion: those decisions restart under the new set,
// which votes again. A removed key loses its say at once, everywhere; a
// ballot cast by one set is never counted against the quorum of another; and
// a seat given back does not bring an old ballot back with it. Voided ballots
// stay on the page, marked as such.
//
// A pending request or motion that can no longer pass, or that has waited
// longer than [Expiry], is closed by anyone with [Close] or [CloseMotion].
//
// # Small, and only small
//
// [MaxGrant] is a constant. No call can raise it. It bounds one request and
// also what one payee address receives over any [Window]: a request is
// refused at filing when what it asks, plus what that payee was paid in the
// window, plus what is already open for it, would pass the cap. That bounds
// what the desk pays one address, not one person: nothing on chain tells two
// addresses of the same person apart, and the page is where a pattern shows.
//
// # Funding
//
// The realm spends only what has been sent to its own address, with a plain
// bank send. It has no other way in and no other way out: coins leave only as
// a grant the controllers voted. To return money, file a request paying it
// back and vote it like any other.
//
// # Controllers
//
// Every decision needs yes votes from a strict majority of ALL current
// controllers: 2 of 3, 3 of 4, 3 of 5. The parties a decision is about never
// vote on it and still count in the denominator. For a removal that is a real
// guarantee: its subject holds a seat nobody else can cast, so a set of two
// cannot remove one of its own and a set of three needs both others. For a
// request it is a conflict-of-interest rule and nothing more: filer and payee
// are addresses the caller chooses, so a controller who files from another
// address for another address of their own is not stopped by it. What holds a
// grant is the majority.
//
// Controllers are added and removed by the same majority, with [Propose] and
// [Second]. An added controller takes the seat only by calling [Join]
// themselves, which proves a key signs for that address: a seat that can
// never vote would raise the quorum past the controllers who can, and the
// motion to undo it would need the quorum it broke. The set holds two to
// [MaxControllers] seats.
//
// # Pause and the open queue
//
// Paused means one thing: new requests are refused, except from the addresses
// on the allowlist. Everything already filed keeps working, votes keep
// counting and payouts keep going out. The allowlist is its own list, not the
// controller set, though it starts with the same three addresses. Any single
// controller may pause, resume and edit the allowlist: none of that moves
// money or changes who may move it.
//
// At most [MaxOpen] requests are pending at once, so the page and the gas to
// read it stay bounded whoever files. A full queue drains as requests are
// decided, withdrawn by their filer or payee, or closed once they lapse.
package smallgrants

import (
	"strconv"
	"strings"
	"time"

	"chain"
	"chain/banker"
	"chain/markdown"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/seqid/v0"
)

const (
	// Denom is the only coin this realm holds or pays.
	Denom = "ugnot"

	// MaxGrant is the most one request may ask for, and the most one payee
	// address may receive over any Window: 100 GNOT. Enough for a few package
	// deploys and their gas, not enough to fund a project. It is a constant
	// on purpose; see the package doc.
	MaxGrant = int64(100_000_000)

	// Window is the span, in seconds of block time, over which MaxGrant
	// bounds what one payee receives: 30 days.
	Window = int64(30 * 24 * 3600)

	// Expiry is how long, in seconds of block time, a request or a motion
	// stays open before anyone may Close it: 30 days.
	Expiry = int64(30 * 24 * 3600)

	// MaxOpen is how many requests may be pending at once.
	MaxOpen = 30

	// MaxControllers bounds the set, so a decision always has a reachable
	// quorum and the page lists it whole.
	MaxControllers = 9

	// MaxTitleLen and MaxReasonLen bound what a caller stores and this page
	// renders. MaxNoteLen bounds a ballot's reason.
	MaxTitleLen  = 80
	MaxReasonLen = 1000
	MaxNoteLen   = 280
)

// The founding controllers, the signers who approve and pay at deploy time.
// Hardcoded rather than taken from the deployer, so the set is the same on
// every chain and in every test, and readable here before anyone signs.
const (
	Moul    = address("g1m7nvpk9trgj5sqhwdu2r0p9v5e2pzemedglvzt")
	Jaekwon = address("g1ecsuj0q572jr0dhu29q9njtnmw03hyu7tyyvv6")
	Aeddi   = address("g1cgnrpdemae7r2qvtkd99x3vk6cvmppsavx8eqs")
)

// The states of a request or a motion. Each is decided exactly once.
const (
	StatusPending   = "pending"
	StatusPaid      = "paid"
	StatusRejected  = "rejected" // a motion
	StatusRefused   = "refused"  // a request
	StatusWithdrawn = "withdrawn"
	StatusAdopted   = "adopted"
	StatusLapsed    = "lapsed" // open past Expiry, then closed
)

type ballot struct {
	Voter  address
	Yes    bool
	Amount int64 // on a request: ugnot this ballot would pay, 0 for a refusal
	Note   string
	Height int64
	Epoch  int64 // the controller set it was cast under
}

// request is one ask for money.
type request struct {
	ID      int64
	By      address // who filed it
	To      address // who gets paid; often not the filer
	Amount  int64   // ugnot asked
	Paid    int64   // ugnot paid; at most Amount, 0 unless paid
	Title   string
	Reason  string
	Height  int64
	Filed   int64 // unix seconds, block time
	Status  string
	Decided int64
	Epoch   int64 // while pending, unused; once closed, the set that closed it
	Ballots []ballot
}

// motion is a proposal to add or remove one controller.
type motion struct {
	ID      int64
	By      address
	Subject address
	Add     bool
	Joined  bool // an addition: the subject has called Join
	Reason  string
	Height  int64
	Filed   int64
	Status  string
	Decided int64
	Epoch   int64
	Ballots []ballot
}

// payout is one grant paid to a payee, kept while it is inside the Window.
type payout struct {
	At     int64
	Amount int64
}

var (
	selfPath string
	selfAddr address

	controllers []address      // in the order they were seated
	epoch       int64          // bumped by every change to controllers
	allowlist   *bptree.BPTree // address -> true; may file while paused
	paused      bool

	requests *bptree.BPTree // seqid -> *request; only ever added to
	open     *bptree.BPTree // seqid -> true, the pending subset, at most MaxOpen
	decided  *bptree.BPTree // seqid of the decision -> request seqid, in closing order
	motions  *bptree.BPTree // seqid -> *motion; only ever added to
	nextReq  seqid.ID
	nextDec  seqid.ID
	nextMot  seqid.ID

	paidTo *bptree.BPTree // payee -> []payout inside the Window
	owedTo *bptree.BPTree // payee -> int64, what its open requests ask

	totalPaid int64
	paidCount int64
)

func init() {
	// init runs as this realm with nobody calling it, so CurrentRealm is this
	// realm here and only here. This is where it learns its own path and
	// address; nothing else in the package writes the path down.
	self := unsafe.CurrentRealm()
	selfPath = self.PkgPath()
	selfAddr = self.Address()
	reset()
}

// reset installs the deploy-time state. Also called by the tests: realm
// globals persist for a whole test binary.
func reset() {
	controllers = []address{Moul, Jaekwon, Aeddi}
	epoch = 0
	allowlist = bptree.NewBPTree32()
	for _, c := range controllers {
		allowlist.Set(c.String(), true)
	}
	paused = false
	requests = bptree.NewBPTreeN(128)
	open = bptree.NewBPTree32()
	decided = bptree.NewBPTreeN(128)
	motions = bptree.NewBPTreeN(128)
	nextReq, nextDec, nextMot = 0, 0, 0
	paidTo = bptree.NewBPTree32()
	owedTo = bptree.NewBPTree32()
	totalPaid, paidCount = 0, 0
}

// ---- reads

// Address is where the money sits: this realm's own package address. Fund the
// realm with a plain bank send to it.
func Address() address { return selfAddr }

// Balance is what the realm can pay right now.
func Balance() int64 {
	return banker.NewReadonlyBanker().GetCoins(selfAddr).AmountOf(Denom)
}

// Controllers lists the current controllers, in the order they were seated.
func Controllers() []address {
	out := make([]address, len(controllers))
	copy(out, controllers)
	return out
}

// IsController reports whether addr is a current controller.
func IsController(addr string) bool { return isController(address(addr)) }

// Quorum is how many yes votes a decision needs right now.
func Quorum() int { return len(controllers)/2 + 1 }

// Paused reports whether new requests are limited to the allowlist.
func Paused() bool { return paused }

// IsAllowed reports whether addr may file while the realm is paused.
func IsAllowed(addr string) bool { return allowlist.Has(addr) }

// TotalPaid and PaidCount are the running totals of what left as grants.
func TotalPaid() int64 { return totalPaid }
func PaidCount() int64 { return paidCount }

// OpenCount is how many requests are pending, at most MaxOpen.
func OpenCount() int { return open.Size() }

// Room is what payee may still ask for right now: MaxGrant, less what it was
// paid inside the Window and what its open requests already ask.
func Room(payee string) int64 {
	a := address(payee)
	return MaxGrant - paidInWindow(a) - owed(a)
}

// Status is the state of request id, or "" when there is none.
func Status(id int64) string {
	if r := getRequest(id); r != nil {
		return r.Status
	}
	return ""
}

// MotionStatus is the state of motion id, or "" when there is none.
func MotionStatus(id int64) string {
	if m := getMotion(id); m != nil {
		return m.Status
	}
	return ""
}

// ---- requests

// Request asks for amount ugnot to be paid to `to`, and returns the request
// id. Anyone may file, for anyone: the account that needs the coins is often
// the one that cannot pay the gas to ask. While the realm is paused, only an
// address on the allowlist may file. Filing moves no money.
func Request(cur realm, to string, amount int64, title, reason string) int64 {
	by := caller(cur)
	if paused && !allowlist.Has(by.String()) {
		panic("smallgrants: paused, new requests are open to the allowlist only")
	}
	if open.Size() >= MaxOpen {
		panic("smallgrants: " + strconv.Itoa(MaxOpen) + " requests are already waiting; file again once one is decided")
	}
	dst := address(to)
	if !dst.IsValid() {
		panic("smallgrants: " + to + " is not a valid address")
	}
	if dst == selfAddr {
		panic("smallgrants: this realm cannot pay itself")
	}
	if amount <= 0 {
		panic("smallgrants: amount must be a positive number of " + Denom)
	}
	if amount > MaxGrant {
		panic("smallgrants: " + strconv.FormatInt(amount, 10) + Denom +
			" is over the cap of " + strconv.FormatInt(MaxGrant, 10) + Denom)
	}
	if room := Room(to); amount > room {
		panic("smallgrants: " + to + " may receive at most " + strconv.FormatInt(MaxGrant, 10) + Denom +
			" per 30 days, counting its open requests; it has " + strconv.FormatInt(room, 10) + Denom + " left")
	}
	title = text(title, "title", MaxTitleLen, true)
	reason = text(reason, "reason", MaxReasonLen, true)

	id := int64(nextReq.Next())
	k := seqid.ID(id).String()
	requests.Set(k, &request{
		ID: id, By: by, To: dst, Amount: amount, Title: title, Reason: reason,
		Height: runtime.ChainHeight(), Filed: now(), Status: StatusPending,
	})
	open.Set(k, true)
	owedTo.Set(dst.String(), owed(dst)+amount)
	chain.Emit("Request", "id", itoa(id), "by", by.String(), "to", dst.String(),
		"amount", strconv.FormatInt(amount, 10))
	return id
}

// Withdraw pulls a pending request. Its filer or its payee may: a payee can
// always clear a request filed in its name that it does not want.
func Withdraw(cur realm, id int64) {
	by := caller(cur)
	r := mustPending(id)
	if r.By != by && r.To != by {
		panic("smallgrants: only the filer or the payee may withdraw request " + itoa(id))
	}
	closeRequest(r, StatusWithdrawn)
	chain.Emit("Withdraw", "id", itoa(id))
}

// Close ends a pending request that can no longer pass, as refused, or one
// open longer than Expiry, as lapsed. Anyone may call it: it pays nothing.
func Close(cur realm, id int64) {
	caller(cur)
	r := mustPending(id)
	switch {
	case expired(r.Filed):
		closeRequest(r, StatusLapsed)
	case outcome(r.Ballots, r.By, r.To) == StatusRejected:
		closeRequest(r, StatusRefused)
	default:
		panic("smallgrants: request " + itoa(id) + " can still pass and has not lapsed")
	}
	chain.Emit("Close", "id", itoa(id), "status", r.Status)
}

// Accept votes to pay request id in full. Controllers only; reason is
// optional and public. The yes that reaches [Quorum] pays in the same
// transaction; if the balance cannot cover it, the call is refused and
// nothing is recorded.
func Accept(cur realm, id int64, reason string) {
	decide(cur, id, mustOpen(id).Amount, reason)
}

// AcceptPart votes to pay amount ugnot of request id, at most what it asked.
// Otherwise exactly [Accept]: once the request pays, it pays the smallest
// amount a counted yes named, and it is closed.
func AcceptPart(cur realm, id int64, amount int64, reason string) {
	r := mustOpen(id)
	if amount <= 0 {
		panic("smallgrants: a part must be a positive amount of " + Denom + "; to pay nothing, Refuse")
	}
	// The request was capped when it was filed, so a part of it is too.
	if amount > r.Amount {
		panic("smallgrants: " + strconv.FormatInt(amount, 10) + Denom + " is more than the " +
			strconv.FormatInt(r.Amount, 10) + Denom + " request " + itoa(id) + " asked for")
	}
	decide(cur, id, amount, reason)
}

// Refuse votes not to pay request id. reason is optional and public. A
// refusal can close a request; it can never pay one.
func Refuse(cur realm, id int64, reason string) {
	decide(cur, id, 0, reason)
}

// decide casts a ballot that pays amount, or refuses at 0, and settles the
// request when the ballot decides it.
func decide(cur realm, id, amount int64, reason string) {
	voter := caller(cur)
	r := mustOpen(id)
	reason = text(reason, "reason", MaxNoteLen, false)
	yes := amount > 0
	ballots := castBallot(r.Ballots, voter, yes, reason, r.By, r.To)
	ballots[len(ballots)-1].Amount = amount
	out := outcome(ballots, r.By, r.To)
	// Within one set, yes votes only ever grow, so only a yes can bring the
	// count to the quorum. Written down anyway: a refusal never pays.
	if out == StatusAdopted && !yes {
		out = StatusPending
	}
	pay := int64(0)
	// Checked before anything is written, so a refused call leaves no trace.
	if out == StatusAdopted {
		pay = agreed(ballots, epoch)
		if bal := Balance(); bal < pay {
			panic("smallgrants: balance is " + strconv.FormatInt(bal, 10) + Denom +
				", request " + itoa(id) + " needs " + strconv.FormatInt(pay, 10) + Denom +
				"; fund the realm first, nothing was recorded")
		}
		// Filing reserved this amount inside the payee's room, and the room
		// only grows as time passes; checked again so the cap never rests on
		// that reasoning alone.
		if paidInWindow(r.To)+pay > MaxGrant {
			panic("smallgrants: " + r.To.String() + " would pass " + strconv.FormatInt(MaxGrant, 10) +
				Denom + " in 30 days; nothing was recorded")
		}
	}
	r.Ballots = ballots

	switch out {
	case StatusAdopted:
		r.Paid = pay
		closeRequest(r, StatusPaid)
		totalPaid += pay
		paidCount++
		recordPayout(r.To, pay)
		banker.NewBanker(banker.BankerTypeRealmSend, cur).
			SendCoins(selfAddr, r.To, chain.NewCoins(chain.NewCoin(Denom, pay)))
		chain.Emit("Paid", "id", itoa(id), "to", r.To.String(),
			"amount", strconv.FormatInt(pay, 10))
	case StatusRejected:
		closeRequest(r, StatusRefused)
	}
	chain.Emit("Decide", "id", itoa(id), "voter", voter.String(),
		"amount", strconv.FormatInt(amount, 10), "status", r.Status)
}

// agreed is what an adopted request pays: the smallest amount named by a yes
// counted under set e, the one amount all of them agreed to.
func agreed(bs []ballot, e int64) int64 {
	pay := int64(0)
	for _, b := range bs {
		if b.Yes && b.Epoch == e && (pay == 0 || b.Amount < pay) {
			pay = b.Amount
		}
	}
	return pay
}

// ---- controllers

// Propose files a motion to add or remove one controller, and returns its id.
// Controllers only. Filing is not a vote: the proposer seconds it like anyone.
// An addition takes effect only once the subject has also called [Join].
func Propose(cur realm, subject string, add bool, reason string) int64 {
	by := caller(cur)
	mustControl(by)
	s := address(subject)
	if !s.IsValid() {
		panic("smallgrants: " + subject + " is not a valid address")
	}
	if add {
		if s == selfAddr {
			panic("smallgrants: this realm cannot sit on its own controller set")
		}
		if isController(s) {
			panic("smallgrants: " + subject + " is already a controller")
		}
		if len(controllers) >= MaxControllers {
			panic("smallgrants: the set is full at " + strconv.Itoa(MaxControllers) + ", remove one first")
		}
	} else {
		if !isController(s) {
			panic("smallgrants: " + subject + " is not a controller")
		}
		if len(controllers) <= 2 {
			panic("smallgrants: a set of two cannot remove one of its own, add a third first")
		}
	}
	reason = text(reason, "reason", MaxReasonLen, true)

	id := int64(nextMot.Next())
	motions.Set(seqid.ID(id).String(), &motion{
		ID: id, By: by, Subject: s, Add: add, Reason: reason,
		Height: runtime.ChainHeight(), Filed: now(), Status: StatusPending,
	})
	chain.Emit("Propose", "id", itoa(id), "subject", s.String(), "add", strconv.FormatBool(add))
	return id
}

// Second casts a controller's ballot on a motion. The subject of a removal
// may not vote on it and still counts toward the quorum. Only a yes ever
// adopts a motion.
func Second(cur realm, id int64, yes bool, note string) {
	voter := caller(cur)
	m := mustOpenMotion(id)
	note = text(note, "note", MaxNoteLen, false)
	m.Ballots = castBallot(m.Ballots, voter, yes, note, m.party())
	out := m.outcome()
	if out == StatusAdopted && !yes {
		out = StatusPending
	}
	settleMotion(m, out)
	chain.Emit("Second", "id", itoa(id), "voter", voter.String(),
		"yes", strconv.FormatBool(yes), "status", m.Status)
}

// Join is how the subject of an addition takes the seat: called by that
// address itself, before or after the controllers' yes votes. It is what
// proves a key signs for the seat.
func Join(cur realm, id int64) {
	who := caller(cur)
	m := mustOpenMotion(id)
	if !m.Add || m.Subject != who {
		panic("smallgrants: only the address motion " + itoa(id) + " would seat may join by it")
	}
	m.Joined = true
	settleMotion(m, m.outcome())
	chain.Emit("Join", "id", itoa(id), "status", m.Status)
}

// CloseMotion ends a pending motion that can no longer pass, as rejected, or
// one open longer than Expiry, as lapsed. Anyone may call it.
func CloseMotion(cur realm, id int64) {
	caller(cur)
	m := mustPendingMotion(id)
	switch {
	case expired(m.Filed):
		closeMotion(m, StatusLapsed)
	case m.outcome() == StatusRejected:
		closeMotion(m, StatusRejected)
	default:
		panic("smallgrants: motion " + itoa(id) + " can still pass and has not lapsed")
	}
	chain.Emit("CloseMotion", "id", itoa(id), "status", m.Status)
}

// party is who may not vote on m: the subject of a removal. An added address
// is not a controller yet, so it could not vote anyway.
func (m *motion) party() address {
	if m.Add {
		return ""
	}
	return m.Subject
}

// outcome is the motion's tally under the current set, with the rules a
// count alone does not see: a removal never leaves fewer than two, a motion
// whose change already happened fails, an addition never passes
// MaxControllers, and an addition the subject has not joined waits for it.
func (m *motion) outcome() string {
	if !m.Add && (len(controllers) <= 2 || !isController(m.Subject)) {
		// The set can shrink under a removal filed when it was bigger, or
		// lose its subject to another motion; adopting either would change
		// nothing and still void every pending ballot.
		return StatusRejected
	}
	if m.Add && (isController(m.Subject) || len(controllers) >= MaxControllers) {
		return StatusRejected
	}
	out := outcome(m.Ballots, m.party())
	if out == StatusAdopted && m.Add && !m.Joined {
		return StatusPending
	}
	return out
}

func settleMotion(m *motion, out string) {
	switch out {
	case StatusAdopted:
		if m.Add {
			controllers = append(controllers, m.Subject)
		} else {
			controllers = without(controllers, m.Subject)
		}
		closeMotion(m, StatusAdopted)
		// A new set: every ballot cast under the old one stops counting.
		epoch++
		chain.Emit("Controllers", "subject", m.Subject.String(), "add", strconv.FormatBool(m.Add),
			"epoch", itoa(epoch))
	case StatusRejected:
		closeMotion(m, StatusRejected)
	}
}

// ---- pause and allowlist

// Pause refuses new requests except from the allowlist. Any one controller.
func Pause(cur realm) {
	mustControl(caller(cur))
	paused = true
	chain.Emit("Pause")
}

// Resume opens new requests to everyone again. Any one controller.
func Resume(cur realm) {
	mustControl(caller(cur))
	paused = false
	chain.Emit("Resume")
}

// Allow lets addr file while the realm is paused. Any one controller.
func Allow(cur realm, addr string) {
	mustControl(caller(cur))
	a := address(addr)
	if !a.IsValid() {
		panic("smallgrants: " + addr + " is not a valid address")
	}
	allowlist.Set(a.String(), true)
	chain.Emit("Allow", "addr", a.String())
}

// Disallow takes addr off the allowlist. Any one controller.
func Disallow(cur realm, addr string) {
	mustControl(caller(cur))
	if _, removed := allowlist.Remove(addr); !removed {
		panic("smallgrants: " + addr + " is not on the allowlist")
	}
	chain.Emit("Disallow", "addr", addr)
}

// ---- rules

// castBallot appends voter's ballot under the current set, refusing a
// non-controller, a second ballot under the same set, and any party the
// decision is about.
func castBallot(bs []ballot, voter address, yes bool, note string, parties ...address) []ballot {
	mustControl(voter)
	for _, p := range parties {
		if voter == p {
			panic("smallgrants: " + voter.String() + " is a party to this decision and may not vote on it")
		}
	}
	for _, b := range bs {
		if b.Voter == voter && b.Epoch == epoch {
			panic("smallgrants: " + voter.String() + " has already voted")
		}
	}
	return append(bs, ballot{Voter: voter, Yes: yes, Note: note, Height: runtime.ChainHeight(), Epoch: epoch})
}

// outcome applies the one rule to the ballots cast under the current set:
// adopted once their yes votes reach a majority of all current controllers;
// rejected once the controllers who may still vote cannot get it there;
// pending otherwise.
//
// The quorum is over every seat, parties included. Counting it over eligible
// voters only is the defect this rule exists to prevent: on a set of two, a
// removal's subject drops out, the eligible set is one, its majority is one,
// and either controller could remove the other and then pay alone.
func outcome(bs []ballot, parties ...address) string {
	yes, cast := 0, map[address]bool{}
	for _, b := range bs {
		if b.Epoch != epoch {
			continue
		}
		cast[b.Voter] = true
		if b.Yes {
			yes++
		}
	}
	left := 0
	for _, c := range controllers {
		if !cast[c] && !isParty(c, parties) {
			left++
		}
	}
	q := Quorum()
	switch {
	case yes >= q:
		return StatusAdopted
	case yes+left < q:
		return StatusRejected
	}
	return StatusPending
}

// ---- payee window

func now() int64 { return time.Now().Unix() }

func expired(filed int64) bool { return now()-filed > Expiry }

func owed(a address) int64 {
	if v := owedTo.Get(a.String()); v != nil {
		return v.(int64)
	}
	return 0
}

// paidInWindow is what a received inside the Window ending now.
func paidInWindow(a address) int64 {
	v := paidTo.Get(a.String())
	if v == nil {
		return 0
	}
	sum, from := int64(0), now()-Window
	for _, p := range v.([]payout) {
		if p.At > from {
			sum += p.Amount
		}
	}
	return sum
}

// recordPayout keeps a's payouts inside the Window and drops the older ones,
// so the list never outgrows what MaxGrant allows in one window.
func recordPayout(a address, amount int64) {
	from := now() - Window
	var kept []payout
	if v := paidTo.Get(a.String()); v != nil {
		for _, p := range v.([]payout) {
			if p.At > from {
				kept = append(kept, p)
			}
		}
	}
	paidTo.Set(a.String(), append(kept, payout{At: now(), Amount: amount}))
}

// ---- helpers

func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("smallgrants: spoofed realm")
	}
	return cur.Previous().Address()
}

func mustControl(a address) {
	if !isController(a) {
		panic("smallgrants: " + a.String() + " is not a controller")
	}
}

func isController(a address) bool {
	for _, c := range controllers {
		if c == a {
			return true
		}
	}
	return false
}

func isParty(a address, parties []address) bool {
	for _, p := range parties {
		if p == a {
			return true
		}
	}
	return false
}

func without(list []address, a address) []address {
	out := make([]address, 0, len(list))
	for _, x := range list {
		if x != a {
			out = append(out, x)
		}
	}
	return out
}

func getRequest(id int64) *request {
	if id <= 0 {
		return nil
	}
	v := requests.Get(seqid.ID(id).String())
	if v == nil {
		return nil
	}
	return v.(*request)
}

func getMotion(id int64) *motion {
	if id <= 0 {
		return nil
	}
	v := motions.Get(seqid.ID(id).String())
	if v == nil {
		return nil
	}
	return v.(*motion)
}

func mustPending(id int64) *request {
	r := getRequest(id)
	if r == nil {
		panic("smallgrants: no request " + itoa(id))
	}
	if r.Status != StatusPending {
		panic("smallgrants: request " + itoa(id) + " is already " + r.Status)
	}
	return r
}

// mustOpen is a pending request that may still be voted on.
func mustOpen(id int64) *request {
	r := mustPending(id)
	if expired(r.Filed) {
		panic("smallgrants: request " + itoa(id) + " has lapsed; anyone may Close it")
	}
	return r
}

func mustPendingMotion(id int64) *motion {
	m := getMotion(id)
	if m == nil {
		panic("smallgrants: no motion " + itoa(id))
	}
	if m.Status != StatusPending {
		panic("smallgrants: motion " + itoa(id) + " is already " + m.Status)
	}
	return m
}

func mustOpenMotion(id int64) *motion {
	m := mustPendingMotion(id)
	if expired(m.Filed) {
		panic("smallgrants: motion " + itoa(id) + " has lapsed; anyone may CloseMotion it")
	}
	return m
}

func closeRequest(r *request, status string) {
	r.Status = status
	r.Decided = runtime.ChainHeight()
	r.Epoch = epoch
	k := seqid.ID(r.ID).String()
	open.Remove(k)
	decided.Set(nextDec.Next().String(), k)
	if left := owed(r.To) - r.Amount; left > 0 {
		owedTo.Set(r.To.String(), left)
	} else {
		owedTo.Remove(r.To.String())
	}
}

func closeMotion(m *motion, status string) {
	m.Status = status
	m.Decided = runtime.ChainHeight()
	m.Epoch = epoch
}

// counted is the set whose ballots decide: the current one while pending,
// the one that closed it after.
func counted(status string, closedAt int64) int64 {
	if status == StatusPending {
		return epoch
	}
	return closedAt
}

// text trims s and enforces its length, and that it says something when
// required. Invisible characters alone do not count as saying something.
func text(s, what string, max int, required bool) string {
	s = strings.TrimSpace(s)
	if required && strings.TrimSpace(markdown.StripBidiAndZeroWidth(s)) == "" {
		panic("smallgrants: the " + what + " is empty")
	}
	if len(s) > max {
		panic("smallgrants: the " + what + " is longer than " + strconv.Itoa(max) + " bytes")
	}
	return s
}

func itoa(n int64) string { return strconv.FormatInt(n, 10) }
