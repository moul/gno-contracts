package crews

import (
	"strconv"
	"strings"
	"testing"

	"chain"
	"chain/banker"

	"gno.land/p/moul/x/social/crew/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var realmAddr = chain.PackageAddress(realmPath)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

// tenGNOT is what every founder here puts in: 10,000 shares at the opening
// price, so halving and doubling stay exact and the rounding tests can use
// deliberately awkward numbers instead.
const tenGNOT = int64(10000000)

// reset clears realm state. Realm globals live for the whole test binary, so
// everything a later test reads starts here.
func reset() {
	crews = crew.New()
}

// create calls Create the way a real transaction would: the runtime credits
// the realm's address, then the envelope reports the send to the crossing
// function. The account switch and the cross are in the same frame on purpose,
// since testing.SetRealm governs nothing else.
func create(cur realm, who address, amount int64, name string) int64 {
	testing.IssueCoins(realmAddr, chain.Coins{{denom, amount}})
	testing.SetOriginSend(chain.Coins{{denom, amount}})
	testing.SetRealm(testing.NewUserRealm(who))
	return Create(cross(cur), name)
}

// join is [create] for Join.
func join(cur realm, who address, amount, crewID int64) int64 {
	testing.IssueCoins(realmAddr, chain.Coins{{denom, amount}})
	testing.SetOriginSend(chain.Coins{{denom, amount}})
	testing.SetRealm(testing.NewUserRealm(who))
	return Join(cross(cur), crewID)
}

// fund is [create] for Fund.
func fund(cur realm, who address, amount, crewID int64) int64 {
	testing.IssueCoins(realmAddr, chain.Coins{{denom, amount}})
	testing.SetOriginSend(chain.Coins{{denom, amount}})
	testing.SetRealm(testing.NewUserRealm(who))
	return Fund(cross(cur), crewID)
}

func TestCreateMakesTheFounderTheOnlyMember(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, tenGNOT, "validators")

	name, at, members, shares, treasury := Get(id)
	uassert.Equal(t, "validators", name)
	uassert.Equal(t, int64(123), at, "tests start at height 123")
	uassert.Equal(t, 1, members)
	uassert.Equal(t, tenGNOT/crew.InitialPricePerShare, shares)
	uassert.Equal(t, tenGNOT, treasury)

	uassert.Equal(t, shares, SharesOf(id, alice))
	uassert.Equal(t, int64(0), SharesOf(id, bob))
	uassert.Equal(t, crew.InitialPricePerShare, ValuePerShare(id))
	uassert.Equal(t, 1, Count())
	uassert.Equal(t, tenGNOT, Treasury(id))
}

// A second joiner at the same per-share value gets the same shares, which is
// the baseline the anti-dilution rule is measured against.
func TestASecondJoinerAtTheSamePriceGetsTheSameShares(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, tenGNOT, "crew")
	got := join(cur, bob, tenGNOT, id)

	uassert.Equal(t, SharesOf(id, alice), got, "same money, same shares")
	uassert.Equal(t, crew.InitialPricePerShare, ValuePerShare(id), "the price did not move")
	uassert.Equal(t, 2, MemberCount(id))
	uassert.Equal(t, 2*tenGNOT, Treasury(id))
}

// A joiner arriving after the treasury grew gets FEWER shares for the same
// money: they buy at what a share is worth now, not at what the founders paid.
func TestAJoinerAfterTheTreasuryGrewGetsFewer(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, tenGNOT, "crew")
	fund(cur, carol, tenGNOT, id) // the crew doubled its money
	urequire.Equal(t, 2*crew.InitialPricePerShare, ValuePerShare(id))

	got := join(cur, bob, tenGNOT, id)
	uassert.Equal(t, SharesOf(id, alice)/2, got, "the same money buys half as much")
	uassert.Equal(t, 2*crew.InitialPricePerShare, ValuePerShare(id),
		"and joining moved the value for nobody")
	uassert.Equal(t, int64(0), SharesOf(id, carol), "funding mints nothing")
}

// Ragequit credits, Withdraw pays, and the coins actually move.
func TestRagequitCreditsAndWithdrawPays(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, tenGNOT, "crew")
	join(cur, bob, tenGNOT, id)
	fund(cur, carol, 2*tenGNOT, id) // treasury 4x, still 2x the shares

	testing.SetRealm(testing.NewUserRealm(bob))
	owed := Ragequit(cross(cur), id)
	uassert.Equal(t, 2*tenGNOT, owed, "half the shares of a treasury worth four")
	uassert.Equal(t, owed, CreditOf(bob), "credited, never sent")
	uassert.Equal(t, owed, TotalOwed())
	uassert.Equal(t, 1, MemberCount(id))
	uassert.Equal(t, int64(0), SharesOf(id, bob))
	uassert.Equal(t, 2*tenGNOT, Treasury(id))

	before := banker.NewReadonlyBanker().GetCoins(bob).AmountOf(denom)

	testing.SetRealm(testing.NewUserRealm(bob))
	got := Withdraw(cross(cur))
	uassert.Equal(t, owed, got)
	uassert.Equal(t, int64(0), CreditOf(bob), "zeroed before the coins moved")
	uassert.Equal(t, int64(0), TotalOwed())

	after := banker.NewReadonlyBanker().GetCoins(bob).AmountOf(denom)
	uassert.Equal(t, before+owed, after, "the coins actually arrived")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "nothing to withdraw", func() { Withdraw(cross(cur)) })
}

// Everyone ragequitting empties the treasury to the last ugnot, even when no
// single division is exact: the dust a leaver rounds away belongs to whoever is
// still in, and the last one out holds every share.
func TestEveryoneRagequittingEmptiesTheTreasury(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, 1000, "crew")
	join(cur, bob, 1000, id)
	join(cur, carol, 1000, id)
	fund(cur, alice, 2, id) // 3002 ugnot over 3 shares, divides by nothing

	urequire.Equal(t, int64(3002), Treasury(id))

	var paid int64
	testing.SetRealm(testing.NewUserRealm(alice))
	paid += Ragequit(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(bob))
	paid += Ragequit(cross(cur), id)
	testing.SetRealm(testing.NewUserRealm(carol))
	paid += Ragequit(cross(cur), id)

	uassert.Equal(t, int64(3002), paid, "every ugnot left with somebody")
	uassert.Equal(t, int64(0), Treasury(id), "to the last one")
	uassert.Equal(t, 0, MemberCount(id))
	uassert.Equal(t, int64(3002), TotalOwed())
	uassert.Equal(t, int64(1000), CreditOf(alice), "first out, rounded down hardest")
	uassert.Equal(t, int64(1001), CreditOf(carol), "last out takes the dust")
}

// A one-member crew ragequitting takes everything, including the ugnot that
// bought no whole share: their shares ARE the total, so the division is exact.
func TestAOneMemberCrewTakesEverything(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, 5001, "solo")

	testing.SetRealm(testing.NewUserRealm(alice))
	got := Ragequit(cross(cur), id)
	uassert.Equal(t, int64(5001), got)
	uassert.Equal(t, int64(0), Treasury(id))
	uassert.Equal(t, 0, MemberCount(id))

	// An emptied crew is not a dead one: with nothing outstanding there is
	// no value to price against, so it reopens at the opening price.
	uassert.Equal(t, int64(0), ValuePerShare(id))
	got = join(cur, bob, tenGNOT, id)
	uassert.Equal(t, tenGNOT/crew.InitialPricePerShare, got)
}

func TestProposalsAreAdvisoryAndShareWeighted(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, tenGNOT, "crew") // alice: 10000 shares
	join(cur, bob, tenGNOT/2, id)             // bob:    5000 shares

	testing.SetRealm(testing.NewUserRealm(bob))
	pid := Propose(cross(cur), id, "ship v1 before the conference")

	_, author, text, deadline, closed, passed := ProposalOf(pid)
	uassert.Equal(t, bob.String(), author.String())
	uassert.Equal(t, "ship v1 before the conference", text)
	uassert.Equal(t, int64(123+crew.VoteBlocks), deadline)
	uassert.False(t, closed)
	uassert.False(t, passed)

	testing.SetRealm(testing.NewUserRealm(bob))
	Vote(cross(cur), pid, true)
	testing.SetRealm(testing.NewUserRealm(alice))
	Vote(cross(cur), pid, false)

	yes, no := Tally(pid)
	uassert.Equal(t, int64(5000), yes)
	uassert.Equal(t, int64(10000), no, "a bigger holder outvotes a smaller one")

	// Changing your mind while it is open replaces the ballot.
	testing.SetRealm(testing.NewUserRealm(alice))
	Vote(cross(cur), pid, true)
	yes, no = Tally(pid)
	uassert.Equal(t, int64(15000), yes)
	uassert.Equal(t, int64(0), no, "the old ballot is removed, not added to")

	testing.SkipHeights(crew.VoteBlocks)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.True(t, Close(cross(cur), pid), "anyone may close it")

	_, _, _, _, closed, passed = ProposalOf(pid)
	uassert.True(t, closed)
	uassert.True(t, passed)

	// Passing it moved nothing. That is the whole v0 claim.
	uassert.Equal(t, tenGNOT+tenGNOT/2, Treasury(id))
	uassert.Equal(t, int64(0), TotalOwed())
}

func TestRefusals(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, tenGNOT, "crew")

	testing.IssueCoins(realmAddr, chain.Coins{{denom, tenGNOT}})
	testing.SetOriginSend(chain.Coins{{denom, tenGNOT}})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "already a member", func() { Join(cross(cur), id) })

	testing.IssueCoins(realmAddr, chain.Coins{{denom, tenGNOT}})
	testing.SetOriginSend(chain.Coins{{denom, tenGNOT}})
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "no such crew", func() { Join(cross(cur), 4242) })

	// Create with nothing attached is refused by the envelope, which names
	// the flag the caller has to fix.
	testing.SetOriginSend(chain.Coins{})
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "send", func() { Create(cross(cur), "broke") })

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not a member", func() {
		Propose(cross(cur), id, "let me in")
	})
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not a member", func() { Ragequit(cross(cur), id) })

	testing.SetRealm(testing.NewUserRealm(alice))
	pid := Propose(cross(cur), id, "a question")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not a member", func() { Vote(cross(cur), pid, true) })
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "still open", func() { Close(cross(cur), pid) })

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "name is empty", func() {
		create(cur, alice, tenGNOT, "  ")
	})
	// A pipe in a name would open a column where the name is a link title
	// in a table cell, which md.Link's escaper does not cover.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "name is empty", func() {
		create(cur, alice, tenGNOT, "a | pipe")
	})

	uassert.Equal(t, 1, Count(), "no refusal created anything")
	uassert.Equal(t, 1, MemberCount(id))
}

// TestRender uses uassert rather than an Example because every view contains
// consecutive blank lines, which gno collapses inside an // Output: block.
func TestRender(cur realm, t *testing.T) {
	reset()
	id := create(cur, alice, tenGNOT, "a crew [with](markdown)")
	join(cur, bob, tenGNOT, id)

	testing.SetRealm(testing.NewUserRealm(alice))
	pid := Propose(cross(cur), id, "ship v1 | before the conference")
	testing.SetRealm(testing.NewUserRealm(alice))
	Vote(cross(cur), pid, true)

	index := Render("")
	uassert.True(t, strings.Contains(index, "# Crews"), index)
	uassert.True(t, strings.Contains(index, "| 1 | 1 | 0 GNOT |"), "crews, proposals, owed")
	uassert.True(t, strings.Contains(index, "func=Create"), index)
	uassert.True(t, strings.Contains(index, "One realm address holds every crew's treasury"),
		"the index states the custody caveat")
	uassert.True(t, strings.Contains(index,
		"[a crew \\[with\\]\\(markdown\\)](/r/moul/x/social/crews/v0:crew/1)"),
		"md.Link escapes the title exactly once: "+index)

	sid := strconv.FormatInt(id, 10)
	page := Render("crew/" + sid)
	uassert.True(t, strings.Contains(page, "# a crew \\[with\\]\\(markdown\\)"),
		"the name is escaped where it is shown as prose: "+page)
	uassert.True(t, strings.Contains(page, "| 2 of 15 | 20000 | 20 GNOT | 0.001 GNOT |"), page)
	uassert.True(t, strings.Contains(page, "| 10000 | 50% | 10 GNOT |"),
		"each member holds half the shares and half the money")
	uassert.True(t, strings.Contains(page, "func=Ragequit"), page)
	uassert.True(t, strings.Contains(page, "executes nothing"), page)

	// A pipe in a proposal's text must not open a column in the crew's
	// proposal table. It goes through ui.Cell for exactly this.
	uassert.True(t, strings.Contains(page, "ship v1 \\| before the conference"),
		"the cell is escaped: "+page)
	uassert.False(t, strings.Contains(page, "| ship v1 | before"),
		"a raw pipe would open a column: "+page)

	spid := strconv.FormatInt(pid, 10)
	prop := Render("proposal/" + spid)
	uassert.True(t, strings.Contains(prop, "# Proposal #"+spid), prop)
	uassert.True(t, strings.Contains(prop, "> ship v1 | before the conference"),
		"a blockquote is prose, where a pipe is inert and must not grow a backslash")
	uassert.True(t, strings.Contains(prop, "| open until 1123 | 10000 | 0 | 1 |"), prop)
	uassert.True(t, strings.Contains(prop, "func=Vote"), prop)

	// Past the deadline the page offers the close instead of the vote.
	testing.SkipHeights(crew.VoteBlocks)
	prop = Render("proposal/" + spid)
	uassert.True(t, strings.Contains(prop, "awaiting a close"), prop)
	uassert.True(t, strings.Contains(prop, "func=Close"), prop)
	uassert.False(t, strings.Contains(prop, "func=Vote"), prop)

	uassert.Equal(t, "# Crews\nNo crew #4242", Render("crew/4242"))
	uassert.Equal(t, "# Crews\nNot a crew id: nope", Render("crew/nope"))
	uassert.Equal(t, "# Crews\nNo proposal #4242", Render("proposal/4242"))
	uassert.Equal(t, "# Crews\nNot a proposal id: nope", Render("proposal/nope"))
	uassert.True(t, strings.HasPrefix(Render("elsewhere"), "# Not found"))
}

// An empty realm still renders something a reader can act on.
func TestRenderWithNothingInIt(cur realm, t *testing.T) {
	reset()
	index := Render("")
	uassert.True(t, strings.Contains(index, "No crews yet."), index)
	uassert.True(t, strings.Contains(index, "func=Create"), index)
}

// Links are rooted at the realm's own path, so they resolve from any page
// gnoweb serves them on.
func TestLinksAreRootRelative(t *testing.T) {
	uassert.Equal(t, "/r/moul/x/social/crews/v0", realmURL())
	uassert.Equal(t, "/r/moul/x/social/crews/v0:crew/7", crewURL(7))
	uassert.Equal(t, "/r/moul/x/social/crews/v0:proposal/7", proposalURL(7))
}
