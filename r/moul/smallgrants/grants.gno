// Package smallgrants is a small-grant desk, run in the open.
//
// Anyone files a request for a small amount of GNOT, for themselves or for
// someone else. The controllers decide on it in public, and the decision that
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
// # Small, and only small
//
// [MaxGrant] is a constant. No call can raise it, so this realm can never be
// used for a large grant, whoever controls it. Bigger grants are a different
// system with different rules, not a setting of this one.
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
// vote on it (the filer and the payee of a request, the subject of a
// removal), and they still count in the denominator. That is the rule that
// keeps one controller from acting alone on a small set: the seat of someone
// who may not vote is a vote nobody can cast, never a vote that disappears.
//
// Controllers are added and removed by the same majority, with [Propose] and
// [Second], so the set can grow without a redeploy. A set of two cannot remove
// one of its own: add a third first.
//
// # Pause
//
// Paused means one thing: new requests are refused, except from the addresses
// on the allowlist. Everything already filed keeps working, votes keep
// counting and payouts keep going out. The allowlist is its own list, not the
// controller set, though it starts with the same three addresses. Any single
// controller may pause, resume and edit the allowlist: none of that moves
// money or changes who may move it.
package smallgrants

import (
	"strconv"
	"strings"

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

	// MaxGrant is the most one request may ask for: 100 GNOT. Enough for a
	// few package deploys and their gas, not enough to fund a project. It is
	// a constant on purpose; see the package doc.
	MaxGrant = int64(100_000_000)

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
)

type ballot struct {
	Voter  address
	Yes    bool
	Amount int64 // on a request: ugnot this ballot would pay, 0 for a refusal
	Note   string
	Height int64
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
	Status  string
	Decided int64
	Ballots []ballot
}

// motion is a proposal to add or remove one controller.
type motion struct {
	ID      int64
	By      address
	Subject address
	Add     bool
	Reason  string
	Height  int64
	Status  string
	Decided int64
	Ballots []ballot
}

var (
	selfPath string
	selfAddr address

	controllers []address // in the order they were seated
	allowlist   *bptree.BPTree // address -> true; may file while paused
	paused      bool

	requests *bptree.BPTree // seqid -> *request; only ever added to
	open     *bptree.BPTree // seqid -> true, the pending subset
	motions  *bptree.BPTree // seqid -> *motion; only ever added to
	nextReq  seqid.ID
	nextMot  seqid.ID

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
	allowlist = bptree.NewBPTree32()
	for _, c := range controllers {
		allowlist.Set(c.String(), true)
	}
	paused = false
	requests = bptree.NewBPTreeN(128)
	open = bptree.NewBPTree32()
	motions = bptree.NewBPTreeN(128)
	nextReq = 0
	nextMot = 0
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
	title = text(title, "title", MaxTitleLen, true)
	reason = text(reason, "reason", MaxReasonLen, true)

	id := int64(nextReq.Next())
	k := seqid.ID(id).String()
	requests.Set(k, &request{
		ID: id, By: by, To: dst, Amount: amount, Title: title, Reason: reason,
		Height: runtime.ChainHeight(), Status: StatusPending,
	})
	open.Set(k, true)
	chain.Emit("Request", "id", itoa(id), "by", by.String(), "to", dst.String(),
		"amount", strconv.FormatInt(amount, 10))
	return id
}

// Withdraw pulls the caller's own pending request.
func Withdraw(cur realm, id int64) {
	by := caller(cur)
	r := mustPending(id)
	if r.By != by {
		panic("smallgrants: only the filer may withdraw request " + itoa(id))
	}
	closeRequest(r, StatusWithdrawn)
	chain.Emit("Withdraw", "id", itoa(id))
}

// Accept votes to pay request id in full. Controllers only; reason is
// optional and public. The yes that reaches [Quorum] pays in the same
// transaction; if the balance cannot cover it, the call is refused and
// nothing is recorded.
func Accept(cur realm, id int64, reason string) {
	decide(cur, id, mustPending(id).Amount, reason)
}

// AcceptPart votes to pay amount ugnot of request id, at most what it asked.
// Otherwise exactly [Accept]: once the request pays, it pays the smallest
// amount a counted yes named, and it is closed.
func AcceptPart(cur realm, id int64, amount int64, reason string) {
	r := mustPending(id)
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

// Refuse votes not to pay request id. reason is optional and public.
func Refuse(cur realm, id int64, reason string) {
	decide(cur, id, 0, reason)
}

// decide casts a ballot that pays amount, or refuses at 0, and settles the
// request when the ballot decides it.
func decide(cur realm, id, amount int64, reason string) {
	voter := caller(cur)
	r := mustPending(id)
	reason = text(reason, "reason", MaxNoteLen, false)
	ballots := castBallot(r.Ballots, voter, amount > 0, reason, r.By, r.To)
	ballots[len(ballots)-1].Amount = amount
	out := outcome(ballots, r.By, r.To)
	pay := int64(0)
	// Checked before anything is written, so a refused call leaves no trace.
	if out == StatusAdopted {
		pay = agreed(ballots)
		if bal := Balance(); bal < pay {
			panic("smallgrants: balance is " + strconv.FormatInt(bal, 10) + Denom +
				", request " + itoa(id) + " needs " + strconv.FormatInt(pay, 10) + Denom +
				"; fund the realm first, nothing was recorded")
		}
	}
	r.Ballots = ballots

	switch out {
	case StatusAdopted:
		r.Paid = pay
		closeRequest(r, StatusPaid)
		totalPaid += pay
		paidCount++
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

// agreed is what an adopted request pays: the smallest amount named by a
// counted yes, the one amount all of them agreed to.
func agreed(bs []ballot) int64 {
	pay := int64(0)
	for _, b := range bs {
		if b.Yes && isController(b.Voter) && (pay == 0 || b.Amount < pay) {
			pay = b.Amount
		}
	}
	return pay
}

// ---- controllers

// Propose files a motion to add or remove one controller, and returns its id.
// Controllers only. Filing is not a vote: the proposer seconds it like anyone.
func Propose(cur realm, subject string, add bool, reason string) int64 {
	by := caller(cur)
	mustControl(by)
	s := address(subject)
	if !s.IsValid() {
		panic("smallgrants: " + subject + " is not a valid address")
	}
	if add && isController(s) {
		panic("smallgrants: " + subject + " is already a controller")
	}
	if !add {
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
		Height: runtime.ChainHeight(), Status: StatusPending,
	})
	chain.Emit("Propose", "id", itoa(id), "subject", s.String(), "add", strconv.FormatBool(add))
	return id
}

// Second casts a controller's ballot on a motion. The subject of a removal
// may not vote on it and still counts toward the quorum.
func Second(cur realm, id int64, yes bool, note string) {
	voter := caller(cur)
	m := getMotion(id)
	if m == nil {
		panic("smallgrants: no motion " + itoa(id))
	}
	if m.Status != StatusPending {
		panic("smallgrants: motion " + itoa(id) + " is already " + m.Status)
	}
	note = text(note, "note", MaxNoteLen, false)
	// Only a removal has a party who may not vote; an added address is not a
	// controller yet, so it could not vote anyway.
	subject := address("")
	if !m.Add {
		subject = m.Subject
	}
	m.Ballots = castBallot(m.Ballots, voter, yes, note, subject)

	out := outcome(m.Ballots, subject)
	// A removal that would leave fewer than two controllers fails, whatever
	// the count: the set can shrink under a motion filed when it was bigger.
	if !m.Add && out == StatusAdopted && len(controllers) <= 2 {
		out = StatusRejected
	}
	switch out {
	case StatusAdopted:
		if m.Add {
			if !isController(m.Subject) {
				controllers = append(controllers, m.Subject)
			}
		} else {
			controllers = without(controllers, m.Subject)
		}
		m.Status, m.Decided = StatusAdopted, runtime.ChainHeight()
		chain.Emit("Controllers", "subject", m.Subject.String(), "add", strconv.FormatBool(m.Add))
	case StatusRejected:
		m.Status, m.Decided = StatusRejected, runtime.ChainHeight()
	}
	chain.Emit("Second", "id", itoa(id), "voter", voter.String(),
		"yes", strconv.FormatBool(yes), "status", m.Status)
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

// castBallot appends voter's ballot, refusing a non-controller, a second
// ballot, and any party the decision is about.
func castBallot(bs []ballot, voter address, yes bool, note string, parties ...address) []ballot {
	mustControl(voter)
	for _, p := range parties {
		if voter == p {
			panic("smallgrants: " + voter.String() + " is a party to this decision and may not vote on it")
		}
	}
	for _, b := range bs {
		if b.Voter == voter {
			panic("smallgrants: " + voter.String() + " has already voted")
		}
	}
	return append(bs, ballot{Voter: voter, Yes: yes, Note: note, Height: runtime.ChainHeight()})
}

// outcome applies the one rule: adopted once the yes votes of CURRENT
// controllers reach a majority of all current controllers; rejected once the
// controllers who may still vote cannot get it there; pending otherwise.
//
// The quorum is over every seat, parties included. Counting it over eligible
// voters only is the defect this rule exists to prevent: on a set of two, a
// removal's subject drops out, the eligible set is one, its majority is one,
// and either controller could remove the other and then pay alone.
func outcome(bs []ballot, parties ...address) string {
	yes, cast := 0, map[address]bool{}
	for _, b := range bs {
		cast[b.Voter] = true
		if b.Yes && isController(b.Voter) {
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

func closeRequest(r *request, status string) {
	r.Status = status
	r.Decided = runtime.ChainHeight()
	open.Remove(seqid.ID(r.ID).String())
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
