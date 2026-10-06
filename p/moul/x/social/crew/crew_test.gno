package crew

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
)

// join is Join with the minted share count dropped, for the cases that only
// care that it worked.
func join(t *testing.T, cs *Crews, id store.ID, who address, amount int64) {
	t.Helper()
	_, err := cs.Join(id, who, amount)
	urequire.NoError(t, err)
}

// tenGNOT is the amount every founder in these tests puts in, chosen so the
// share count is a round 10,000 and a halved or doubled price is still exact.
const tenGNOT = int64(10000000)

func TestValidName(t *testing.T) {
	tests := []struct {
		name string
		want bool
	}{
		{"validators", true},
		{"The Hackathon Team", true},
		{"a", true},
		{strings.Repeat("x", MaxNameLen), true},
		{"", false},
		{"   ", false},
		{strings.Repeat("x", MaxNameLen+1), false},
		{"two\nlines", false},
		{"a\tb", false},
		{"a\x7fb", false},
		{"a | pipe", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidName(tt.name), tt.name)
	}
}

func TestValidText(t *testing.T) {
	tests := []struct {
		name string
		text string
		want bool
	}{
		{"plain", "ship v1 before the conference", true},
		{"newlines and tabs are content", "a\nb\tc", true},
		{"markdown is allowed and escaped later", "[x](y) | z", true},
		{"empty", "", false},
		{"blank", "  \n ", false},
		{"too long", strings.Repeat("x", MaxTextLen+1), false},
		{"control character", "a\x01b", false},
		{"delete character", "a\x7fb", false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, ValidText(tt.text), tt.name)
	}
}

func TestCreateMintsAtTheOpeningPrice(t *testing.T) {
	cs := New()
	id, err := cs.Create("validators", alice, tenGNOT, 100)
	urequire.NoError(t, err)

	c, ok := cs.Get(id)
	urequire.True(t, ok, "the crew exists")
	uassert.Equal(t, "validators", c.Name)
	uassert.Equal(t, int64(100), c.CreatedAt)
	uassert.Equal(t, tenGNOT/InitialPricePerShare, c.TotalShares)
	uassert.Equal(t, tenGNOT, c.Treasury)
	uassert.Equal(t, c.TotalShares, c.SharesOf(alice))
	uassert.Equal(t, 1, c.MemberCount())
	uassert.Equal(t, InitialPricePerShare, c.ValuePerShare())
	uassert.Equal(t, 1, cs.Len())
}

// The remainder below one whole share stays in the treasury, which is the same
// direction every other division here rounds.
func TestCreateKeepsTheRemainder(t *testing.T) {
	cs := New()
	id, err := cs.Create("crew", alice, 2999, 100)
	urequire.NoError(t, err)

	c, _ := cs.Get(id)
	uassert.Equal(t, int64(2), c.TotalShares, "2999 ugnot buys two whole shares")
	uassert.Equal(t, int64(2999), c.Treasury, "and the 999 left over is the crew's")
}

func TestCreateRefusals(t *testing.T) {
	tests := []struct {
		label  string
		name   string
		amount int64
		want   error
	}{
		{"empty name", "", tenGNOT, ErrBadName},
		{"name with a newline", "two\nlines", tenGNOT, ErrBadName},
		{"name with a pipe", "a | pipe", tenGNOT, ErrBadName},
		{"nothing sent", "crew", 0, ErrBadAmount},
		{"negative", "crew", -1, ErrBadAmount},
		{"under one share", "crew", InitialPricePerShare - 1, ErrNoShares},
	}
	for _, tt := range tests {
		cs := New()
		_, err := cs.Create(tt.name, alice, tt.amount, 100)
		uassert.ErrorIs(t, err, tt.want, tt.label)
		uassert.Equal(t, 0, cs.Len(), tt.label+": nothing was stored")
	}
}

// A second joiner at the same per-share value gets the same shares. This is the
// baseline the anti-dilution rule is measured against.
func TestASecondJoinerAtTheSamePriceGetsTheSameShares(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)

	got, err := cs.Join(id, bob, tenGNOT)
	urequire.NoError(t, err)

	c, _ := cs.Get(id)
	uassert.Equal(t, c.SharesOf(alice), got, "same money, same shares")
	uassert.Equal(t, tenGNOT/InitialPricePerShare, got)
	uassert.Equal(t, 2*tenGNOT, c.Treasury)
	uassert.Equal(t, 2*(tenGNOT/InitialPricePerShare), c.TotalShares)
	uassert.Equal(t, InitialPricePerShare, c.ValuePerShare(), "the value per share did not move")
	uassert.Equal(t, 2, c.MemberCount())
}

// A joiner arriving after the treasury grew gets FEWER shares for the same
// money, because they are buying at what a share is worth now. That is the
// whole point: a late joiner cannot buy into value the existing members built.
func TestAJoinerAfterTheTreasuryGrewGetsFewer(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	urequire.NoError(t, cs.Fund(id, tenGNOT)) // the crew doubled its money

	c, _ := cs.Get(id)
	urequire.Equal(t, 2*InitialPricePerShare, c.ValuePerShare())

	got, err := cs.Join(id, bob, tenGNOT)
	urequire.NoError(t, err)
	uassert.Equal(t, c.SharesOf(alice)/2, got, "the same money buys half as much")
	uassert.Equal(t, 2*InitialPricePerShare, c.ValuePerShare(),
		"and joining did not move the value for anybody else")
}

// Rounding down on the way in means a joiner never gets a share they did not
// fully pay for, and the fractional remainder accrues to the crew.
func TestJoinRoundsInTheCrewsFavour(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, 1000, 100) // 1 share, treasury 1000
	urequire.NoError(t, cs.Fund(id, 500))        // treasury 1500, still 1 share

	// 1499 ugnot is 0.999 of a share. Rounding up would hand bob a whole
	// one and half of alice's money with it.
	_, err := cs.Join(id, bob, 1499)
	uassert.ErrorIs(t, err, ErrNoShares)

	got, err := cs.Join(id, bob, 2999)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1), got, "1.999 shares' worth buys one share")

	c, _ := cs.Get(id)
	uassert.Equal(t, int64(4499), c.Treasury, "the 1499 ugnot of remainder stayed")
	uassert.Equal(t, int64(2), c.TotalShares)
}

func TestJoinRefusals(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)

	_, err := cs.Join(999, bob, tenGNOT)
	uassert.ErrorIs(t, err, ErrNoCrew)

	_, err = cs.Join(id, alice, tenGNOT)
	uassert.ErrorIs(t, err, ErrIsMember, "a member cannot buy in twice")

	_, err = cs.Join(id, bob, 0)
	uassert.ErrorIs(t, err, ErrBadAmount)

	c, _ := cs.Get(id)
	uassert.Equal(t, 1, c.MemberCount(), "no refusal changed the roster")
	uassert.Equal(t, tenGNOT, c.Treasury)
}

// Fifteen people is the product constraint, and the sixteenth is refused rather
// than quietly allowed.
func TestACrewIsFullAtMaxMembers(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	for i := 1; i < MaxMembers; i++ {
		who := testutils.TestAddress("m" + strconv.Itoa(i))
		_, err := cs.Join(id, who, tenGNOT)
		urequire.NoError(t, err)
	}

	c, _ := cs.Get(id)
	urequire.Equal(t, MaxMembers, c.MemberCount())

	_, err := cs.Join(id, testutils.TestAddress("one too many"), tenGNOT)
	uassert.ErrorIs(t, err, ErrFull)
	uassert.Equal(t, MaxMembers, c.MemberCount())
}

func TestProposeAndTallyByShareWeight(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100) // alice: 10000 shares
	cs.Join(id, bob, tenGNOT/2)                     // bob: 5000 shares

	pid, err := cs.Propose(id, bob, "ship v1 before the conference", 200)
	urequire.NoError(t, err)

	p, ok := cs.Proposal(pid)
	urequire.True(t, ok, "the proposal exists")
	uassert.Equal(t, uint64(id), uint64(p.CrewID))
	uassert.Equal(t, int64(200+VoteBlocks), p.Deadline)
	uassert.True(t, p.Open(200))
	uassert.False(t, p.Open(200+VoteBlocks), "the deadline is exclusive")

	urequire.NoError(t, cs.Vote(pid, bob, true, 210))
	urequire.NoError(t, cs.Vote(pid, alice, false, 211))
	uassert.Equal(t, int64(5000), p.Yes)
	uassert.Equal(t, int64(10000), p.No, "a bigger holder outvotes a smaller one")
	uassert.Equal(t, 2, p.Voters())

	c, _ := cs.Get(id)
	uassert.Equal(t, 1, len(c.Proposals()))
}

// One ballot per member, replaced in place while the proposal is open, and
// reweighed from the shares held at the moment it is recast.
func TestAVoteIsChangeableWhileOpen(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	pid, _ := cs.Propose(id, alice, "a question", 200)
	p, _ := cs.Proposal(pid)

	urequire.NoError(t, cs.Vote(pid, alice, true, 210))
	uassert.Equal(t, int64(10000), p.Yes)
	uassert.Equal(t, int64(0), p.No)

	urequire.NoError(t, cs.Vote(pid, alice, false, 211))
	uassert.Equal(t, int64(0), p.Yes, "the old ballot is removed, not added to")
	uassert.Equal(t, int64(10000), p.No)
	uassert.Equal(t, 1, p.Voters(), "still one voter")

	yes, weight, voted := p.VoteOf(alice)
	uassert.True(t, voted)
	uassert.False(t, yes)
	uassert.Equal(t, int64(10000), weight)
}

func TestProposeAndVoteRefusals(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)

	_, err := cs.Propose(999, alice, "text", 200)
	uassert.ErrorIs(t, err, ErrNoCrew)
	_, err = cs.Propose(id, bob, "text", 200)
	uassert.ErrorIs(t, err, ErrNotMember, "only a member proposes")
	_, err = cs.Propose(id, alice, "   ", 200)
	uassert.ErrorIs(t, err, ErrBadText)

	pid, _ := cs.Propose(id, alice, "a question", 200)
	uassert.ErrorIs(t, cs.Vote(999, alice, true, 210), ErrNoProposal)
	uassert.ErrorIs(t, cs.Vote(pid, bob, true, 210), ErrNotMember)
	uassert.ErrorIs(t, cs.Vote(pid, alice, true, 200+VoteBlocks), ErrVoteClosed,
		"the deadline is exclusive")
}

func TestCloseRecordsTheResult(t *testing.T) {
	tests := []struct {
		label      string
		aliceVotes bool
		bobVotes   bool
		want       bool
	}{
		{"the bigger holder carries it", true, false, true},
		{"and blocks it", false, true, false},
		{"unanimous yes", true, true, true},
		{"unanimous no", false, false, false},
	}
	for _, tt := range tests {
		cs := New()
		id, _ := cs.Create("crew", alice, tenGNOT, 100) // 10000 shares
		cs.Join(id, bob, tenGNOT/2)                     // 5000 shares
		pid, _ := cs.Propose(id, alice, "a question", 200)

		urequire.NoError(t, cs.Vote(pid, alice, tt.aliceVotes, 210))
		urequire.NoError(t, cs.Vote(pid, bob, tt.bobVotes, 211))

		passed, err := cs.Close(pid, 200+VoteBlocks)
		urequire.NoError(t, err)
		uassert.Equal(t, tt.want, passed, tt.label)

		p, _ := cs.Proposal(pid)
		uassert.True(t, p.Closed, tt.label)
		uassert.Equal(t, tt.want, p.Passed, tt.label)
	}
}

// A tie fails, and a proposal nobody voted on is a tie at zero.
func TestATieFails(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	cs.Join(id, bob, tenGNOT)
	pid, _ := cs.Propose(id, alice, "a question", 200)

	urequire.NoError(t, cs.Vote(pid, alice, true, 210))
	urequire.NoError(t, cs.Vote(pid, bob, false, 211))

	passed, err := cs.Close(pid, 200+VoteBlocks)
	urequire.NoError(t, err)
	uassert.False(t, passed, "equal weight on both sides is not agreement")

	silent, _ := cs.Propose(id, alice, "nobody cares", 200)
	passed, err = cs.Close(silent, 200+VoteBlocks)
	urequire.NoError(t, err)
	uassert.False(t, passed, "0 to 0 is not agreement either")
}

func TestCloseRefusals(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	pid, _ := cs.Propose(id, alice, "a question", 200)

	_, err := cs.Close(999, 5000)
	uassert.ErrorIs(t, err, ErrNoProposal)

	_, err = cs.Close(pid, 200+VoteBlocks-1)
	uassert.ErrorIs(t, err, ErrVoteOpen, "one block early is early")

	_, err = cs.Close(pid, 200+VoteBlocks)
	urequire.NoError(t, err)
	_, err = cs.Close(pid, 200+VoteBlocks)
	uassert.ErrorIs(t, err, ErrVoteClosed, "closing twice does not re-tally")
}

// A vote keeps the weight it was cast with. Ragequitting afterwards does not
// unwind it, which is a v0 caveat stated in the package doc rather than a bug.
func TestAVoteKeepsTheWeightItWasCastWith(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	cs.Join(id, bob, tenGNOT)
	pid, _ := cs.Propose(id, alice, "a question", 200)

	urequire.NoError(t, cs.Vote(pid, bob, true, 210))
	_, _, err := cs.Ragequit(id, bob)
	urequire.NoError(t, err)

	p, _ := cs.Proposal(pid)
	uassert.Equal(t, int64(10000), p.Yes, "bob's ballot stayed behind")
	uassert.ErrorIs(t, cs.Vote(pid, bob, false, 220), ErrNotMember,
		"but he cannot touch it again")
}

func TestRagequitTakesAProRataSlice(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	cs.Join(id, bob, tenGNOT)
	urequire.NoError(t, cs.Fund(id, 2*tenGNOT)) // the crew doubled its money

	shares, amount, err := cs.Ragequit(id, bob)
	urequire.NoError(t, err)
	uassert.Equal(t, tenGNOT/InitialPricePerShare, shares, "every share is burned")
	uassert.Equal(t, 2*tenGNOT, amount, "half of a treasury worth four, for half the shares")

	c, _ := cs.Get(id)
	uassert.Equal(t, 1, c.MemberCount())
	uassert.Equal(t, int64(0), c.SharesOf(bob))
	uassert.False(t, c.IsMember(bob))
	uassert.Equal(t, 2*tenGNOT, c.Treasury)
	uassert.Equal(t, tenGNOT/InitialPricePerShare, c.TotalShares)

	uassert.Equal(t, 2*tenGNOT, cs.CreditOf(bob), "credited, never sent")
	uassert.Equal(t, 2*tenGNOT, cs.TotalOwed())

	_, _, err = cs.Ragequit(id, bob)
	uassert.ErrorIs(t, err, ErrNotMember, "there is nothing left to burn")
	_, _, err = cs.Ragequit(999, alice)
	uassert.ErrorIs(t, err, ErrNoCrew)
}

// A one-member crew ragequitting takes everything: their shares ARE the total,
// so the division is exact whatever the numbers are.
func TestAOneMemberCrewTakesEverything(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, 5001, 100) // 5 shares, a treasury of 5001

	shares, amount, err := cs.Ragequit(id, alice)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(5), shares)
	uassert.Equal(t, int64(5001), amount, "including the ugnot that bought no share")

	c, _ := cs.Get(id)
	uassert.Equal(t, int64(0), c.Treasury)
	uassert.Equal(t, int64(0), c.TotalShares)
	uassert.Equal(t, 0, c.MemberCount())
}

// Everyone ragequitting empties the treasury to the last ugnot, even when no
// single division is exact: the dust each leaver rounds away belongs to whoever
// is still in, and the last one out holds every share.
func TestEveryoneRagequittingEmptiesTheTreasury(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, 1000, 100)
	join(t, cs, id, bob, 1000)
	join(t, cs, id, carol, 1000)
	urequire.NoError(t, cs.Fund(id, 2)) // 3002 ugnot over 3 shares, divides by nothing

	c, _ := cs.Get(id)
	urequire.Equal(t, int64(3002), c.Treasury)
	urequire.Equal(t, int64(3), c.TotalShares)

	var paid int64
	for _, who := range []address{alice, bob, carol} {
		_, amount, err := cs.Ragequit(id, who)
		urequire.NoError(t, err)
		paid += amount
	}

	uassert.Equal(t, int64(3002), paid, "every ugnot left with somebody")
	uassert.Equal(t, int64(0), c.Treasury, "to the last one")
	uassert.Equal(t, int64(0), c.TotalShares)
	uassert.Equal(t, 0, c.MemberCount())
	uassert.Equal(t, int64(3002), cs.TotalOwed())

	// The dust did not land evenly, which is the point: the people who
	// stayed longest absorbed it.
	uassert.Equal(t, int64(1000), cs.CreditOf(alice), "first out, rounded down hardest")
	uassert.Equal(t, int64(1001), cs.CreditOf(bob))
	uassert.Equal(t, int64(1001), cs.CreditOf(carol))
}

// An emptied crew is not a dead one. With no shares outstanding there is no
// value to price against, so it reopens at the price it opened at.
func TestRejoiningAnEmptiedCrewIsBackAtTheOpeningPrice(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	_, _, err := cs.Ragequit(id, alice)
	urequire.NoError(t, err)

	c, _ := cs.Get(id)
	urequire.Equal(t, int64(0), c.TotalShares)
	uassert.Equal(t, int64(0), c.ValuePerShare(), "nothing is worth anything yet")
	uassert.Equal(t, InitialPricePerShare, c.PricePerShare(), "but a share still has a price")

	got, err := cs.Join(id, dave, tenGNOT)
	urequire.NoError(t, err)
	uassert.Equal(t, tenGNOT/InitialPricePerShare, got)
	uassert.Equal(t, tenGNOT, c.Treasury)
}

func TestWithdrawZeroesTheCreditBeforeItReturns(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	cs.Join(id, bob, tenGNOT)
	_, owed, _ := cs.Ragequit(id, bob)
	urequire.True(t, owed > 0, "bob is owed something")

	got, err := cs.Withdraw(bob)
	urequire.NoError(t, err)
	uassert.Equal(t, owed, got)
	uassert.Equal(t, int64(0), cs.CreditOf(bob), "zeroed, so a reentrant call finds nothing")
	uassert.Equal(t, int64(0), cs.TotalOwed())

	_, err = cs.Withdraw(bob)
	uassert.ErrorIs(t, err, ErrNothing)
	_, err = cs.Withdraw(carol)
	uassert.ErrorIs(t, err, ErrNothing)
}

// Credits accumulate across crews, because one ledger serves all of them.
func TestCreditsAccumulateAcrossCrews(t *testing.T) {
	cs := New()
	first, _ := cs.Create("first", alice, tenGNOT, 100)
	second, _ := cs.Create("second", bob, tenGNOT, 100)
	join(t, cs, second, alice, tenGNOT)

	_, a, _ := cs.Ragequit(first, alice)
	_, b, _ := cs.Ragequit(second, alice)
	uassert.Equal(t, a+b, cs.CreditOf(alice), "one withdrawal collects both")
	uassert.Equal(t, 2, cs.Len())
}

func TestListIsNewestFirst(t *testing.T) {
	cs := New()
	first, _ := cs.Create("first", alice, tenGNOT, 100)
	second, _ := cs.Create("second", bob, tenGNOT, 101)
	third, _ := cs.Create("third", carol, tenGNOT, 102)

	got := cs.List(10)
	urequire.Equal(t, 3, len(got))
	uassert.Equal(t, uint64(third), uint64(got[0].ID))
	uassert.Equal(t, uint64(second), uint64(got[1].ID))
	uassert.Equal(t, uint64(first), uint64(got[2].ID))
	uassert.Equal(t, "third", got[0].Crew.Name)

	uassert.Equal(t, 1, len(cs.List(1)))
	uassert.Equal(t, 0, len(cs.List(0)))
}

// Members comes back in join order and as a copy, so a Render can never
// reshuffle the roster it is reading.
func TestMembersAreAnOrderedCopy(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)
	cs.Join(id, bob, tenGNOT)
	cs.Join(id, carol, tenGNOT)

	c, _ := cs.Get(id)
	got := c.Members()
	urequire.Equal(t, 3, len(got))
	uassert.Equal(t, alice.String(), got[0].String())
	uassert.Equal(t, bob.String(), got[1].String())
	uassert.Equal(t, carol.String(), got[2].String())

	got[0] = dave
	uassert.Equal(t, alice.String(), c.Members()[0].String(), "the caller got a copy")

	// Ragequitting removes the leaver and keeps the rest in order.
	cs.Ragequit(id, bob)
	got = c.Members()
	urequire.Equal(t, 2, len(got))
	uassert.Equal(t, alice.String(), got[0].String())
	uassert.Equal(t, carol.String(), got[1].String())
}

func TestFundRefusals(t *testing.T) {
	cs := New()
	id, _ := cs.Create("crew", alice, tenGNOT, 100)

	uassert.ErrorIs(t, cs.Fund(999, 100), ErrNoCrew)
	uassert.ErrorIs(t, cs.Fund(id, 0), ErrBadAmount)
	uassert.ErrorIs(t, cs.Fund(id, -1), ErrBadAmount)

	c, _ := cs.Get(id)
	uassert.Equal(t, tenGNOT, c.Treasury, "no refusal moved the treasury")
	uassert.Equal(t, 0, cs.ProposalCount())
}
