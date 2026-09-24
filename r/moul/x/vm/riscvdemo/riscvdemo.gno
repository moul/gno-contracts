// Package riscvdemo runs real compiled machine code on chain, a slice at a
// time.
//
// It is a demo of two libraries and carries no logic of its own:
// [p/moul/x/vm/riscv](/p/moul/x/vm/riscv/v0) is the RV32IM hart, and
// [p/moul/x/vm/vmkit](/p/moul/x/vm/vmkit/v0) is the host ABI, the fuel meter
// and the instance store.
//
// What it exists to show is that the guest was not written for gno. The
// programs on the front page are flat .text images: the same bytes
// `rustc --target riscv32im-unknown-none-elf` emits, uploaded as hex. The
// realm holds the snapshot between transactions, so one computation finishes
// across several of them, and realm code cannot do that for itself.
package riscvdemo

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"time"

	"gno.land/p/moul/x/vm/riscv/v0"
	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Caps. Everything a caller can grow is bounded, because all of it is storage
// somebody pays a deposit on.
const (
	// MaxInstances is how many programs the realm keeps at once.
	MaxInstances = 64
	// MaxImage caps an uploaded text segment at 2,048 instructions.
	//
	// This one is not arbitrary. Predecoding costs about 19,600 gas per word
	// and is redone on every resume, so the image size is a tax on every
	// transaction that touches the instance, not just the upload. 8 KiB works
	// out to roughly 40M gas per slice before the guest executes anything,
	// which is about 1% of a block.
	MaxImage = 8192
	// MaxOutput caps the bytes one program may write. Past it the guest is
	// trapped rather than truncated, so rendered output is never a lie.
	MaxOutput = 4096
	// MaxInput caps the call input a program can be given.
	MaxInput = 1024
	// DefaultFuel is the budget an upload gets when it asks for none, and the
	// slice size Step uses when asked for none.
	DefaultFuel = 100000
	// MaxSliceFuel bounds one transaction's work regardless of what the
	// caller asked for, and it is derived from the measurement rather than
	// picked: an RV32IM instruction costs about 8,500 gas, so 100,000 of them
	// is about 850M, a little under a third of a 3G block. Twice this would
	// still be a legal transaction and a rude one, and it would leave no room
	// for the predecode and the realm's own storage writes on top.
	MaxSliceFuel = 100000
)

var (
	store  = vmkit.NewStore()
	inputs = avl.NewTree()
	idgen  seqid.ID
	count  int
)

// host is the realm-backed [vmkit.Host]. One is built per call, wrapping the
// instance being stepped, so a guest's output and authority are scoped to it
// and nothing ambient leaks in.
type host struct {
	inst    *vmkit.Instance
	in      []byte
	kv      *avl.Tree
	overrun bool // the guest wrote past MaxOutput
}

func (h *host) Caller() address { return h.inst.Owner }
func (h *host) Origin() address { return h.inst.Owner }
func (h *host) Now() int64      { return time.Now().Unix() }
func (h *host) Height() int64   { return runtime.ChainHeight() }
func (h *host) Input() []byte   { return h.in }

// Get and Set are scoped to the instance by construction: the tree belongs to
// the instance being stepped, so one program cannot reach another's storage
// even though both live in this one realm.
func (h *host) Get(key []byte) []byte {
	v := h.kv.Get(string(key))
	if v == nil {
		return nil
	}
	return v.([]byte)
}

func (h *host) Set(key, val []byte) { h.kv.Set(string(key), val) }

func (h *host) Output(p []byte) {
	if len(h.inst.Output)+len(p) > MaxOutput {
		h.overrun = true
		return
	}
	h.inst.Output = append(h.inst.Output, p...)
}

func (h *host) Emit(typ string, kv ...string) { chain.Emit(typ, kv...) }

// Send is never granted here. The demo funds no instance, so a guest that
// tries to move coins is refused. That is the capability rule doing its job,
// not a missing feature.
func (h *host) Send(to address, amount int64) error { return vmkit.ErrNotGranted }

func (h *host) Log(msg string) {}

// Upload stores a hex-encoded text image as a new instance and returns its id.
//
// The image is loaded here rather than at the first Step, so a misaligned or
// oversized one is rejected by the transaction that submitted it instead of
// costing somebody else the gas later.
func Upload(cur realm, hexImage, input string, budget int64) string {
	img, ok := decodeHex(hexImage)
	if !ok {
		panic("riscvdemo: image is not valid hex")
	}
	return upload(img, input, budget)
}

// UploadSample stores one of the programs the front page offers. Writing RV32IM
// by hand is not the point of this realm, and without this nobody without a
// cross compiler could press a button.
func UploadSample(cur realm, name, input string, budget int64) string {
	s := sampleByName(name)
	if s == nil {
		panic("riscvdemo: no such sample")
	}
	// A sample carries its own budget because the default is a total, not a
	// slice: the heavy loop needs 200,006 instructions, and offering a button
	// that runs out of fuel halfway is a worse demo than no button.
	if budget <= 0 {
		budget = s.budget
	}
	return upload(s.image(), input, budget)
}

func upload(img []byte, input string, budget int64) string {
	if count >= MaxInstances {
		panic("riscvdemo: too many instances, remove one first")
	}
	if len(input) > MaxInput {
		panic("riscvdemo: input too long")
	}
	if len(img) == 0 {
		panic("riscvdemo: empty image")
	}
	if len(img) > MaxImage {
		panic("riscvdemo: image too large")
	}
	// Loading it now is the validation: NewMachine is what rejects an image
	// that is not a whole number of instructions.
	if _, err := riscv.NewMachine(img, riscv.DefaultEntry); err != nil {
		panic("riscvdemo: " + err.Error())
	}
	if budget <= 0 {
		budget = DefaultFuel
	}

	id := idgen.Next().String()
	owner := unsafe.PreviousRealm().Address()
	store.Set(vmkit.NewInstance(id, owner, riscv.VMName, img, budget))
	if input != "" {
		inputs.Set(id, input)
	}
	count++

	chain.Emit("riscv_upload", "id", id, "bytes", ufmt.Sprintf("%d", len(img)))
	return id
}

// Step runs one slice of the instance: up to `fuel` guest instructions, then
// stop and keep the snapshot. Anyone may pay for a slice, not only the owner:
// a paused program that only its owner can advance is a worse demo and no
// safer, since the program and its budget were both fixed at upload.
func Step(cur realm, id string, fuel int64) string {
	inst := store.Get(id)
	if inst == nil {
		panic("riscvdemo: no such instance")
	}
	if inst.Status != vmkit.Running {
		panic("riscvdemo: instance is " + inst.Status.String())
	}
	if fuel <= 0 {
		fuel = DefaultFuel
	}
	if fuel > MaxSliceFuel {
		fuel = MaxSliceFuel
	}

	m, err := riscv.NewMachine(inst.Program, riscv.DefaultEntry)
	if err != nil {
		panic("riscvdemo: " + err.Error())
	}
	h := &host{inst: inst, in: []byte(inputOf(id)), kv: avl.NewTree()}
	if err := inst.Run(m, h, fuel); err != nil {
		panic("riscvdemo: " + err.Error())
	}
	if h.overrun {
		inst.Status = vmkit.Trapped
		inst.Trap = "output limit reached"
	}

	chain.Emit("riscv_step",
		"id", id,
		"status", inst.Status.String(),
		"fuel", ufmt.Sprintf("%d", inst.FuelUsed),
	)
	return inst.Status.String()
}

// Remove deletes an instance. Owner only.
func Remove(cur realm, id string) {
	inst := store.Get(id)
	if inst == nil {
		panic("riscvdemo: no such instance")
	}
	if inst.Owner != unsafe.PreviousRealm().Address() {
		panic("riscvdemo: not your instance")
	}
	store.Remove(id)
	inputs.Remove(id)
	count--
}

func inputOf(id string) string {
	v := inputs.Get(id)
	if v == nil {
		return ""
	}
	return v.(string)
}

// decodeHex accepts the output of any hexdump: an even number of hex digits,
// with an optional 0x prefix, and whitespace anywhere. Whitespace is allowed
// because that is what a pasted hexdump has in it; anything else is refused,
// because a silently mangled image would trap somewhere unrelated later.
func decodeHex(s string) ([]byte, bool) {
	if len(s) >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
		s = s[2:]
	}
	digits := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			continue
		}
		v, ok := hexVal(c)
		if !ok {
			return nil, false
		}
		digits = append(digits, v)
	}
	if len(digits) == 0 || len(digits)%2 != 0 {
		return nil, false
	}
	out := make([]byte, len(digits)/2)
	for i := 0; i < len(out); i++ {
		out[i] = digits[i*2]<<4 | digits[i*2+1]
	}
	return out, true
}

func hexVal(c byte) (byte, bool) {
	switch {
	case c >= '0' && c <= '9':
		return c - '0', true
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10, true
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}
