// Package governor is a simplified on-chain governance realm inspired by
// OpenZeppelin's Governor. Anyone may open a proposal; every address gets a
// single equally-weighted vote (1 address = 1 vote); a proposal succeeds when
// its voting deadline has passed and the "for" tally strictly beats "against".
package governor

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/avl/v0"
)

// votingPeriod is the number of blocks a proposal stays open for voting.
const votingPeriod = int64(100)

// Vote support values.
const (
	VoteAgainst = 0
	VoteFor     = 1
	VoteAbstain = 2
)

// Proposal state values.
const (
	StateActive    = "Active"
	StateSucceeded = "Succeeded"
	StateDefeated  = "Defeated"
	StateExecuted  = "Executed"
)

// Proposal is a single governance proposal. It carries no ID field: the id
// belongs to the store, which hands it back on lookup and iteration.
type Proposal struct {
	Proposer       address
	Description    string
	SnapshotHeight int64
	Deadline       int64
	For            int64
	Against        int64
	Abstain        int64
	Executed       bool
	votes          *avl.Tree // voter address (string) -> support (int)
}

// proposals assigns the proposal ids. v0 kept its own nextID plus an idKey()
// that zero-padded to width 12, which stopped ordering Render past 10^12, and
// its own totalCount, which the store's LastID already answers.
var proposals = store.Named("governor: proposal")

// Propose opens a new proposal and returns its id. The snapshot height and
// deadline are recorded from the current chain height.
func Propose(cur realm, description string) int64 {
	if strings.TrimSpace(description) == "" {
		panic("governor: empty description")
	}
	proposer := unsafe.PreviousRealm().Address()
	h := runtime.ChainHeight()
	p := &Proposal{
		Proposer:       proposer,
		Description:    description,
		SnapshotHeight: h,
		Deadline:       h + votingPeriod,
		votes:          avl.NewTree(),
	}
	id := int64(proposals.Add(p))

	chain.Emit(
		"ProposalCreated",
		"id", strconv.FormatInt(id, 10),
		"proposer", proposer.String(),
		"deadline", strconv.FormatInt(p.Deadline, 10),
	)
	return id
}

// CastVote records one vote for the caller on proposal id. support is
// 0=against, 1=for, 2=abstain. One address may vote at most once per proposal,
// and voting is only allowed while the proposal is Active.
func CastVote(cur realm, id int64, support int) {
	p := mustGet(id)
	if computeState(p, runtime.ChainHeight()) != StateActive {
		panic("governor: voting closed")
	}
	if support < VoteAgainst || support > VoteAbstain {
		panic("governor: invalid support value")
	}
	voter := unsafe.PreviousRealm().Address()
	if p.votes.Has(voter.String()) {
		panic("governor: already voted")
	}
	p.votes.Set(voter.String(), support)

	switch support {
	case VoteFor:
		p.For++
	case VoteAgainst:
		p.Against++
	default:
		p.Abstain++
	}

	chain.Emit(
		"VoteCast",
		"id", strconv.FormatInt(id, 10),
		"voter", voter.String(),
		"support", strconv.Itoa(support),
	)
}

// Execute marks a Succeeded proposal as executed. It panics unless the
// proposal has reached the Succeeded state.
func Execute(cur realm, id int64) {
	p := mustGet(id)
	if computeState(p, runtime.ChainHeight()) != StateSucceeded {
		panic("governor: proposal not in Succeeded state")
	}
	p.Executed = true
	chain.Emit("ProposalExecuted", "id", strconv.FormatInt(id, 10))
}

// State returns the current lifecycle state of proposal id.
func State(id int64) string {
	return computeState(mustGet(id), runtime.ChainHeight())
}

// computeState is the pure state machine: it decides the state of p at chain
// height h. Kept free of globals so it is unit-testable.
func computeState(p *Proposal, h int64) string {
	if p.Executed {
		return StateExecuted
	}
	if h < p.Deadline {
		return StateActive
	}
	if p.For > p.Against {
		return StateSucceeded
	}
	return StateDefeated
}

func mustGet(id int64) *Proposal {
	return proposals.MustGet(store.ID(id)).(*Proposal)
}

// bar renders a proportional ▓░ progress bar of fixed width.
func bar(value, total int64, width int) string {
	if width <= 0 {
		return ""
	}
	filled := 0
	if total > 0 {
		filled = int((value*int64(width) + total/2) / total)
		if filled > width {
			filled = width
		}
	}
	return strings.Repeat("▓", filled) + strings.Repeat("░", width-filled)
}

// Render lists all proposals with their tallies and states as Markdown.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# 🏛️ Governor\n\n")
	b.WriteString("Simplified on-chain governance — 1 address = 1 vote, ")
	b.WriteString("voting period of " + strconv.FormatInt(votingPeriod, 10) + " blocks.\n\n")

	h := runtime.ChainHeight()
	b.WriteString("Current chain height: **" + strconv.FormatInt(h, 10) + "**\n\n")

	if proposals.Len() == 0 {
		b.WriteString("_No proposals yet. Call `Propose` to create one._\n")
		return b.String()
	}

	b.WriteString("Total proposals: **" + proposals.LastID().String() + "**\n\n")

	proposals.Each(func(id store.ID, v any) {
		p := v.(*Proposal)
		state := computeState(p, h)
		total := p.For + p.Against + p.Abstain

		b.WriteString("---\n\n")
		b.WriteString("## #" + id.String() + " · " + state + "\n\n")
		b.WriteString("> " + p.Description + "\n\n")
		b.WriteString("- Proposer: `" + p.Proposer.String() + "`\n")
		b.WriteString("- Snapshot height: " + strconv.FormatInt(p.SnapshotHeight, 10) + "\n")
		b.WriteString("- Deadline height: " + strconv.FormatInt(p.Deadline, 10))
		if state == StateActive {
			b.WriteString(" (" + strconv.FormatInt(p.Deadline-h, 10) + " blocks left)")
		}
		b.WriteString("\n\n")

		b.WriteString("| Choice | Votes | Tally |\n")
		b.WriteString("|---|---|---|\n")
		b.WriteString("| For | " + strconv.FormatInt(p.For, 10) + " | `" + bar(p.For, total, 20) + "` |\n")
		b.WriteString("| Against | " + strconv.FormatInt(p.Against, 10) + " | `" + bar(p.Against, total, 20) + "` |\n")
		b.WriteString("| Abstain | " + strconv.FormatInt(p.Abstain, 10) + " | `" + bar(p.Abstain, total, 20) + "` |\n\n")
	})

	return b.String()
}
