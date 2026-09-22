// Package grant is moul's personal grant board.
//
// It is small on purpose. moul funds it out of his own pocket, moul is the
// only member, and it exists mainly so the coding agents working on his repos
// and the people he already works with have a way to ask for money against
// work they can prove they did: a request, a milestone, a link to the merged
// PR, a tranche. It is open to anyone, not only to agents, and nothing here is
// privileged to a bot.
//
// # What this is NOT
//
// It is not a faucet, and it is not an official gno.land grant program. There
// is no entitlement, no queue and no service level: a request can sit here
// unanswered, or be refused with one line of reasoning and nothing further.
// The official thing, where anyone asks for tokens and a DAO decides, is a
// separate program that does not exist yet, at a path this realm deliberately
// does not name: naming one would read as a commitment nobody has made. This
// realm is moul's own money and a proof of concept for the library under it.
//
// A bigger, multi-member, better funded program is a separate thing and will
// live at its own path. This one stays personal, and its limits are on the
// page rather than in a comment: one member means "a majority of the board" is
// one signature, and the board page says so.
//
// # What is here versus in the library
//
// Almost nothing. Every rule, every tally, every markdown page comes from
// gno.land/p/moul/grants/v0, which is pure and has no idea coins exist. This
// file is the chain-facing half: it turns the caller into an address and the
// block into a height, holds the one Program, moves ugnot through the banker,
// and emits events. That is deliberate, so the next board (multi-member,
// differently funded, maybe a different denom) is another file this short and
// not a fork of this one.
//
// # Who the caller is
//
// Every actor is PreviousRealm().Address(), the immediate caller. Called
// through another realm that is the calling REALM, not the user behind it.
// An agent holding a gno.land account session scoped to this path applies and
// submits proofs as its own address, which is exactly what makes an agent's
// track record on this board its own and not moul's.
package grant

import (
	"strconv"

	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/moul/grants/v0"
)

const (
	// Denom is the only coin this board holds or pays.
	Denom = "ugnot"
	// Path is this realm's package path; its treasury is derived from it.
	Path = "gno.land/r/moul/grant/v0"
	// Link is Path as a gnoweb route.
	Link = "/r/moul/grant/v0"
)

// Owner is the founding and, for now, only member.
//
// Hardcoded rather than taken from the deployer: inside a plain
// `func Test(t *testing.T)` the gno test runner reports OriginCaller() as the
// EMPTY address, so a board seeded from it is empty in every test and
// something else on chain. That divergence is exactly where an authorization
// bug hides, so the address is written down.
const Owner = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")

var program *grants.Program

func init() { reset() }

// reset installs a fresh, empty board. Also called by the tests: realm globals
// persist for a whole test binary and examples run after every Test, so a
// pinned Render has to start from a known state.
func reset() { program = grants.NewProgram(Denom, Owner) }

// Address is the treasury: this realm's own package address. Fund it by
// sending ugnot to it, or by calling Fund with `-send`.
func Address() address { return chain.PackageAddress(Path) }

// Balance is what the treasury actually holds.
func Balance() int64 {
	return banker.NewReadonlyBanker().GetCoins(Address()).AmountOf(Denom)
}

// Committed is what approved grants can still claim, Available is the balance
// minus that, and it can go negative. See the library for why.
func Committed() int64 { return program.Committed() }
func Available() int64 { return program.Available(Balance()) }

// Raised is everything donated through Fund, Disbursed everything paid out.
func Raised() int64    { return program.Raised() }
func Disbursed() int64 { return program.Disbursed() }

// Members lists the board.
func Members() []address { return program.Board.Members() }

// Requests is how many requests have ever been filed.
func Requests() int { return program.Board.Size() }

// Fund credits the ugnot sent with the call to the treasury and puts the donor
// on the record. Coins sent to the realm address directly still land in the
// treasury; they just do not get a name next to them.
func Fund(cur realm) {
	from := unsafe.PreviousRealm().Address()
	amount := unsafe.OriginSend().AmountOf(Denom)
	if err := program.Fund(from, amount, runtime.ChainHeight()); err != nil {
		panic(err)
	}
	chain.Emit("Fund", "from", from.String(), "amount", strconv.FormatInt(amount, 10))
}

// Apply files a grant request for the caller. milestones reads
// "title:amount,title:amount", amounts in ugnot, paid in the order given.
// Returns the request id.
func Apply(cur realm, title, body, milestones string) int {
	applicant := unsafe.PreviousRealm().Address()
	return file(applicant, applicant, "", title, body, milestones)
}

// ApplyFor files a grant request whose tranches pay beneficiary rather than
// the caller, with a reason for the detour that goes on the request page.
//
// This is the call that makes the board usable at all for the case it exists
// to serve. An account with nothing in it cannot pay the gas to ask for its
// first coins, so without someone else filing on its behalf the people who
// most need a small grant are exactly the people who cannot ask for one.
// Either address may then submit the proofs, and neither may vote.
func ApplyFor(cur realm, beneficiary, reason, title, body, milestones string) int {
	applicant := unsafe.PreviousRealm().Address()
	return file(applicant, address(beneficiary), reason, title, body, milestones)
}

func file(applicant, beneficiary address, reason, title, body, milestones string) int {
	r, err := program.ApplyFor(applicant, beneficiary, reason, title, body, milestones,
		runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("Apply", "id", strconv.Itoa(r.ID), "applicant", applicant.String(),
		"beneficiary", r.Payee().String(), "total", strconv.FormatInt(r.Total(), 10))
	return r.ID
}

// ProposeMember asks the board to add or remove a member. Members only.
func ProposeMember(cur realm, addr string, add bool, body string) int {
	proposer := unsafe.PreviousRealm().Address()
	r, err := program.Board.SubmitMemberChange(proposer, address(addr), add, body, runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("ProposeMember", "id", strconv.Itoa(r.ID), "subject", addr,
		"add", strconv.FormatBool(add))
	return r.ID
}

// Retract pulls the caller's own request before it is decided.
func Retract(cur realm, id int) {
	caller := unsafe.PreviousRealm().Address()
	if err := program.Board.Withdraw(caller, id, runtime.ChainHeight()); err != nil {
		panic(err)
	}
	chain.Emit("Retract", "id", strconv.Itoa(id))
}

// Vote records a member's ballot. The reason is stored and rendered next to
// the vote: it is the only part of a decision that tells an applicant what to
// do about it.
func Vote(cur realm, id int, approve bool, reason string) {
	voter := unsafe.PreviousRealm().Address()
	st, err := program.Board.Vote(voter, id, approve, reason, runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("Vote", "id", strconv.Itoa(id), "voter", voter.String(),
		"approve", strconv.FormatBool(approve), "status", st.String())
}

// SubmitProof offers evidence for the next milestone of an approved grant.
// kind is "url", "hash" or "text"; ref is the link, digest or statement.
func SubmitProof(cur realm, id, milestone int, kind, ref, note string) {
	caller := unsafe.PreviousRealm().Address()
	p := grants.Proof{Kind: kind, Ref: ref, Note: note, Height: runtime.ChainHeight()}
	if err := program.Board.SubmitProof(caller, id, milestone, p); err != nil {
		panic(err)
	}
	chain.Emit("SubmitProof", "id", strconv.Itoa(id),
		"milestone", strconv.Itoa(milestone), "kind", kind)
}

// Review records a member's verdict on the proof under review. The verdict
// that carries also pays the tranche, in this same transaction. A verdict the
// treasury cannot cover is refused outright and changes nothing.
func Review(cur realm, id, milestone int, accept bool, reason string) {
	voter := unsafe.PreviousRealm().Address()
	out, pay, err := program.Review(voter, id, milestone, accept, reason, runtime.ChainHeight(), Balance())
	if err != nil {
		panic(err)
	}
	chain.Emit("Review", "id", strconv.Itoa(id), "milestone", strconv.Itoa(milestone),
		"voter", voter.String(), "accept", strconv.FormatBool(accept), "outcome", out.String())
	if pay == nil {
		return
	}
	banker.NewBanker(banker.BankerTypeRealmSend, cur).
		SendCoins(Address(), pay.To, chain.NewCoins(chain.NewCoin(Denom, pay.Amount)))
	chain.Emit("Release", "id", strconv.Itoa(id), "milestone", strconv.Itoa(milestone),
		"to", pay.To.String(), "amount", strconv.FormatInt(pay.Amount, 10))
}
