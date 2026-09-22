package vmkit

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// counter is a toy [Machine] used to test the kit itself without dragging in
// a real guest VM: it writes one byte per step and halts after `total` of
// them. Anything that works here is a property of the ABI, not of brainfuck.
type counter struct {
	total int64
	done  int64
	trap  string
}

func (c *counter) Step(h Host, fuel int64) (int64, Status) {
	m := NewMeter(fuel)
	var used int64
	for c.done < c.total {
		if !m.Charge(1) {
			return used, Running
		}
		used++
		c.done++
		h.Output([]byte{byte('a' + (c.done-1)%26)})
	}
	return used, Halted
}

func (c *counter) Snapshot() []byte {
	w := NewWriter(24)
	w.Int(c.total)
	w.Int(c.done)
	w.String(c.trap)
	return w.Out()
}

func (c *counter) Restore(b []byte) error {
	r := NewReader(b)
	total := r.Int()
	done := r.Int()
	trap := r.String()
	if err := r.Err(); err != nil {
		return err
	}
	c.total, c.done, c.trap = total, done, trap
	return nil
}

func (c *counter) Trap() string { return c.trap }

func TestStatusString(t *testing.T) {
	cases := []struct {
		s    Status
		want string
		done bool
	}{
		{Running, "running", false},
		{Halted, "halted", true},
		{Trapped, "trapped", true},
		{OutOfFuel, "out of fuel", true},
		{Status(99), "unknown", true},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, tc.s.String())
		uassert.Equal(t, tc.done, tc.s.Done())
	}
}

func TestMeterCharge(t *testing.T) {
	m := NewMeter(10)
	uassert.True(t, m.Charge(4))
	uassert.Equal(t, int64(4), m.Used())
	uassert.Equal(t, int64(6), m.Remaining())

	// A charge that does not fit spends nothing, so the caller can stop
	// before the instruction it cannot pay for.
	uassert.False(t, m.Charge(7))
	uassert.Equal(t, int64(4), m.Used())

	uassert.True(t, m.Charge(6))
	uassert.True(t, m.Exhausted())
	uassert.False(t, m.Charge(1))
}

func TestMeterUnmetered(t *testing.T) {
	m := NewMeter(Unmetered)
	uassert.True(t, m.Charge(1 << 40))
	uassert.False(t, m.Exhausted())
	uassert.Equal(t, Unmetered, m.Remaining())
}

func TestMeterZeroBudget(t *testing.T) {
	m := NewMeter(0)
	uassert.True(t, m.Exhausted())
	uassert.False(t, m.Charge(1))
	uassert.Equal(t, int64(0), m.Used())
}

func TestCodecRoundTrip(t *testing.T) {
	w := NewWriter(0)
	w.Byte(0xab)
	w.Uint32(0xdeadbeef)
	w.Uint64(0x0102030405060708)
	w.Int(-1234567)
	w.Int(0)
	w.Int(1234567)
	w.Bytes([]byte{0, 1, 2, 255})
	w.String("gno.land")

	r := NewReader(w.Out())
	uassert.Equal(t, uint64(0xab), uint64(r.Byte()))
	uassert.Equal(t, uint64(0xdeadbeef), uint64(r.Uint32()))
	uassert.Equal(t, uint64(0x0102030405060708), r.Uint64())
	uassert.Equal(t, int64(-1234567), r.Int())
	uassert.Equal(t, int64(0), r.Int())
	uassert.Equal(t, int64(1234567), r.Int())
	uassert.Equal(t, 4, len(r.Bytes()))
	uassert.Equal(t, "gno.land", r.String())
	uassert.NoError(t, r.Err())
	uassert.Equal(t, 0, r.Remaining())
}

func TestCodecIsCanonical(t *testing.T) {
	// The same state must always produce the same bytes: a snapshot is
	// consensus state, so two nodes encoding it differently is a fork.
	build := func() []byte {
		w := NewWriter(0)
		w.Int(-7)
		w.String("x")
		w.Uint32(9)
		return w.Out()
	}
	uassert.Equal(t, string(build()), string(build()))
}

func TestCodecTruncated(t *testing.T) {
	r := NewReader([]byte{1, 2})
	r.Uint64()
	uassert.ErrorIs(t, r.Err(), ErrTruncated)
	// Once latched, every later read is a zero value and the error stands.
	uassert.Equal(t, "", r.String())
	uassert.ErrorIs(t, r.Err(), ErrTruncated)
}

func TestCodecBytesAreCopied(t *testing.T) {
	w := NewWriter(0)
	w.Bytes([]byte{1, 2, 3})
	buf := w.Out()
	r := NewReader(buf)
	got := r.Bytes()
	buf[len(buf)-1] = 99 // mutate the snapshot under the reader
	uassert.Equal(t, 3, len(got))
	uassert.Equal(t, uint64(3), uint64(got[2]))
}

func TestTestHostStorage(t *testing.T) {
	h := NewTestHost()
	uassert.Equal(t, 0, len(h.Get([]byte("missing"))))

	h.Set([]byte{0, 1}, []byte("zero-prefixed"))
	h.Set([]byte("k"), []byte("v"))
	uassert.Equal(t, "zero-prefixed", string(h.Get([]byte{0, 1})))
	uassert.Equal(t, "v", string(h.Get([]byte("k"))))

	// Keys are hex so a zero byte survives, and sorted so a test can pin
	// them.
	keys := h.Keys()
	uassert.Equal(t, 2, len(keys))
	uassert.Equal(t, "0001", keys[0])
	uassert.Equal(t, "6b", keys[1])
}

func TestTestHostStorageIsCopied(t *testing.T) {
	h := NewTestHost()
	val := []byte("abc")
	h.Set([]byte("k"), val)
	val[0] = 'z'
	uassert.Equal(t, "abc", string(h.Get([]byte("k"))))

	got := h.Get([]byte("k"))
	got[0] = 'z'
	uassert.Equal(t, "abc", string(h.Get([]byte("k"))))
}

func TestTestHostSendNeedsAGrant(t *testing.T) {
	to := address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")

	h := NewTestHost()
	uassert.ErrorIs(t, h.Send(to, 100), ErrNotGranted)
	uassert.Equal(t, 0, len(h.Sends()))

	h.Grant(150)
	uassert.NoError(t, h.Send(to, 100))
	uassert.Equal(t, 1, len(h.Sends()))
	uassert.Equal(t, int64(100), h.Sends()[0].Amount)

	// The grant is a budget, not a switch.
	uassert.ErrorIs(t, h.Send(to, 100), ErrNotGranted)
	uassert.NoError(t, h.Send(to, 50))
}

func TestTestHostEventsAndInput(t *testing.T) {
	h := NewTestHost().WithInput([]byte("hi")).WithHeight(42).WithTime(1700000000)
	uassert.Equal(t, "hi", string(h.Input()))
	uassert.Equal(t, int64(42), h.Height())
	uassert.Equal(t, int64(1700000000), h.Now())

	h.Emit("run", "id", "1", "status", "halted")
	h.Emit("odd", "dangling")
	uassert.Equal(t, 2, len(h.Events()))
	uassert.Equal(t, "run id=1 status=halted", h.Events()[0])
	uassert.Equal(t, "odd", h.Events()[1]) // odd trailing element dropped
}

func TestInstanceRunsToCompletion(t *testing.T) {
	inst := NewInstance("1", address("g1x"), "counter", []byte("5"), Unmetered)
	h := NewTestHost()
	uassert.NoError(t, inst.Run(&counter{total: 5}, h, Unmetered))
	uassert.Equal(t, "halted", inst.Status.String())
	uassert.Equal(t, int64(5), inst.FuelUsed)
	uassert.Equal(t, int64(1), inst.Slices)
	uassert.Equal(t, "abcde", h.OutString())
}

func TestInstanceResumesAcrossSlices(t *testing.T) {
	// The property that makes a guest program a contract: five slices of
	// one unit must equal one slice of five.
	inst := NewInstance("1", address("g1x"), "counter", []byte("5"), Unmetered)
	h := NewTestHost()
	for i := 0; i < 5; i++ {
		// A realm holds bytes, not a machine: every slice loads a fresh
		// one from the program and lets Restore carry the state over.
		uassert.NoError(t, inst.Run(&counter{total: 5}, h, 1))
	}
	uassert.Equal(t, "halted", inst.Status.String())
	uassert.Equal(t, int64(5), inst.FuelUsed)
	uassert.Equal(t, int64(5), inst.Slices)
	uassert.Equal(t, "abcde", h.OutString())
}

func TestInstanceStopsAtItsBudget(t *testing.T) {
	inst := NewInstance("1", address("g1x"), "counter", []byte("10"), 3)
	h := NewTestHost()
	uassert.NoError(t, inst.Run(&counter{total: 10}, h, Unmetered))
	uassert.Equal(t, "out of fuel", inst.Status.String())
	uassert.Equal(t, int64(3), inst.FuelUsed)
	uassert.Equal(t, int64(0), inst.Remaining())
	uassert.Equal(t, "abc", h.OutString())

	// A second call has nothing to spend and says so instead of looping.
	uassert.ErrorIs(t, inst.Run(&counter{}, h, Unmetered), ErrBudgetExhausted)
}

func TestInstanceSliceClamps(t *testing.T) {
	inst := NewInstance("1", address("g1x"), "counter", nil, 10)
	inst.FuelUsed = 7
	uassert.Equal(t, int64(3), inst.Slice(100))
	uassert.Equal(t, int64(2), inst.Slice(2))
	uassert.Equal(t, int64(3), inst.Slice(Unmetered))

	open := NewInstance("2", address("g1x"), "counter", nil, Unmetered)
	uassert.Equal(t, int64(5), open.Slice(5))
	uassert.Equal(t, Unmetered, open.Slice(Unmetered))
}

func TestInstanceRejectsABadSnapshot(t *testing.T) {
	inst := NewInstance("1", address("g1x"), "counter", []byte("5"), Unmetered)
	inst.Snapshot = []byte{1, 2, 3} // too short for the counter's three fields
	err := inst.Run(&counter{}, NewTestHost(), Unmetered)
	uassert.ErrorIs(t, err, ErrTruncated)
	// The instance is untouched: a snapshot that cannot be decoded costs
	// gas but never corrupts the stored program.
	uassert.Equal(t, int64(0), inst.Slices)
	uassert.Equal(t, "5", string(inst.Program))
}

func TestStore(t *testing.T) {
	s := NewStore()
	uassert.Equal(t, 0, s.Size())
	uassert.Equal(t, true, s.Get("nope") == nil)

	s.Set(NewInstance("001", address("g1a"), "counter", nil, Unmetered))
	s.Set(NewInstance("002", address("g1b"), "counter", nil, Unmetered))
	s.Set(NewInstance("003", address("g1c"), "counter", nil, Unmetered))
	uassert.Equal(t, 3, s.Size())
	uassert.Equal(t, "002", s.Get("002").ID)

	ids := ""
	s.Iterate(func(i *Instance) bool { ids += i.ID + " "; return false })
	uassert.Equal(t, "001 002 003 ", ids)

	rev := ""
	s.ReverseIterate(func(i *Instance) bool { rev += i.ID + " "; return false })
	uassert.Equal(t, "003 002 001 ", rev)

	// Early stop.
	first := ""
	s.Iterate(func(i *Instance) bool { first = i.ID; return true })
	uassert.Equal(t, "001", first)

	uassert.True(t, s.Remove("002"))
	uassert.False(t, s.Remove("002"))
	uassert.Equal(t, 2, s.Size())
}

func TestTrapReason(t *testing.T) {
	uassert.Equal(t, "boom", TrapReason(&counter{trap: "boom"}))
	uassert.Equal(t, "", TrapReason(&counter{}))
}
