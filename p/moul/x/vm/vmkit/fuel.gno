package vmkit

// Unmetered is the fuel value that disables the budget: a [Meter] built with
// it never reports exhaustion. It exists so a benchmark can measure the
// dispatch loop without the meter in it, and so a trusted caller can run a
// program to completion in one slice. Gas remains the real backstop.
const Unmetered int64 = -1

// Meter is a fuel budget being spent. It allocates nothing after
// construction, because it sits in the hot path of every guest instruction.
type Meter struct {
	budget int64 // Unmetered, or the number of units this slice may spend
	used   int64
}

// NewMeter returns a meter good for `budget` units, or an unmetered one when
// budget is [Unmetered]. A budget of zero is a meter with nothing to spend,
// which is a legitimate way to ask "is this instance still runnable".
func NewMeter(budget int64) *Meter {
	if budget < 0 {
		budget = Unmetered
	}
	return &Meter{budget: budget}
}

// Charge spends n units and reports whether they were available. On false
// nothing is spent, so the caller can stop before executing the instruction
// it could not pay for. That ordering is what makes a resumed machine
// re-execute exactly the instruction it stopped at, and no other.
func (m *Meter) Charge(n int64) bool {
	if m.budget == Unmetered {
		m.used += n
		return true
	}
	if m.used+n > m.budget {
		return false
	}
	m.used += n
	return true
}

// Used reports how much fuel has been spent.
func (m *Meter) Used() int64 { return m.used }

// Remaining reports what is left, or [Unmetered].
func (m *Meter) Remaining() int64 {
	if m.budget == Unmetered {
		return Unmetered
	}
	return m.budget - m.used
}

// Exhausted reports whether the next single unit would fail.
func (m *Meter) Exhausted() bool { return !m.affordable(1) }

func (m *Meter) affordable(n int64) bool {
	return m.budget == Unmetered || m.used+n <= m.budget
}
