package grants

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice") // files requests
	bob   = testutils.TestAddress("bob")   // gets paid
	carol = testutils.TestAddress("carol") // a would-be controller, or a sock
)

func balanceOf(a address) int64 {
	return banker.NewReadonlyBanker().GetCoins(a).AmountOf(Denom)
}

// fund puts ugnot at the realm address the way a multisig's plain send does.
func fund(n int64) {
	testing.IssueCoins(Address(), chain.NewCoins(chain.NewCoin(Denom, n)))
}

func TestDeployState(t *testing.T) {
	reset()
	uassert.True(t, strings.HasPrefix(selfPath, "gno.land/r/"), "the path is read at init, never written down: "+selfPath)
	uassert.True(t, strings.HasSuffix(selfPath, "/v0"), selfPath)
	uassert.Equal(t, chain.PackageAddress(selfPath), Address())
	uassert.Equal(t, 3, len(Controllers()))
	uassert.Equal(t, 2, Quorum())
	for _, c := range []address{Moul, Jaekwon, Aeddi} {
		uassert.True(t, c.IsValid())
		uassert.True(t, IsController(c.String()))
		uassert.True(t, IsAllowed(c.String()), "the allowlist starts with the controllers")
	}
	uassert.False(t, Paused())
	uassert.Equal(t, int64(100_000_000), MaxGrant)
}

func TestRequestIsValidated(cur realm, t *testing.T) {
	long := strings.Repeat("x", MaxReasonLen+1)
	cases := []struct {
		name, to      string
		amount        int64
		title, reason string
		want          string
	}{
		{"bad address", "nope", 1, "t", "r", "is not a valid address"},
		{"self", Address().String(), 1, "t", "r", "cannot pay itself"},
		{"zero", bob.String(), 0, "t", "r", "must be a positive"},
		{"negative", bob.String(), -5, "t", "r", "must be a positive"},
		{"over the cap", bob.String(), MaxGrant + 1, "t", "r", "over the cap"},
		{"no title", bob.String(), 1, "  ", "r", "the title is empty"},
		{"invisible title", bob.String(), 1, "​", "r", "the title is empty"},
		{"no reason", bob.String(), 1, "t", "", "the reason is empty"},
		{"long title", bob.String(), 1, strings.Repeat("x", MaxTitleLen+1), "r", "title is longer"},
		{"long reason", bob.String(), 1, "t", long, "reason is longer"},
	}
	// No t.Run in this file: testing.SetRealm does not reach a crossing call
	// made from a subtest's frame, so every case runs in the test body.
	for _, tc := range cases {
		reset()
		testing.SetRealm(testing.NewUserRealm(alice))
		uassert.AbortsContains(t, cur, tc.want, func() {
			Request(cross(cur), tc.to, tc.amount, tc.title, tc.reason)
		}, tc.name)
	}
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.Equal(t, int64(1), Request(cross(cur), bob.String(), MaxGrant, "t", "r"), "the cap itself is allowed")
}

// The whole flow: alice asks for bob, one yes is not enough, the second pays.
func TestTwoOfThreePays(cur realm, t *testing.T) {
	reset()
	fund(30_000_000)
	before := balanceOf(bob)

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 20_000_000, "Port a lib", "bob has no gas")

	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), id, true, "")
	uassert.Equal(t, StatusPending, Status(id), "one controller alone pays nothing")
	uassert.Equal(t, before, balanceOf(bob))

	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Vote(cross(cur), id, true, "ok")
	uassert.Equal(t, StatusPaid, Status(id))
	uassert.Equal(t, before+20_000_000, balanceOf(bob))
	uassert.Equal(t, int64(10_000_000), Balance())
	uassert.Equal(t, int64(20_000_000), TotalPaid())

	testing.SetRealm(testing.NewUserRealm(Aeddi))
	uassert.AbortsContains(t, cur, "already paid", func() { Vote(cross(cur), id, true, "") })
}

func TestTwoNoRejects(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 1, "t", "r")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), id, false, "not now")
	uassert.Equal(t, StatusPending, Status(id))
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Vote(cross(cur), id, false, "")
	uassert.Equal(t, StatusRejected, Status(id))
}

func TestWhoMayVote(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Moul))
	id := Request(cross(cur), Jaekwon.String(), 1, "t", "r") // filed by moul, pays jaekwon

	cases := []struct {
		name  string
		voter address
		want  string
	}{
		{"stranger", alice, "is not a controller"},
		{"filer", Moul, "is a party to this decision"},
		{"payee", Jaekwon, "is a party to this decision"},
	}
	for _, tc := range cases {
		testing.SetRealm(testing.NewUserRealm(tc.voter))
		uassert.AbortsContains(t, cur, tc.want, func() { Vote(cross(cur), id, true, "") }, tc.name)
	}
	// aeddi is the only one who may vote, and one yes of a quorum of two is
	// not enough: a controller asking for a controller needs both others.
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Vote(cross(cur), id, true, "")
	uassert.Equal(t, StatusRejected, Status(id), "nobody is left who could cast the second yes")
}

func TestVoteTwice(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 1, "t", "r")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), id, true, "")
	testing.SetRealm(testing.NewUserRealm(Moul))
	uassert.AbortsContains(t, cur, "already voted", func() { Vote(cross(cur), id, true, "") })
}

func TestUnderfundedVoteIsRefusedAndLeavesNoTrace(cur realm, t *testing.T) {
	reset()
	fund(5)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 10, "t", "r")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), id, true, "")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	uassert.AbortsContains(t, cur, "fund the realm first", func() { Vote(cross(cur), id, true, "") })
	uassert.Equal(t, StatusPending, Status(id))
	uassert.Equal(t, 1, len(getRequest(id).Ballots), "the refused ballot was not recorded")

	fund(5)
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Vote(cross(cur), id, true, "")
	uassert.Equal(t, StatusPaid, Status(id))
}

func TestWithdraw(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 1, "t", "r")
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only the filer", func() { Withdraw(cross(cur), id) })
	testing.SetRealm(testing.NewUserRealm(alice))
	Withdraw(cross(cur), id)
	uassert.Equal(t, StatusWithdrawn, Status(id))
}

// Paused refuses NEW requests from anyone off the allowlist, and nothing else.
// The allowlist is not the controller set: a controller taken off it is
// refused, an address put on it is not.
func TestPauseRefusesOnlyNewRequestsOffTheAllowlist(cur realm, t *testing.T) {
	reset()
	fund(10)
	testing.SetRealm(testing.NewUserRealm(alice))
	inflight := Request(cross(cur), bob.String(), 10, "t", "r")
	testing.SetRealm(testing.NewUserRealm(alice))
	withdrawable := Request(cross(cur), bob.String(), 1, "t", "r")

	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Pause(cross(cur))
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Allow(cross(cur), carol.String())
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Disallow(cross(cur), Moul.String())
	urequire.True(t, Paused())

	cases := []struct {
		name string
		who  address
		ok   bool
	}{
		{"stranger", alice, false},
		{"controller taken off the allowlist", Moul, false},
		{"controller on the allowlist", Jaekwon, true},
		{"non-controller on the allowlist", carol, true},
	}
	for _, tc := range cases {
		testing.SetRealm(testing.NewUserRealm(tc.who))
		if tc.ok {
			Request(cross(cur), bob.String(), 1, "t", "r")
			continue
		}
		uassert.AbortsContains(t, cur, "paused", func() {
			Request(cross(cur), bob.String(), 1, "t", "r")
		}, tc.name)
	}

	// In flight keeps working: withdrawal, votes, and the payout.
	testing.SetRealm(testing.NewUserRealm(alice))
	Withdraw(cross(cur), withdrawable)
	before := balanceOf(bob)
	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), inflight, true, "")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Vote(cross(cur), inflight, true, "")
	uassert.Equal(t, StatusPaid, Status(inflight), "paused never stops a payout")
	uassert.Equal(t, before+10, balanceOf(bob))

	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Resume(cross(cur))
	testing.SetRealm(testing.NewUserRealm(alice))
	Request(cross(cur), bob.String(), 1, "t", "r")
}

func TestOnlyControllersTouchThePause(cur realm, t *testing.T) {
	reset()
	calls := []struct {
		name string
		fn   func()
	}{
		{"Pause", func() { Pause(cross(cur)) }},
		{"Resume", func() { Resume(cross(cur)) }},
		{"Allow", func() { Allow(cross(cur), alice.String()) }},
		{"Disallow", func() { Disallow(cross(cur), Moul.String()) }},
		{"Propose", func() { Propose(cross(cur), alice.String(), true, "me") }},
	}
	for _, c := range calls {
		testing.SetRealm(testing.NewUserRealm(alice))
		uassert.AbortsContains(t, cur, "is not a controller", c.fn, c.name)
	}
}

func TestAddAController(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Moul))
	id := Propose(cross(cur), carol.String(), true, "more hands")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), id, true, "")
	uassert.False(t, IsController(carol.String()), "one controller cannot seat anyone")
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Second(cross(cur), id, true, "")
	uassert.Equal(t, StatusAdopted, MotionStatus(id))
	uassert.True(t, IsController(carol.String()))
	uassert.Equal(t, 3, Quorum(), "four controllers need three")
	uassert.False(t, IsAllowed(carol.String()), "seating a controller does not touch the allowlist")
}

// The three constants are only the seed: a controller seated later, with no
// redeploy, votes a grant through like a founding one.
func TestFourthControllerPays(cur realm, t *testing.T) {
	reset()
	fund(10_000_000)
	testing.SetRealm(testing.NewUserRealm(Moul))
	mid := Propose(cross(cur), carol.String(), true, "a fourth")
	Second(cross(cur), mid, true, "")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Second(cross(cur), mid, true, "")
	urequire.True(t, IsController(carol.String()))

	before := balanceOf(bob)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 5_000_000, "t", "r")
	for _, v := range []address{Moul, Aeddi} {
		testing.SetRealm(testing.NewUserRealm(v))
		Vote(cross(cur), id, true, "")
	}
	uassert.Equal(t, StatusPending, Status(id), "two of four is not a majority")
	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), id, true, "")
	uassert.Equal(t, StatusPaid, Status(id), "the fourth controller's yes is the one that pays")
	uassert.Equal(t, before+5_000_000, balanceOf(bob))
}

// The defect this realm is built around, on every shape it can take: on a
// small set, no controller may remove another alone and then pay alone. The
// TestTakeover* functions are that proof, one shape each.

// three: one yes removes nobody.
func TestTakeoverThreeOneYesRemovesNobody(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Moul))
	id := Propose(cross(cur), Jaekwon.String(), false, "take over")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), id, true, "")
	uassert.Equal(t, StatusPending, MotionStatus(id))
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	uassert.AbortsContains(t, cur, "is a party", func() { Second(cross(cur), id, false, "") })
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Second(cross(cur), id, false, "")
	uassert.Equal(t, StatusRejected, MotionStatus(id))
	uassert.True(t, IsController(Jaekwon.String()))
}

// two: a removal cannot be filed.
func TestTakeoverTwoCannotFileARemoval(cur realm, t *testing.T) {
	reset()
	shrinkToMoulAndJaekwon(cur, t)
	testing.SetRealm(testing.NewUserRealm(Moul))
	uassert.AbortsContains(t, cur, "add a third first", func() {
		Propose(cross(cur), Jaekwon.String(), false, "take over")
	})
}

// two: a removal filed at three dies when the set shrinks.
func TestTakeoverRemovalFiledAtThreeDiesAtTwo(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Moul))
	late := Propose(cross(cur), Jaekwon.String(), false, "filed while there were three")
	shrinkToMoulAndJaekwon(cur, t)
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), late, true, "")
	uassert.Equal(t, StatusRejected, MotionStatus(late), "the subject's seat is a yes nobody can cast")
	uassert.True(t, IsController(Jaekwon.String()))

	// The second half of the attack: had the removal gone through, moul would
	// now be the whole set and his one yes would pay a friend's request.
	fund(1)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), carol.String(), 1, "sock", "filed by a friend")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), id, true, "")
	uassert.Equal(t, StatusPending, Status(id), "one controller paid alone")
	uassert.Equal(t, int64(0), balanceOf(carol))
}

// two: one yes pays nobody.
func TestTakeoverTwoOneYesPaysNobody(cur realm, t *testing.T) {
	reset()
	fund(1)
	shrinkToMoulAndJaekwon(cur, t)
	testing.SetRealm(testing.NewUserRealm(Moul))
	id := Request(cross(cur), carol.String(), 1, "sock", "r")
	testing.SetRealm(testing.NewUserRealm(Moul))
	uassert.AbortsContains(t, cur, "is a party", func() { Vote(cross(cur), id, true, "") })
	testing.SetRealm(testing.NewUserRealm(alice))
	id = Request(cross(cur), carol.String(), 1, "sock", "filed by a friend")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), id, true, "")
	uassert.Equal(t, StatusPending, Status(id), "two controllers means two yes")
	uassert.Equal(t, int64(1), Balance())
}

// two: one cannot seat a sock.
func TestTakeoverTwoOneCannotSeatASock(cur realm, t *testing.T) {
	reset()
	shrinkToMoulAndJaekwon(cur, t)
	testing.SetRealm(testing.NewUserRealm(Moul))
	id := Propose(cross(cur), carol.String(), true, "a sock")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), id, true, "")
	uassert.Equal(t, StatusPending, MotionStatus(id))
	uassert.False(t, IsController(carol.String()))
}

// a removed controller's yes stops counting.
func TestTakeoverRemovedControllersYesStopsCounting(cur realm, t *testing.T) {
	reset()
	fund(1)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 1, "t", "r")
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Vote(cross(cur), id, true, "")
	shrinkToMoulAndJaekwon(cur, t) // removes aeddi
	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), id, true, "")
	uassert.Equal(t, StatusPending, Status(id), "aeddi's ballot is on the record and carries no weight")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Vote(cross(cur), id, true, "")
	uassert.Equal(t, StatusPaid, Status(id))
}

// shrinkToMoulAndJaekwon removes aeddi the legitimate way: two of three.
func shrinkToMoulAndJaekwon(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(Moul))
	id := Propose(cross(cur), Aeddi.String(), false, "stepping back")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), id, true, "")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Second(cross(cur), id, true, "")
	urequire.Equal(t, StatusAdopted, MotionStatus(id))
	urequire.Equal(t, 2, len(Controllers()))
}

func TestRenderEscapesCallerText(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 1, "a | b ![x](y)", "**bold** <script>")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Vote(cross(cur), id, false, "c | d")
	index, page := Render(""), Render("request/1")
	uassert.False(t, strings.Contains(index, "a | b"), "a pipe in a title would open a column")
	uassert.False(t, strings.Contains(page, "c | d"), "a pipe in a note would open a column")
	uassert.False(t, strings.Contains(index+page, "![x](y)"), "an image would render")
	uassert.False(t, strings.Contains(page, "**bold**"), "a reason is not markdown")
	uassert.True(t, strings.Contains(Render("request/9"), "There is no request 9"))
	uassert.True(t, strings.Contains(Render("nope"), "Not found"))
}
