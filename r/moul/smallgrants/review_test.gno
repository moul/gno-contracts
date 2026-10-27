package smallgrants

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// Regression tests from the governance review of this realm: each attack
// worked against the first version, and the rule that stops it is named.

// A removal used to rewrite what a pending request pays: the smallest yes
// left the set, and the next yes paid the largest. Ballots now die with the
// set they were cast under.
func TestReviewRemovalCannotRaiseThePayout(cur realm, t *testing.T) {
	reset()
	fund(MaxGrant)
	seatCarol(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), MaxGrant, "t", "r")
	testing.SetRealm(testing.NewUserRealm(Moul))
	AcceptPart(cross(cur), id, 1_000_000, "one GNOT, no more")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Accept(cross(cur), id, "")

	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	mid := Propose(cross(cur), Moul.String(), false, "out")
	for _, v := range []address{Jaekwon, Aeddi, carol} {
		testing.SetRealm(testing.NewUserRealm(v))
		Second(cross(cur), mid, true, "")
	}
	urequire.False(t, IsController(Moul.String()))

	before := balanceOf(bob)
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Accept(cross(cur), id, "")
	uassert.Equal(t, StatusPending, Status(id), "jaekwon's yes was cast under the old set")
	uassert.Equal(t, before, balanceOf(bob))
	uassert.True(t, strings.Contains(Render("request/1"), voided), "the old ballots stay visible")
}

// A pending motion's ballots die with the set too: a yes cast at four is not
// a yes at three.
func TestReviewSetChangeVoidsMotionBallots(cur realm, t *testing.T) {
	reset()
	dave := testutils.TestAddress("dave")
	testing.SetRealm(testing.NewUserRealm(Moul))
	mid := Propose(cross(cur), dave.String(), true, "dave")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), mid, true, "")
	seatCarol(cur, t) // the set changes under the motion
	testing.SetRealm(testing.NewUserRealm(dave))
	Join(cross(cur), mid)
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Second(cross(cur), mid, true, "")
	uassert.False(t, IsController(dave.String()), "one live yes of a quorum of three")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), mid, true, "moul again, under the new set")
	testing.SetRealm(testing.NewUserRealm(carol))
	Second(cross(cur), mid, true, "")
	uassert.True(t, IsController(dave.String()))
}

// Seating the realm's own address and two keyless ones used to raise the
// quorum past the controllers who can sign, for good. A seat now takes its
// subject's own call, and the realm's address is refused outright.
func TestReviewNoSeatWithoutAKey(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(Moul))
	uassert.AbortsContains(t, cur, "cannot sit on its own", func() {
		Propose(cross(cur), Address().String(), true, "the realm")
	})
	for _, name := range []string{"keyless1", "keyless2", "keyless3"} {
		testing.SetRealm(testing.NewUserRealm(Moul))
		mid := Propose(cross(cur), testutils.TestAddress(name).String(), true, "a typo")
		for _, v := range []address{Moul, Jaekwon, Aeddi} {
			testing.SetRealm(testing.NewUserRealm(v))
			Second(cross(cur), mid, true, "")
		}
		uassert.Equal(t, StatusPending, MotionStatus(mid), "nobody joined")
	}
	uassert.Equal(t, 3, len(Controllers()))
	uassert.Equal(t, 2, Quorum(), "the quorum never passes the controllers who can sign")
}

func TestReviewSetIsBounded(cur realm, t *testing.T) {
	reset()
	for i := len(controllers); i < MaxControllers; i++ {
		c := testutils.TestAddress("c" + itoa(int64(i)))
		testing.SetRealm(testing.NewUserRealm(Moul))
		mid := Propose(cross(cur), c.String(), true, "grow")
		testing.SetRealm(testing.NewUserRealm(c))
		Join(cross(cur), mid)
		for _, v := range Controllers() {
			if MotionStatus(mid) != StatusPending {
				break
			}
			testing.SetRealm(testing.NewUserRealm(v))
			Second(cross(cur), mid, true, "")
		}
	}
	urequire.Equal(t, MaxControllers, len(Controllers()))
	testing.SetRealm(testing.NewUserRealm(Moul))
	uassert.AbortsContains(t, cur, "the set is full", func() {
		Propose(cross(cur), carol.String(), true, "one more")
	})
}

// The open list used to grow with every filing, and the decided table walked
// past every pending row to find its ten. Both are bounded now.
func TestReviewOpenQueueIsBounded(cur realm, t *testing.T) {
	reset()
	fund(MaxGrant)
	testing.SetRealm(testing.NewUserRealm(alice))
	paid := Request(cross(cur), carol.String(), 1, "decided early", "r")
	for _, v := range []address{Moul, Jaekwon} {
		testing.SetRealm(testing.NewUserRealm(v))
		Accept(cross(cur), paid, "")
	}
	small := len(Render(""))
	for i := 0; i < MaxOpen; i++ {
		testing.SetRealm(testing.NewUserRealm(alice))
		Request(cross(cur), testutils.TestAddress("p"+itoa(int64(i))).String(), 1, "spam", "r")
	}
	urequire.Equal(t, MaxOpen, OpenCount())
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "already waiting", func() {
		Request(cross(cur), bob.String(), 1, "one more", "r")
	})
	index := Render("")
	uassert.True(t, strings.Contains(index, "decided early"), "a full queue does not hide the decided table")
	uassert.True(t, len(index) < small+MaxOpen*200, "the index grows with the bounded queue only: "+itoa(int64(len(index))))
}

// A request nobody decides lapses: votes stop, anyone closes it, and its
// payee's room comes back.
func TestReviewLapse(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), MaxGrant, "t", "r")
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "can still pass", func() { Close(cross(cur), id) })
	testing.SkipHeights(Expiry/5 + 1) // five seconds a block in tests
	testing.SetRealm(testing.NewUserRealm(Moul))
	uassert.AbortsContains(t, cur, "has lapsed", func() { Accept(cross(cur), id, "") })
	testing.SetRealm(testing.NewUserRealm(carol))
	Close(cross(cur), id)
	uassert.Equal(t, StatusLapsed, Status(id))
	uassert.Equal(t, MaxGrant, Room(bob.String()))
}

// The cap on one payee is over a sliding window, not for life. One loop, no
// helper closure: testing.SetRealm does not reach a crossing call made from
// a closure's frame.
func TestReviewPayeeWindowSlides(cur realm, t *testing.T) {
	reset()
	fund(2 * MaxGrant)
	steps := []struct {
		amount   int64
		skip     int64 // blocks to skip before filing
		roomLeft int64
	}{
		{40_000_000, 0, 60_000_000}, // a part paid leaves the rest to ask for
		{60_000_000, 0, 0},
		{MaxGrant, Window/5 + 1, 0}, // five seconds a block: the window slid
	}
	for _, st := range steps {
		testing.SkipHeights(st.skip)
		testing.SetRealm(testing.NewUserRealm(alice))
		id := Request(cross(cur), bob.String(), st.amount, "t", "r")
		for _, v := range []address{Moul, Jaekwon} {
			testing.SetRealm(testing.NewUserRealm(v))
			Accept(cross(cur), id, "")
		}
		urequire.Equal(t, StatusPaid, Status(id))
		uassert.Equal(t, st.roomLeft, Room(bob.String()))
	}
}

// Two removals of the same controller: the second, once its change has
// happened, fails instead of adopting a no-op that would void every ballot.
func TestReviewStaleRemovalDoesNotVoidBallots(cur realm, t *testing.T) {
	reset()
	seatCarol(cur, t)
	var mids []int64
	for i := 0; i < 2; i++ {
		testing.SetRealm(testing.NewUserRealm(Moul))
		mids = append(mids, Propose(cross(cur), carol.String(), false, "out"))
	}
	for _, v := range []address{Moul, Jaekwon, Aeddi} {
		testing.SetRealm(testing.NewUserRealm(v))
		Second(cross(cur), mids[0], true, "")
	}
	urequire.False(t, IsController(carol.String()))
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 1, "t", "r")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Accept(cross(cur), id, "")
	before := epoch
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Second(cross(cur), mids[1], true, "")
	uassert.Equal(t, StatusRejected, MotionStatus(mids[1]))
	uassert.Equal(t, before, epoch, "moul's yes on the request still counts")
}
