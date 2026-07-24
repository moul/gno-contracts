// Package multisig implements an M-of-N approval multisig realm.
//
// It is a port of the classic Solidity multisig idea: a fixed set of owners
// is configured once, any owner may create a proposal, owners approve it, and
// once the number of distinct approvals reaches the threshold the proposal is
// marked "Executed". This realm tracks approvals only — it does not move funds.
package multisig

import (
	"errors"
	"strconv"
	"strings"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// State of a single proposal.
type stateKind int

const (
	statePending stateKind = iota
	stateExecuted
)

func (s stateKind) String() string {
	if s == stateExecuted {
		return "Executed"
	}
	return "Pending"
}

// proposal is a single approval request.
type proposal struct {
	id          int
	description string
	proposer    address
	approvals   *avl.Tree // owner address string -> struct{}{}, distinct approvers
	state       stateKind
}

// Package-level persistent state.
var (
	owners      *avl.Tree // owner address string -> struct{}{}
	ownerCount  int
	threshold   int
	initialized bool

	proposals   *avl.Tree // decimal id string -> *proposal
	nextID      int
)

var (
	errAlreadyInit = errors.New("multisig: already initialized")
	errNotInit     = errors.New("multisig: not initialized")
	errBadThreshold = errors.New("multisig: threshold must be between 1 and number of owners")
	errNoOwners    = errors.New("multisig: at least one owner required")
	errNotOwner    = errors.New("multisig: caller is not an owner")
	errNoProposal  = errors.New("multisig: proposal not found")
	errDupApproval = errors.New("multisig: caller already approved this proposal")
	errExecuted    = errors.New("multisig: proposal already executed")
)

func init() {
	owners = avl.NewTree()
	proposals = avl.NewTree()
}

// caller returns the address of the realm/user that called into this realm.
func caller() address {
	return unsafe.PreviousRealm().Address()
}

func isOwner(a address) bool {
	return owners.Has(a.String())
}

// Setup configures the multisig exactly once. owners is a comma-separated list
// of bech32 addresses; threshold is the number of approvals required to execute
// a proposal. It panics (cross-realm abort) on invalid input or if already set.
func Setup(cur realm, ownersCSV string, thresholdN int) {
	if initialized {
		panic(errAlreadyInit)
	}

	parts := strings.Split(ownersCSV, ",")
	count := 0
	for _, p := range parts {
		a := strings.TrimSpace(p)
		if a == "" {
			continue
		}
		addr := address(a)
		if owners.Has(addr.String()) {
			continue // dedupe
		}
		owners.Set(addr.String(), struct{}{})
		count++
	}
	if count == 0 {
		panic(errNoOwners)
	}
	if thresholdN < 1 || thresholdN > count {
		panic(errBadThreshold)
	}

	ownerCount = count
	threshold = thresholdN
	initialized = true

	chain.Emit("Setup", "owners", strconv.Itoa(count), "threshold", strconv.Itoa(thresholdN))
}

// Propose creates a new proposal authored by an owner and returns its id.
func Propose(cur realm, description string) int {
	if !initialized {
		panic(errNotInit)
	}
	c := caller()
	if !isOwner(c) {
		panic(errNotOwner)
	}

	id := nextID
	nextID++

	p := &proposal{
		id:          id,
		description: description,
		proposer:    c,
		approvals:   avl.NewTree(),
		state:       statePending,
	}
	proposals.Set(strconv.Itoa(id), p)

	chain.Emit("Propose", "id", strconv.Itoa(id), "proposer", c.String())
	return id
}

// Approve records an owner's approval for a proposal. When the count of distinct
// approvals reaches the threshold, the proposal becomes Executed.
func Approve(cur realm, id int) {
	if !initialized {
		panic(errNotInit)
	}
	c := caller()
	if !isOwner(c) {
		panic(errNotOwner)
	}

	v, ok := proposals.Get(strconv.Itoa(id))
	if !ok {
		panic(errNoProposal)
	}
	p := v.(*proposal)
	if p.state == stateExecuted {
		panic(errExecuted)
	}
	if p.approvals.Has(c.String()) {
		panic(errDupApproval)
	}

	p.approvals.Set(c.String(), struct{}{})
	chain.Emit("Approve", "id", strconv.Itoa(id), "owner", c.String(), "approvals", strconv.Itoa(p.approvals.Size()))

	if p.approvals.Size() >= threshold {
		p.state = stateExecuted
		chain.Emit("Executed", "id", strconv.Itoa(id))
	}
}

// Render returns a Markdown view of the multisig configuration and proposals.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# M-of-N Multisig\n\n")

	if !initialized {
		b.WriteString("_Not initialized. Call `Setup(owners, threshold)` once._\n")
		return b.String()
	}

	b.WriteString("**Threshold:** ")
	b.WriteString(strconv.Itoa(threshold))
	b.WriteString(" of ")
	b.WriteString(strconv.Itoa(ownerCount))
	b.WriteString("\n\n## Owners\n\n")
	owners.Iterate("", "", func(key string, _ interface{}) bool {
		b.WriteString("- `")
		b.WriteString(key)
		b.WriteString("`\n")
		return false
	})

	b.WriteString("\n## Proposals\n\n")
	if proposals.Size() == 0 {
		b.WriteString("_No proposals yet._\n")
		return b.String()
	}

	b.WriteString("| ID | Description | Proposer | Approvals | State |\n")
	b.WriteString("|----|-------------|----------|-----------|-------|\n")
	proposals.Iterate("", "", func(_ string, v interface{}) bool {
		p := v.(*proposal)
		b.WriteString("| ")
		b.WriteString(strconv.Itoa(p.id))
		b.WriteString(" | ")
		b.WriteString(p.description)
		b.WriteString(" | `")
		b.WriteString(p.proposer.String())
		b.WriteString("` | ")
		b.WriteString(strconv.Itoa(p.approvals.Size()))
		b.WriteString("/")
		b.WriteString(strconv.Itoa(threshold))
		b.WriteString(" | ")
		b.WriteString(p.state.String())
		b.WriteString(" |\n")
		return false
	})

	return b.String()
}
