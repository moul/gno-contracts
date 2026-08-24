// Package timelock is a simplified port of OpenZeppelin's TimelockController.
//
// Operations are scheduled with a delay (measured in blocks). A scheduled
// operation becomes executable only once the chain height reaches the
// operation's ready height. Until then it can be cancelled by anyone (this
// simplified port omits role-based access control). Once executed or
// cancelled, an operation is terminal.
//
// Solidity mapping:
//   - block.number      -> runtime.ChainHeight()
//   - msg.sender        -> unsafe.PreviousRealm().Address()
//   - require(...)       -> panic(...)
//   - events            -> chain.Emit(...)
//   - mapping(id => op) -> avl.Tree keyed by zero-padded id
package timelock

import (
	"strconv"

	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
)

// State labels for an operation.
const (
	StatePending   = "Pending"   // scheduled, not yet ready
	StateReady     = "Ready"     // ready height reached, awaiting execution
	StateExecuted  = "Executed"  // terminal
	StateCancelled = "Cancelled" // terminal
)

// Operation is a single scheduled action.
type Operation struct {
	ID          int
	Action      string
	Proposer    address
	Scheduled   int64 // chain height at scheduling
	ReadyHeight int64 // executable once ChainHeight() >= ReadyHeight
	Done        bool  // executed
	Cancelled   bool
}

var (
	ops    = avl.NewTree() // key: paddedKey(id) -> *Operation
	nextID = 1
)

// Schedule registers a new operation to run after delayBlocks blocks and
// returns its id. delayBlocks must be >= 0.
func Schedule(cur realm, action string, delayBlocks int) int {
	if action == "" {
		panic("timelock: empty action")
	}
	if delayBlocks < 0 {
		panic("timelock: negative delay")
	}

	h := runtime.ChainHeight()
	id := nextID
	nextID++

	op := &Operation{
		ID:          id,
		Action:      action,
		Proposer:    unsafe.PreviousRealm().Address(),
		Scheduled:   h,
		ReadyHeight: h + int64(delayBlocks),
	}
	ops.Set(paddedKey(id), op)

	chain.Emit("Scheduled",
		"id", strconv.Itoa(id),
		"action", action,
		"readyHeight", strconv.FormatInt(op.ReadyHeight, 10),
	)
	return id
}

// Execute runs a ready operation. It panics if the operation is unknown,
// already terminal, or not yet ready.
func Execute(cur realm, id int) {
	op := mustGet(id)
	if op.Done {
		panic("timelock: already executed")
	}
	if op.Cancelled {
		panic("timelock: operation cancelled")
	}
	if runtime.ChainHeight() < op.ReadyHeight {
		panic("timelock: operation not ready")
	}
	op.Done = true

	chain.Emit("Executed", "id", strconv.Itoa(id), "action", op.Action)
}

// Cancel drops a pending or ready operation before it executes. It panics if
// the operation is unknown or already terminal.
func Cancel(cur realm, id int) {
	op := mustGet(id)
	if op.Done {
		panic("timelock: already executed")
	}
	if op.Cancelled {
		panic("timelock: already cancelled")
	}
	op.Cancelled = true

	chain.Emit("Cancelled", "id", strconv.Itoa(id), "action", op.Action)
}

// mustGet returns the operation or panics if absent.
func mustGet(id int) *Operation {
	v := ops.Get(paddedKey(id))
	if v == nil {
		panic("timelock: unknown operation")
	}
	return v.(*Operation)
}

// --- pure/read-only helpers (safe to unit-test) ---

// paddedKey returns a fixed-width, lexicographically sortable key for an id so
// avl iteration yields operations in id order.
func paddedKey(id int) string {
	s := strconv.Itoa(id)
	for len(s) < 12 {
		s = "0" + s
	}
	return s
}

// StateOf returns the display state of op at the given chain height.
func StateOf(op *Operation, height int64) string {
	switch {
	case op.Cancelled:
		return StateCancelled
	case op.Done:
		return StateExecuted
	case height >= op.ReadyHeight:
		return StateReady
	default:
		return StatePending
	}
}

// BlocksRemaining returns how many blocks remain before op is ready (0 if
// already ready or past).
func BlocksRemaining(op *Operation, height int64) int64 {
	if height >= op.ReadyHeight {
		return 0
	}
	return op.ReadyHeight - height
}

// Render implements the standard realm markdown view.
func Render(path string) string {
	h := runtime.ChainHeight()
	out := "# Timelock Controller\n\n"
	out += ufmt.Sprintf("Current chain height: **%d**\n\n", h)

	if ops.Size() == 0 {
		out += "_No operations scheduled yet._\n\n"
		out += "Call `Schedule(action, delayBlocks)` to queue one.\n"
		return out
	}

	out += ufmt.Sprintf("Total operations: **%d**\n\n", ops.Size())
	out += "| ID | Action | State | Ready @ | Blocks left | Proposer |\n"
	out += "|---:|--------|-------|--------:|------------:|----------|\n"

	ops.Iterate("", "", func(_ string, v any) bool {
		op := v.(*Operation)
		state := StateOf(op, h)
		left := BlocksRemaining(op, h)
		out += ufmt.Sprintf("| %d | %s | %s | %d | %d | %s |\n",
			op.ID, op.Action, state, op.ReadyHeight, left, op.Proposer.String())
		return false
	})
	return out
}
