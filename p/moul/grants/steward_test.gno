package grants

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// The capture this file exists for. On a two-member board the subject of a
// removal is barred from voting on it, so the eligible set was ONE and so was
// its majority: either member could remove the other alone, then approve any
// sock's request and accept its proof, and the treasury left on one signature.
func TestTwoMemberBoardCannotBeCapturedByOne(t *testing.T) {
	b := New(alice, bob)

	_, err := b.SubmitMemberChange(alice, bob, false, "goodbye", 1)
	uassert.ErrorIs(t, err, ErrBoardTooSmall, "a board of two cannot remove a member by itself")
	uassert.True(t, b.IsMember(bob))
	uassert.Equal(t, 2, b.MemberCount())

	// Adding still works, and still needs both.
	add, err := b.SubmitMemberChange(alice, carol, true, "", 2)
	urequire.NoError(t, err)
	uassert.Equal(t, 2, b.Majority(add))
	st, err := b.Vote(alice, add.ID, true, "", 3)
	urequire.NoError(t, err)
	uassert.Equal(t, "pending", st.String())
}

// A removal counts the subject's seat in the bar even though the subject may
// not vote. On an odd board that changes nothing; on an even board it is one
// more ballot, and that one ballot is what stops a minority-plus-one from
// shrinking the board towards a size it controls.
func TestRemovalCountsTheSubjectsSeat(t *testing.T) {
	cases := []struct {
		name    string
		members []address
		subject address
		bar     int
	}{
		{"three", []address{alice, bob, carol}, carol, 2},
		{"four", []address{alice, bob, carol, dave}, carol, 3},
		{"five", []address{alice, bob, carol, dave, mallory}, carol, 3},
	}
	for _, tc := range cases {
		b := New(tc.members...)
		r, err := b.SubmitMemberChange(alice, tc.subject, false, "", 1)
		urequire.NoError(t, err, tc.name)
		uassert.Equal(t, tc.bar, b.Majority(r), tc.name)
	}

	b := New(alice, bob, carol, dave)
	r, err := b.SubmitMemberChange(alice, carol, false, "", 1)
	urequire.NoError(t, err)
	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "", 2)))
	st, err := b.Vote(bob, r.ID, true, "", 3)
	urequire.NoError(t, err)
	uassert.Equal(t, "pending", st.String(), "two of four is not a majority of the board")
	st, err = b.Vote(dave, r.ID, true, "", 4)
	urequire.NoError(t, err)
	uassert.Equal(t, "completed", st.String())
	uassert.False(t, b.IsMember(carol))
}

func TestSetMembersReplacesTheBoard(t *testing.T) {
	b := New(alice, bob)
	r := submitOne(t, b)
	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "", 11)))

	uassert.ErrorIs(t, b.SetMembers(20), ErrNoMembers, "an empty board decides nothing, ever")
	uassert.ErrorIs(t, b.SetMembers(20, carol, address("bogus")), ErrBadAddress)
	uassert.Equal(t, 2, b.MemberCount(), "a refused call changes nothing")

	urequire.NoError(t, b.SetMembers(20, bob, carol, carol))
	uassert.Equal(t, 2, b.MemberCount(), "duplicates collapse")
	uassert.False(t, b.IsMember(alice))
	uassert.Equal(t, int64(0), b.JoinedAt(bob), "a member who stays keeps their seniority")
	uassert.Equal(t, int64(20), b.JoinedAt(carol))

	yes, _ := b.Standing(r)
	uassert.Equal(t, 0, yes, "the replaced member's ballot stops counting")
}

func TestCapRefusesOversizedRequests(t *testing.T) {
	p := prog()
	uassert.ErrorIs(t, p.SetCap(-1), ErrBadCap)

	_, err := p.Apply(dave, "big", "", "a:300,b:300", 1)
	urequire.NoError(t, err, "zero means no cap")

	urequire.NoError(t, p.SetCap(500))
	_, err = p.Apply(dave, "too big", "", "a:300,b:201", 2)
	uassert.ErrorIs(t, err, ErrOverCap, "the cap is on the whole request, not per milestone")
	_, err = p.ApplyFor(alice, dave, "empty account", "too big", "", "a:501", 3)
	uassert.ErrorIs(t, err, ErrOverCap)
	r, err := p.Apply(dave, "fits", "", "a:200,b:300", 4)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(500), r.Total())
	uassert.Equal(t, 2, p.Board.Size(), "refused requests are not filed")
}

// approvedWithProof is a dave request for 100 then 400, approved by the
// three-member fixture, with a proof under review for its first milestone.
func approvedWithProof(t *testing.T, p *Program) *Request {
	t.Helper()
	r, err := p.Apply(dave, "Port the thing", "", "design:100,ship:400", 10)
	urequire.NoError(t, err)
	urequire.NoError(t, errOf(p.Board.Vote(alice, r.ID, true, "", 11)))
	urequire.NoError(t, errOf(p.Board.Vote(bob, r.ID, true, "", 12)))
	urequire.NoError(t, p.Board.SubmitProof(dave, r.ID, 0, Proof{Kind: "url", Ref: "https://x", Height: 13}))
	return r
}

func TestPausedProgramPaysNothing(t *testing.T) {
	p := prog()
	r := approvedWithProof(t, p)
	p.Paused = true

	_, _, err := p.Review(alice, r.ID, 0, true, "", 14, 1000)
	urequire.NoError(t, err, "a ballot that does not release anything is still recorded")
	out, pay, err := p.Review(bob, r.ID, 0, true, "", 15, 1000)
	uassert.ErrorIs(t, err, ErrPaused)
	uassert.Equal(t, "under review", out.String())
	uassert.True(t, pay == nil)
	uassert.Equal(t, 1, len(r.Milestones[0].Current().Reviews), "the refused verdict left no ballot")
	uassert.False(t, r.Milestones[0].Released)
	uassert.Equal(t, 0, len(p.Payments))

	p.Paused = false
	out, pay, err = p.Review(bob, r.ID, 0, true, "", 16, 1000)
	urequire.NoError(t, err)
	uassert.Equal(t, "accepted", out.String())
	urequire.True(t, pay != nil)
	uassert.Equal(t, int64(100), pay.Amount)
}

func TestSweepIsRecorded(t *testing.T) {
	p := prog()
	_, err := p.Sweep(mallory, 0, 1, 1000)
	uassert.ErrorIs(t, err, ErrNothingSent)
	_, err = p.Sweep(address(""), 10, 1, 1000)
	uassert.ErrorIs(t, err, ErrBadAddress)
	_, err = p.Sweep(mallory, 1001, 1, 1000)
	uassert.ErrorIs(t, err, ErrUnderfunded)
	uassert.Equal(t, 0, len(p.Sweeps))

	s, err := p.Sweep(mallory, 600, 2, 1000)
	urequire.NoError(t, err)
	uassert.Equal(t, mallory.String(), s.To.String())
	uassert.Equal(t, int64(600), s.Amount)
	uassert.Equal(t, int64(2), s.Height)
	uassert.Equal(t, int64(600), p.Swept())
	uassert.Equal(t, int64(0), p.Disbursed(), "a sweep is not a grant")
}

// Amounts are checked one at a time against the cap, so two huge milestones
// cannot wrap the total around int64 and come in under it.
func TestCapCannotBeWrapped(t *testing.T) {
	p := prog()
	urequire.NoError(t, p.SetCap(500))
	_, err := p.Apply(dave, "wrap", "", "a:9223372036854775807,b:9223372036854775807", 1)
	uassert.ErrorIs(t, err, ErrOverCap)
	_, err = p.Apply(dave, "wrap", "", "a:400,b:9223372036854775807", 1)
	uassert.ErrorIs(t, err, ErrOverCap)
}

// A funded board can be deployed before anyone is seated on it; its page says
// so in a sentence rather than as a table with no rows.
func TestEmptyBoardRendersASentence(t *testing.T) {
	p := NewProgram("ugnot")
	page := Renderer{Program: p, Title: "t", Link: "/r/x"}.Render("")
	uassert.True(t, strings.Contains(page, "Nobody sits on this board"))
	uassert.False(t, strings.Contains(page, "| Member |"))
}
