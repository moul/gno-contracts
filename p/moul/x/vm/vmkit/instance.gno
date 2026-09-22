package vmkit

import (
	"errors"

	"gno.land/p/nt/avl/v0"
)

// ErrNoInstance is returned when an id names nothing.
var ErrNoInstance = errors.New("vmkit: no such instance")

// ErrBudgetExhausted is returned when an instance has already spent its total
// fuel budget, so there is nothing left to step.
var ErrBudgetExhausted = errors.New("vmkit: instance fuel budget exhausted")

// Instance is one guest program as a realm stores it: the code, the machine
// state between slices, and the accounting that survives the transaction.
//
// It holds a snapshot rather than a [Machine], on purpose. A realm keeps
// bytes; the machine is rebuilt for the slice that needs it and thrown away
// after. That is what makes the storage cost of a paused program measurable,
// which is the whole kill criterion for continuations: if resuming costs more
// than re-running, continuations are theater.
type Instance struct {
	ID    string
	Owner address
	VM    string // which guest machine the Program is for

	Program  []byte
	Snapshot []byte

	Status Status
	Trap   string

	// FuelUsed is the total across every slice run so far.
	FuelUsed int64
	// FuelBudget caps FuelUsed across the instance's whole life, or is
	// [Unmetered] for no cap.
	FuelBudget int64

	// Slices counts how many transactions have stepped this instance.
	Slices int64

	Output []byte
}

// NewInstance returns an instance ready for its first slice.
func NewInstance(id string, owner address, vm string, program []byte, budget int64) *Instance {
	if budget < 0 {
		budget = Unmetered
	}
	prog := make([]byte, len(program))
	copy(prog, program)
	return &Instance{
		ID:         id,
		Owner:      owner,
		VM:         vm,
		Program:    prog,
		Status:     Running,
		FuelBudget: budget,
	}
}

// Remaining reports the fuel left in the instance's total budget, or
// [Unmetered].
func (i *Instance) Remaining() int64 {
	if i.FuelBudget == Unmetered {
		return Unmetered
	}
	left := i.FuelBudget - i.FuelUsed
	if left < 0 {
		return 0
	}
	return left
}

// Slice returns how much fuel the next call to [Instance.Run] may spend when
// the caller asks for `want`: `want` clamped to what the budget still allows.
func (i *Instance) Slice(want int64) int64 {
	left := i.Remaining()
	if left == Unmetered {
		return want
	}
	if want == Unmetered || want > left {
		return left
	}
	return want
}

// Run steps m for one slice of at most `fuel` units and folds the result back
// into the instance: the new snapshot, the status, the fuel spent, and
// anything the guest wrote to h.
//
// m must be a fresh machine loaded from i.Program; Run restores i.Snapshot
// into it when there is one, so the caller never has to remember the order.
// The instance is left untouched when Restore fails, which means a snapshot
// that cannot be decoded costs the caller gas but never corrupts the stored
// program.
func (i *Instance) Run(m Machine, h Host, fuel int64) error {
	if i.Status.Done() && i.Status != Running {
		return ErrBudgetExhausted
	}
	if len(i.Snapshot) > 0 {
		if err := m.Restore(i.Snapshot); err != nil {
			return err
		}
	}
	slice := i.Slice(fuel)
	if slice == 0 {
		i.Status = OutOfFuel
		return ErrBudgetExhausted
	}

	used, status := m.Step(h, slice)

	i.FuelUsed += used
	i.Slices++
	i.Snapshot = m.Snapshot()
	i.Status = status
	i.Trap = TrapReason(m)
	if status == Running && i.Remaining() == 0 {
		i.Status = OutOfFuel
	}
	return nil
}

// Store is the avl-backed set of instances a realm owns, keyed by id.
type Store struct {
	tree *avl.Tree
}

// NewStore returns an empty store.
func NewStore() *Store { return &Store{tree: avl.NewTree()} }

// Set writes an instance, replacing any instance with the same id.
func (s *Store) Set(i *Instance) {
	if i == nil {
		return
	}
	s.tree.Set(i.ID, i)
}

// Get returns the instance with this id, or nil.
func (s *Store) Get(id string) *Instance {
	v := s.tree.Get(id)
	if v == nil {
		return nil
	}
	inst, ok := v.(*Instance)
	if !ok {
		return nil
	}
	return inst
}

// Remove deletes an instance and reports whether it existed.
func (s *Store) Remove(id string) bool {
	_, removed := s.tree.Remove(id)
	return removed
}

// Size returns how many instances are stored.
func (s *Store) Size() int { return s.tree.Size() }

// Iterate walks every instance in key order, stopping early when fn returns
// true.
func (s *Store) Iterate(fn func(*Instance) bool) {
	s.tree.Iterate("", "", func(_ string, v any) bool {
		inst, ok := v.(*Instance)
		if !ok {
			return false
		}
		return fn(inst)
	})
}

// ReverseIterate walks every instance in descending key order, which is how a
// realm renders newest-first when ids are zero-padded and ascending.
func (s *Store) ReverseIterate(fn func(*Instance) bool) {
	s.tree.ReverseIterate("", "", func(_ string, v any) bool {
		inst, ok := v.(*Instance)
		if !ok {
			return false
		}
		return fn(inst)
	})
}
