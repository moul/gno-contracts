// Package ballot is a Gno port of the classic Solidity "Ballot" voting
// contract from the Solidity docs. A chairperson seeds a fixed list of
// proposals and grants specific addresses the right to vote; each voter can
// either cast a direct vote or delegate their weight to another voter, and
// delegation follows a chain so a delegate who later delegates further still
// carries every accumulated weight. The winning proposal is whichever has
// the most accumulated weight at query time.
package ballot

import (
	"errors"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
)

// proposal is one of the fixed choices set up at Init time.
type proposal struct {
	name  string
	votes uint64
}

// voterInfo tracks one address's voting rights and delegation state.
type voterInfo struct {
	weight   uint64  // 0 means "no right to vote"
	voted    bool    // true once the weight has been cast (directly or delegated away)
	delegate address // set only when voted == true and this voter delegated
	vote     int     // proposal index this voter's weight ended up on, valid once tallied
}

// Package-level persistent state.
var (
	chairperson address
	initialized bool
	proposals   []proposal
	voters      *avl.Tree // address string -> *voterInfo
)

var (
	errAlreadyInit    = errors.New("ballot: already initialized")
	errNotInit        = errors.New("ballot: not initialized yet")
	errNotChairperson = errors.New("ballot: only the chairperson may do this")
	errNoProposals    = errors.New("ballot: at least one proposal name is required")
	errInvalidAddr    = errors.New("ballot: invalid address")
	errAlreadyRight   = errors.New("ballot: voter already has the right to vote")
	errAlreadyVoted   = errors.New("ballot: voter already voted")
	errNoRight        = errors.New("ballot: caller has no right to vote")
	errSelfDelegate   = errors.New("ballot: self-delegation is not allowed")
	errDelegateLoop   = errors.New("ballot: found a loop in the delegation chain")
	errDelegateNoRight = errors.New("ballot: delegate has no right to vote")
	errBadProposal    = errors.New("ballot: invalid proposal index")
)

func init() {
	voters = avl.NewTree()
}

func requireInit() {
	if !initialized {
		panic(errNotInit)
	}
}

func getOrCreateVoter(addr address) *voterInfo {
	if v := voters.Get(addr.String()); v != nil {
		return v.(*voterInfo)
	}
	v := &voterInfo{}
	voters.Set(addr.String(), v)
	return v
}

// Init configures the ballot exactly once: the caller becomes the
// chairperson (and is immediately given the right to vote), and
// proposalNamesCSV — a comma-separated list — seeds the fixed set of
// proposals. It panics if called twice or with no usable proposal names.
func Init(cur realm, proposalNamesCSV string) {
	if initialized {
		panic(errAlreadyInit)
	}

	for _, raw := range strings.Split(proposalNamesCSV, ",") {
		name := strings.TrimSpace(raw)
		if name == "" {
			continue
		}
		proposals = append(proposals, proposal{name: name})
	}
	if len(proposals) == 0 {
		panic(errNoProposals)
	}

	chairperson = cur.Previous().Address()
	voters.Set(chairperson.String(), &voterInfo{weight: 1})
	initialized = true
}

// GiveRightToVote grants voterAddr a voting weight of 1. Only the
// chairperson may call this, and only for voters who haven't voted yet.
func GiveRightToVote(cur realm, voterAddr string) {
	requireInit()
	if cur.Previous().Address() != chairperson {
		panic(errNotChairperson)
	}

	addr := address(voterAddr)
	if !addr.IsValid() {
		panic(errInvalidAddr)
	}

	v := getOrCreateVoter(addr)
	if v.voted {
		panic(errAlreadyVoted)
	}
	if v.weight != 0 {
		panic(errAlreadyRight)
	}
	v.weight = 1
}

// Delegate hands the caller's voting weight to toAddr. If toAddr has
// already voted, the weight is added directly to that proposal's tally;
// otherwise it accumulates on toAddr's own weight, ready to be cast (or
// delegated further) later. Mirrors Solidity's delegation-chain-following
// with a loop guard.
func Delegate(cur realm, toAddr string) {
	requireInit()

	sender := cur.Previous().Address()
	from := getOrCreateVoter(sender)
	if from.weight == 0 {
		panic(errNoRight)
	}
	if from.voted {
		panic(errAlreadyVoted)
	}

	to := address(toAddr)
	if !to.IsValid() {
		panic(errInvalidAddr)
	}
	if to == sender {
		panic(errSelfDelegate)
	}

	var zero address
	maxSteps := voters.Size() + 1
	for steps := 0; ; steps++ {
		v := voters.Get(to.String())
		if v == nil {
			break
		}
		next := v.(*voterInfo).delegate
		if next == zero {
			break
		}
		to = next
		if to == sender {
			panic(errDelegateLoop)
		}
		if steps > maxSteps {
			panic(errDelegateLoop)
		}
	}

	delegateVoter := getOrCreateVoter(to)
	if delegateVoter.weight == 0 {
		panic(errDelegateNoRight)
	}

	from.voted = true
	from.delegate = to

	if delegateVoter.voted {
		proposals[delegateVoter.vote].votes += from.weight
	} else {
		delegateVoter.weight += from.weight
	}
}

// Vote casts the caller's full weight for proposals[proposalIndex].
func Vote(cur realm, proposalIndex int) {
	requireInit()

	sender := cur.Previous().Address()
	v := getOrCreateVoter(sender)
	if v.weight == 0 {
		panic(errNoRight)
	}
	if v.voted {
		panic(errAlreadyVoted)
	}
	if proposalIndex < 0 || proposalIndex >= len(proposals) {
		panic(errBadProposal)
	}

	v.voted = true
	v.vote = proposalIndex
	proposals[proposalIndex].votes += v.weight
}

// WinningProposal returns the index of the proposal with the most
// accumulated weight, breaking ties in favor of the lowest index.
func WinningProposal() int {
	winner := 0
	best := uint64(0)
	for i, p := range proposals {
		if p.votes > best {
			best = p.votes
			winner = i
		}
	}
	return winner
}

// WinnerName returns the name of the current winning proposal, or "" if
// the ballot hasn't been initialized.
func WinnerName() string {
	if len(proposals) == 0 {
		return ""
	}
	return proposals[WinningProposal()].name
}

func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Ballot\n\n")

	if !initialized {
		b.WriteString("Not initialized yet. The first caller to run `Init` becomes the " +
			"chairperson and seeds the proposal list, e.g.:\n\n")
		b.WriteString("```\nInit(\"Alice,Bob,Carol\")\n```\n")
		return b.String()
	}

	b.WriteString("Chairperson: `" + chairperson.String() + "`\n\n")
	b.WriteString("| # | Proposal | Votes |\n")
	b.WriteString("|---|---|---|\n")
	for i, p := range proposals {
		b.WriteString("| " + strconv.Itoa(i) + " | " + p.name + " | " +
			strconv.FormatUint(p.votes, 10) + " |\n")
	}

	b.WriteString("\nCurrent winner: **" + WinnerName() + "** (index " +
		strconv.Itoa(WinningProposal()) + ")\n\n")
	b.WriteString("Registered voters: " + strconv.Itoa(voters.Size()) + "\n")
	return b.String()
}
