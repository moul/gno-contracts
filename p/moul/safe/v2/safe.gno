// Package safe is inspired by Gnosis Safe
package safe

import (
	"chain/runtime/unsafe"
)

//  Gnosis safe style using this with threshold
// : affMember + update threshold at the same time

type Safe interface {
	Name() string
	Members() []address
	Threshold() uint
	Size() uint
	NextProposal() Proposal
	UpcomingProposals(page uint) (props []Proposal, total uint)
	PreviousProposals(page uint) (props []Proposal, total uint)
	// balances (native, grc20, grc721)

	ProposeAddingMember(addr address, newThreshold uint) (prop Proposal, err error)
	ProposeRemovingMember(addr address, newThreshold uint) (prop Proposal, err error)
	ProposeUpdatingThreshold(newThreshold uint) (prop Proposal, err error)
	// ProposeClosure(cl func()) (prop Proposal, err error)
	// ProposeBankXXX()
	// ProposeGRC20XXX()
	// ProposeGRC721XXX()

	GetProposal(id uint) Proposal
	ApproveProposal(p Proposal) error
	ExecuteProposal(p Proposal) error
	CancelProposal(p Proposal) error // XXX: should be ProposeToCancel?

	Render(path string) string
}

type Proposal interface {
	ID() uint
	Active() bool
	Executed() bool
	Voters() []address
}

func NewSafe() Safe {
	caller := unsafe.PreviousRealm().Address()
	return safe{
		members:   []address{caller},
		threshold: 1,
		prevProps: []Proposal{},
		nextProps: []Proposal{},
	}
}

type safe struct {
	name      string
	members   []address // member addresses
	threshold uint
	prevProps []Proposal // executed/cancelled proposals
	nextProps []Proposal // upcoming proposals
}

func (s safe) String() string { panic("not implemented") }

func (s safe) Name() string        { return s.name }
func (s safe) Members() []address  { return s.members }
func (s safe) Threshold() uint     { return s.threshold }
func (s safe) Size() uint          { return uint(len(s.members)) }
func (s safe) NextProposal() Proposal { panic("not implemented") }

func (s safe) UpcomingProposals(page uint) (props []Proposal, total uint) {
	panic("not implemented")
}

func (s safe) PreviousProposals(page uint) (props []Proposal, total uint) {
	panic("not implemented")
}

func (s safe) ProposeAddingMember(addr address, newThreshold uint) (prop Proposal, err error) {
	panic("not implemented")
}

func (s safe) ProposeRemovingMember(addr address, newThreshold uint) (prop Proposal, err error) {
	panic("not implemented")
}

func (s safe) ProposeUpdatingThreshold(newThreshold uint) (prop Proposal, err error) {
	panic("not implemented")
}

func (s safe) GetProposal(id uint) Proposal   { panic("not implemented") }
func (s safe) ApproveProposal(p Proposal) error { panic("not implemented") }
func (s safe) ExecuteProposal(p Proposal) error { panic("not implemented") }
func (s safe) CancelProposal(p Proposal) error  { panic("not implemented") }
func (s safe) Render(path string) string        { panic("not implemented") }

type proposal struct{}

func (p proposal) String() string { panic("not implemented") }
