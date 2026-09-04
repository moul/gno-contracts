package udao

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// stubConstraint is a Constraint whose verdict is fixed at construction.
type stubConstraint struct {
	ok     bool
	reason string
	desc   string
}

func (c stubConstraint) Validate() (bool, string) { return c.ok, c.reason }
func (c stubConstraint) Description() string      { return c.desc }

// stubProposal is a Proposal carrying an arbitrary constraint list.
type stubProposal struct {
	title, body string
	constraints []Constraint
}

func (p stubProposal) Title() string             { return p.title }
func (p stubProposal) Body() string              { return p.body }
func (p stubProposal) Constraints() []Constraint { return p.constraints }

func TestValidateConstraintsAllMet(t *testing.T) {
	p := stubProposal{constraints: []Constraint{
		stubConstraint{ok: true},
		stubConstraint{ok: true},
	}}

	ok, reasons := ValidateConstraints(p)
	uassert.True(t, ok, "every constraint met")
	uassert.Equal(t, 0, len(reasons))
}

func TestValidateConstraintsNoConstraints(t *testing.T) {
	// A proposal with no constraints is vacuously valid.
	ok, reasons := ValidateConstraints(stubProposal{})
	uassert.True(t, ok, "no constraints means nothing unmet")
	uassert.Equal(t, 0, len(reasons))
}

func TestValidateConstraintsCollectsEveryFailure(t *testing.T) {
	p := stubProposal{constraints: []Constraint{
		stubConstraint{ok: false, reason: "quorum not reached"},
		stubConstraint{ok: true, reason: "ignored when valid"},
		stubConstraint{ok: false, reason: "voting still open"},
	}}

	ok, reasons := ValidateConstraints(p)
	uassert.False(t, ok, "one unmet constraint invalidates the proposal")
	// It reports *all* failures, not just the first, and in order.
	uassert.Equal(t, 2, len(reasons))
	uassert.Equal(t, "quorum not reached", reasons[0])
	uassert.Equal(t, "voting still open", reasons[1])
}

func TestValidateConstraintsIgnoresReasonWhenValid(t *testing.T) {
	p := stubProposal{constraints: []Constraint{
		stubConstraint{ok: true, reason: "should not be collected"},
	}}

	ok, reasons := ValidateConstraints(p)
	uassert.True(t, ok)
	uassert.Equal(t, 0, len(reasons))
}

// TestProposalStateValues pins the iota block: these states are likely to be
// persisted or compared numerically, so inserting one in the middle is breaking.
func TestProposalStateValues(t *testing.T) {
	cases := []struct {
		name string
		got  ProposalState
		want int
	}{
		{"Pending", Pending, 0},
		{"Active", Active, 1},
		{"Passed", Passed, 2},
		{"Rejected", Rejected, 3},
		{"Executed", Executed, 4},
		{"Expired", Expired, 5},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, int(c.got), c.name)
	}
}

// TestProposalStatusZeroValue documents that a zero ProposalStatus reads as a
// Pending proposal with no recorded votes.
func TestProposalStatusZeroValue(t *testing.T) {
	var s ProposalStatus
	uassert.Equal(t, int(Pending), int(s.State))
	uassert.True(t, s.YeaPercentage == 0.0, "no yea votes recorded")
	uassert.True(t, s.NayPercentage == 0.0, "no nay votes recorded")
	uassert.True(t, s.NonVoterPercentage == 0.0, "no non-voters recorded")
}
