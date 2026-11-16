package smallgrants

// Regression tests from the economic review of this realm, each one an attack
// that worked against the first version. Three are adapted, each marked
// ADAPTED with why: seating now takes the subject's own Join, and two
// assertions were written against a fix this version does not take.

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var dave = testutils.TestAddress("dave")

// seatCarol grows the set to four the legitimate way: two of three.
func seatCarol(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(Moul))
	id := Propose(cross(cur), carol.String(), true, "a fourth")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), id, true, "")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Second(cross(cur), id, true, "")
	// ADAPTED: a seat is taken by its subject's own call.
	testing.SetRealm(testing.NewUserRealm(carol))
	Join(cross(cur), id)
	urequire.Equal(t, 4, len(Controllers()))
}

// unseatCarol shrinks back to three: three of four, carol may not vote.
func unseatCarol(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(Moul))
	id := Propose(cross(cur), carol.String(), false, "back to three")
	for _, v := range []address{Moul, Jaekwon, Aeddi} {
		testing.SetRealm(testing.NewUserRealm(v))
		Second(cross(cur), id, true, "")
	}
	urequire.Equal(t, 3, len(Controllers()))
}

// A1: two yes of four is pending; the set shrinks to three; the next ballot,
// a REFUSAL, pays.
func TestAttackRefusePays(cur realm, t *testing.T) {
	reset()
	fund(MaxGrant)
	seatCarol(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), MaxGrant, "t", "r")
	for _, v := range []address{Moul, Jaekwon} {
		testing.SetRealm(testing.NewUserRealm(v))
		Accept(cross(cur), id, "")
	}
	urequire.Equal(t, StatusPending, Status(id))
	unseatCarol(cur, t)

	before := balanceOf(bob)
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Refuse(cross(cur), id, "no")
	uassert.Equal(t, before, balanceOf(bob), "a Refuse ballot must never pay")
	uassert.NotEqual(t, StatusPaid, Status(id), "a Refuse ballot must never pay")
}

// A2: same shape on a motion: a NO second seats dave.
func TestAttackNoSecondSeats(cur realm, t *testing.T) {
	reset()
	seatCarol(cur, t)
	testing.SetRealm(testing.NewUserRealm(Moul))
	mid := Propose(cross(cur), dave.String(), true, "dave")
	for _, v := range []address{Moul, Jaekwon} {
		testing.SetRealm(testing.NewUserRealm(v))
		Second(cross(cur), mid, true, "")
	}
	unseatCarol(cur, t)
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Second(cross(cur), mid, false, "no")
	uassert.False(t, IsController(dave.String()), "a no vote must never seat anyone")
}

// A3: with a stale quorum and a short balance, no controller can refuse the
// request: every ballot, Refuse included, aborts on the balance check.
func TestAttackStaleQuorumCannotBeRefused(cur realm, t *testing.T) {
	reset()
	seatCarol(cur, t)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), MaxGrant, "t", "r")
	for _, v := range []address{Moul, Jaekwon} {
		testing.SetRealm(testing.NewUserRealm(v))
		Accept(cross(cur), id, "")
	}
	unseatCarol(cur, t)
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	uassert.NotAborts(t, cur, func() { Refuse(cross(cur), id, "no") }, "a controller must be able to refuse")
}

// A4: a request whose remaining voters all left is pending forever; no
// controller call can settle it, only the filer's Withdraw.
//
// ADAPTED: the original asserted the request is closed the moment the set
// shrinks. Here a set change voids the old ballots instead, so right after the
// shrink the request is open to the new set, not orphaned: both remaining
// controllers may vote again, and the property under test, that a controller
// call settles it, holds. The second half is the original's case, a request
// that truly cannot pass, which anyone now closes.
func TestAttackOrphanedPending(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 1, "t", "r")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Accept(cross(cur), id, "")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Refuse(cross(cur), id, "")
	shrinkToMoulAndJaekwon(cur, t)
	urequire.Equal(t, StatusPending, Status(id), "voided, not orphaned: the new set decides")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Accept(cross(cur), id, "")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Refuse(cross(cur), id, "")
	uassert.NotEqual(t, StatusPending, Status(id), "it can no longer pass, yet it stays open")

	// Filed by one of a set of two, paying the other: nobody may vote on it.
	testing.SetRealm(testing.NewUserRealm(Moul))
	stuck := Request(cross(cur), Jaekwon.String(), 1, "t", "r")
	testing.SetRealm(testing.NewUserRealm(alice))
	Close(cross(cur), stuck)
	uassert.Equal(t, StatusRefused, Status(stuck), "anyone closes what cannot pass")
}

// A5: the cap is per request only: two controllers pay one payee 3x MaxGrant
// in three requests, back to back.
//
// ADAPTED: the original called Request three times and expected each call to
// succeed. The cap now refuses the second request at filing, where the payee
// learns it, so the second and third filings are asserted to abort; the
// property, one payee never gets more than MaxGrant, is the original's.
func TestAttackCapIsPerRequestOnly(cur realm, t *testing.T) {
	reset()
	fund(3 * MaxGrant)
	before := balanceOf(bob)
	for i := 0; i < 3; i++ {
		testing.SetRealm(testing.NewUserRealm(alice))
		if i > 0 {
			uassert.AbortsContains(t, cur, "per 30 days", func() {
				Request(cross(cur), bob.String(), MaxGrant, "t", "r")
			})
			continue
		}
		id := Request(cross(cur), bob.String(), MaxGrant, "t", "r")
		for _, v := range []address{Moul, Jaekwon} {
			testing.SetRealm(testing.NewUserRealm(v))
			Accept(cross(cur), id, "")
		}
	}
	uassert.True(t, balanceOf(bob)-before <= MaxGrant, "one payee got more than MaxGrant")
}

// A6: a removed controller's old yes comes back to life when re-seated.
func TestAttackReseatRevivesBallot(cur realm, t *testing.T) {
	reset()
	fund(1)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Request(cross(cur), bob.String(), 1, "t", "r")
	testing.SetRealm(testing.NewUserRealm(Aeddi))
	Accept(cross(cur), id, "")
	shrinkToMoulAndJaekwon(cur, t)
	testing.SetRealm(testing.NewUserRealm(Moul))
	mid := Propose(cross(cur), Aeddi.String(), true, "back")
	testing.SetRealm(testing.NewUserRealm(Moul))
	Second(cross(cur), mid, true, "")
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Second(cross(cur), mid, true, "")
	testing.SetRealm(testing.NewUserRealm(Aeddi)) // ADAPTED: the seat is taken by Join
	Join(cross(cur), mid)
	urequire.True(t, IsController(Aeddi.String()))
	before := balanceOf(bob)
	testing.SetRealm(testing.NewUserRealm(Moul))
	Refuse(cross(cur), id, "no") // 1 yes (revived) + 1 no, J left: pending
	testing.SetRealm(testing.NewUserRealm(Jaekwon))
	Accept(cross(cur), id, "")
	uassert.Equal(t, before, balanceOf(bob), "aeddi never voted yes as a member of this set")
}
