package vmkit

import "gno.land/p/nt/avl/v0"

// TestHost is a deterministic in-memory [Host] for unit tests and for
// measuring a machine without a chain under it.
//
// Nothing here reads the chain, so a test that uses it produces the same
// numbers on every host. Storage is an avl tree rather than a map because gno
// map iteration order is unspecified, and [TestHost.Keys] has to be stable for
// a test to assert on it.
//
// Send is denied unless [TestHost.Grant] funded a budget, which is how the
// capability rule gets tested: a guest that tries to send without a grant must
// come back [Trapped], not silently succeed.
type TestHost struct {
	caller address
	origin address
	now    int64
	height int64

	store *avl.Tree // hex key -> []byte

	in     []byte
	out    []byte
	events []string
	logs   []string

	sendBudget int64
	sends      []Transfer
}

// Transfer records one successful [TestHost.Send].
type Transfer struct {
	To     address
	Amount int64
}

// NewTestHost returns a host with no capabilities granted, height 1, time 0,
// and empty input.
func NewTestHost() *TestHost {
	return &TestHost{
		height: 1,
		store:  avl.NewTree(),
	}
}

// WithCaller sets the address the guest sees as its caller and origin.
func (h *TestHost) WithCaller(a address) *TestHost {
	h.caller, h.origin = a, a
	return h
}

// WithOrigin overrides the origin separately from the caller.
func (h *TestHost) WithOrigin(a address) *TestHost { h.origin = a; return h }

// WithTime sets the block time in Unix seconds.
func (h *TestHost) WithTime(t int64) *TestHost { h.now = t; return h }

// WithHeight sets the block height.
func (h *TestHost) WithHeight(n int64) *TestHost { h.height = n; return h }

// WithInput sets the guest's call input.
func (h *TestHost) WithInput(p []byte) *TestHost {
	h.in = make([]byte, len(p))
	copy(h.in, p)
	return h
}

// Grant funds the send capability with a budget in ugnot. Without it, Send
// returns [ErrNotGranted].
func (h *TestHost) Grant(budget int64) *TestHost { h.sendBudget = budget; return h }

func (h *TestHost) Caller() address { return h.caller }
func (h *TestHost) Origin() address { return h.origin }
func (h *TestHost) Now() int64      { return h.now }
func (h *TestHost) Height() int64   { return h.height }
func (h *TestHost) Input() []byte   { return h.in }

func (h *TestHost) Get(key []byte) []byte {
	v := h.store.Get(hexKey(key))
	if v == nil {
		return nil
	}
	stored := v.([]byte)
	out := make([]byte, len(stored))
	copy(out, stored)
	return out
}

func (h *TestHost) Set(key, val []byte) {
	cp := make([]byte, len(val))
	copy(cp, val)
	h.store.Set(hexKey(key), cp)
}

func (h *TestHost) Output(p []byte) { h.out = append(h.out, p...) }

func (h *TestHost) Emit(typ string, kv ...string) {
	line := typ
	for i := 0; i+1 < len(kv); i += 2 {
		line += " " + kv[i] + "=" + kv[i+1]
	}
	h.events = append(h.events, line)
}

func (h *TestHost) Send(to address, amount int64) error {
	if amount <= 0 || amount > h.sendBudget {
		return ErrNotGranted
	}
	h.sendBudget -= amount
	h.sends = append(h.sends, Transfer{To: to, Amount: amount})
	return nil
}

func (h *TestHost) Log(msg string) { h.logs = append(h.logs, msg) }

// Out returns everything the guest has written, as bytes.
func (h *TestHost) Out() []byte { return h.out }

// OutString returns everything the guest has written, as a string.
func (h *TestHost) OutString() string { return string(h.out) }

// ResetOut discards the output buffer, so one host can measure several runs.
func (h *TestHost) ResetOut() { h.out = nil }

// Events returns the rendered events, in emission order.
func (h *TestHost) Events() []string { return h.events }

// Logs returns the diagnostic lines, in emission order.
func (h *TestHost) Logs() []string { return h.logs }

// Sends returns the transfers that succeeded, in order.
func (h *TestHost) Sends() []Transfer { return h.sends }

// Keys returns every storage key the guest wrote, hex-encoded, in sorted
// order.
func (h *TestHost) Keys() []string {
	out := []string{}
	h.store.Iterate("", "", func(k string, _ any) bool {
		out = append(out, k)
		return false
	})
	return out
}

const hexDigits = "0123456789abcdef"

// hexKey encodes a raw key as hex so that arbitrary bytes, including a zero
// byte, survive being used as an avl key.
func hexKey(key []byte) string {
	out := make([]byte, 0, len(key)*2)
	for _, c := range key {
		out = append(out, hexDigits[c>>4], hexDigits[c&0x0f])
	}
	return string(out)
}
