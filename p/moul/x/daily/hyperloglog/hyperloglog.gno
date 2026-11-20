// Package hyperloglog estimates how many DISTINCT elements a stream contained,
// in a fixed amount of memory, as a pure, reusable package.
//
// Counting unique anything on chain is normally a storage question rather than
// an arithmetic one: a set of addresses costs one object per address and grows
// with whatever users feed it, which is an unbounded storage bill driven by
// somebody else's behaviour. A HyperLogLog answers "how many were there" out
// of a FIXED array of small registers, sized once and never grown. At the
// default precision that is 1,024 bytes, whether the stream held ten elements
// or ten million.
//
// It is the third member of a family this repository already carries, and the
// three answer different questions:
//
//   - membership, "have I seen this one": a Bloom filter,
//     [r/moul/x/daily/bloomfilter](/r/moul/x/daily/bloomfilter/v0)
//   - frequency, "how often did this one arrive":
//     [p/moul/x/daily/countminsketch](/p/moul/x/daily/countminsketch/v0)
//   - cardinality, "how many different ones were there": this package
//
// None of the three can answer another's question, and this one is the most
// easily misread: a sketch that has counted a million elements cannot tell you
// whether it has seen YOU. It keeps no elements at all, only the length of the
// longest run of leading zeros each register was ever shown, which is why it
// fits in a kilobyte and why nothing can be taken back out.
//
// How it works, in one paragraph. Hash the element; the top p bits pick one of
// m = 2^p registers; the remaining bits supply a run of leading zeros. A run of
// k zeros turns up roughly once in 2^k elements, so the longest run a register
// ever saw is evidence about how many elements that register was shown. One
// register is a terrible estimator, so m of them are averaged harmonically and
// scaled by a constant that corrects the bias. The standard error is
// 1.04/sqrt(m), and it does not depend on the cardinality: the same 1,024 bytes
// are about as wrong at a thousand elements as at a billion.
//
// Two things make it worth more than its accuracy. It is MERGEABLE: register-
// wise maximum, so shards counted separately combine into the union with the
// overlap counted once, which no exact counter can do without shipping its
// elements. And it is a plain []uint8, so a realm can store it, snapshot it and
// restore it (Snapshot, FromSnapshot) without an object per element.
//
// Determinism: every number below comes out of integer hashing and gno's own
// software float implementation, both of which are interpreted gno source and
// therefore identical on every node. Nothing reads a map, the clock or an
// address.
//
// A live demo of this package is at
// [r/moul/x/daily/hyperloglogdemo](/r/moul/x/daily/hyperloglogdemo/v0).
package hyperloglog

import (
	"errors"
	"math"
)

const (
	// MinPrecision is 4 because the bias constants below are only defined
	// from m=16 up.
	MinPrecision = 4
	// MaxPrecision is 16, which is 65,536 registers and 64 KiB. Past that the
	// accuracy gained is a fraction of a percent and the storage deposit is
	// not.
	MaxPrecision = 16
	// DefaultPrecision is 10: 1,024 registers, 1 KiB, a standard error of
	// about 3.25%. It is the size at which the footprint is still an
	// afterthought for a realm.
	DefaultPrecision = 10
)

var (
	// ErrBadPrecision is returned for a precision outside [MinPrecision, MaxPrecision].
	ErrBadPrecision = errors.New("hyperloglog: precision out of range")
	// ErrPrecisionMismatch is returned by Merge for sketches of different sizes.
	ErrPrecisionMismatch = errors.New("hyperloglog: precision mismatch")
	// ErrNilSketch is returned by Merge for a nil argument.
	ErrNilSketch = errors.New("hyperloglog: nil sketch")
	// ErrBadSnapshot is returned by FromSnapshot when the register count does
	// not match the precision, or when a register holds a zero-run no Add at
	// that precision could have produced.
	ErrBadSnapshot = errors.New("hyperloglog: snapshot does not match precision")
)

// Sketch is a HyperLogLog over string elements. The zero value is not usable:
// build one with New, NewDefault or FromSnapshot.
//
// All of a sketch's state sits behind one pointer, so a copy of a Sketch value
// is the same sketch. Copying the fields would share the registers but not the
// Add count, and the two copies would then disagree about what they had seen.
// Clone is the way to get an independent one.
type Sketch struct {
	st *sketchState
}

type sketchState struct {
	precision int
	reg       []uint8 // m registers, each the longest zero-run seen
	limit     uint8   // the cap on a zero-run, 64 - precision
	adds      int64   // how many Add calls landed, duplicates included
}

// New returns an empty sketch with 2^precision registers.
func New(precision int) (*Sketch, error) {
	if precision < MinPrecision || precision > MaxPrecision {
		return nil, ErrBadPrecision
	}
	return &Sketch{st: &sketchState{
		precision: precision,
		reg:       make([]uint8, 1<<uint(precision)),
		limit:     uint8(64 - precision),
	}}, nil
}

// NewDefault returns an empty sketch at DefaultPrecision.
func NewDefault() *Sketch {
	s, _ := New(DefaultPrecision)
	return s
}

// FromSnapshot rebuilds a sketch from registers produced by Snapshot. Every
// register must be at most 65 - precision, the longest zero-run an Add at that
// precision can record; anything higher did not come from Snapshot and would
// skew Count without bound. The Add count is NOT carried: a restored sketch has observed nothing itself, and
// reporting somebody else's call count as its own would be a lie a realm would
// then render.
func FromSnapshot(precision int, registers []uint8) (*Sketch, error) {
	s, err := New(precision)
	if err != nil {
		return nil, err
	}
	if len(registers) != len(s.st.reg) {
		return nil, ErrBadSnapshot
	}
	for _, r := range registers {
		if r > s.st.limit+1 {
			return nil, ErrBadSnapshot
		}
	}
	copy(s.st.reg, registers)
	return s, nil
}

// Add records one element. The empty string is an element like any other.
func (s *Sketch) Add(element string) {
	h := hash64(element)
	idx := h >> uint(64-s.st.precision)
	// The register bits are shifted out before the zero-run is measured, so
	// the same element can never contribute its index to its own estimate.
	r := rho(h<<uint(s.st.precision), s.st.limit)
	if r > s.st.reg[idx] {
		s.st.reg[idx] = r
	}
	s.st.adds++
}

// AddAll records every element of a slice. Exactly equivalent to the loop,
// and here so a caller does not write one.
func (s *Sketch) AddAll(elements []string) {
	for _, e := range elements {
		s.Add(e)
	}
}

// Count estimates the number of distinct elements added.
//
// Two estimators, and the switch between them is where naive implementations
// go wrong. Above a few times m the harmonic mean of the registers is used.
// Below it most registers are still empty, the harmonic mean is badly biased,
// and the right answer comes from the number of registers that are still zero:
// that is linear counting, and in the small range it is not an approximation
// worth arguing with, it is exact until two elements collide.
//
// The large-range correction found in the original paper is absent on purpose.
// It repairs 32-bit hash exhaustion, and the hash here is 64-bit: collisions
// start to matter somewhere past 10^18 elements, which is not a number a chain
// is going to reach.
func (s *Sketch) Count() int64 {
	estimate, m, zeros := s.raw()
	if linearRange(estimate, m, zeros) {
		estimate = m * math.Log(m/float64(zeros))
	}
	return int64(estimate + 0.5)
}

// LinearCounting reports whether Count is currently answering from linear
// counting, the small-range estimator, rather than from the harmonic mean. It
// applies the exact switch Count applies, so a caller labelling the answer
// cannot pick a threshold of its own that disagrees with it.
func (s *Sketch) LinearCounting() bool {
	return linearRange(s.raw())
}

// raw is the harmonic-mean estimate before the small-range switch, with the
// register count and the number of registers still empty that the switch
// reads.
func (s *Sketch) raw() (estimate, m float64, zeros int) {
	m = float64(len(s.st.reg))
	sum := 0.0
	for _, r := range s.st.reg {
		if r == 0 {
			zeros++
		}
		sum += 1.0 / float64(uint64(1)<<uint(r))
	}
	return alpha(len(s.st.reg)) * m * m / sum, m, zeros
}

// linearRange is the switch between the two estimators: a raw estimate at or
// below 2.5m, with at least one register still empty.
func linearRange(raw, m float64, zeros int) bool {
	return raw <= 2.5*m && zeros > 0
}

// Merge folds other into s, so that s afterwards estimates the union of the
// two. This is the operation that makes the structure worth its error bars: a
// realm can keep one sketch per day, per shard or per caller and combine them
// afterwards, and an element present in both is counted once because a
// register-wise maximum has no way to count it twice.
//
// The Add counts are summed, because they are call counts rather than
// cardinalities and the union of two streams did see both.
func (s *Sketch) Merge(other *Sketch) error {
	if other == nil {
		return ErrNilSketch
	}
	if other.st.precision != s.st.precision {
		return ErrPrecisionMismatch
	}
	for i, r := range other.st.reg {
		if r > s.st.reg[i] {
			s.st.reg[i] = r
		}
	}
	s.st.adds += other.st.adds
	return nil
}

// Clone returns an independent copy.
func (s *Sketch) Clone() *Sketch {
	c := &sketchState{precision: s.st.precision, limit: s.st.limit, adds: s.st.adds}
	c.reg = make([]uint8, len(s.st.reg))
	copy(c.reg, s.st.reg)
	return &Sketch{st: c}
}

// Reset empties the sketch, keeping its precision.
func (s *Sketch) Reset() {
	for i := range s.st.reg {
		s.st.reg[i] = 0
	}
	s.st.adds = 0
}

// Snapshot returns a copy of the registers, which is the whole state. Store it
// and hand it back to FromSnapshot later. It is a copy rather than the live
// slice so that a stored snapshot does not keep changing underneath its owner.
func (s *Sketch) Snapshot() []uint8 {
	out := make([]uint8, len(s.st.reg))
	copy(out, s.st.reg)
	return out
}

// Precision returns p, the number of hash bits used to pick a register.
func (s *Sketch) Precision() int { return s.st.precision }

// Registers returns m, the number of registers.
func (s *Sketch) Registers() int { return len(s.st.reg) }

// Zeros returns how many registers are still untouched. It is the quantity
// linear counting is built on, and on its own it is a useful honesty signal: a
// sketch with no zeros left is past the small range and its answer is now an
// estimate rather than a count.
func (s *Sketch) Zeros() int {
	n := 0
	for _, r := range s.st.reg {
		if r == 0 {
			n++
		}
	}
	return n
}

// Max returns the largest zero-run any register holds. It is the single most
// influential number in the estimate, and a sketch whose Max is far above
// log2(count) has been handed an unlucky element rather than a lot of them.
func (s *Sketch) Max() uint8 {
	var top uint8
	for _, r := range s.st.reg {
		if r > top {
			top = r
		}
	}
	return top
}

// Adds returns how many Add calls landed, duplicates included. The contrast
// with Count is the point of the structure: Adds is what arrived, Count is how
// much of it was different.
func (s *Sketch) Adds() int64 { return s.st.adds }

// Bytes returns the register footprint. It is a function of the precision
// alone: the same number before and after a million elements.
func (s *Sketch) Bytes() int { return len(s.st.reg) }

// RelativeError returns the theoretical standard error, 1.04/sqrt(m). It is
// independent of the cardinality, which is the counter-intuitive part: the
// same kilobyte is about as wrong at a thousand elements as at a billion.
//
// It is one standard deviation, not a guarantee. About a third of all sketches
// are further out than this, and a caller rendering a figure should say
// "about" rather than quote it to the unit.
func (s *Sketch) RelativeError() float64 {
	return 1.04 / math.Sqrt(float64(len(s.st.reg)))
}

// alpha is the bias correction for the harmonic mean. The three small cases
// are measured constants from the original paper; the general form takes over
// from m=128 up.
func alpha(m int) float64 {
	switch m {
	case 16:
		return 0.673
	case 32:
		return 0.697
	case 64:
		return 0.709
	}
	return 0.7213 / (1 + 1.079/float64(m))
}
