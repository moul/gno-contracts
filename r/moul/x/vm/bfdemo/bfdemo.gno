// Package bfdemo is the playground for the guest-VM work: a realm that runs
// Brainfuck programs on chain, a slice at a time.
//
// It is a demo of two libraries and carries no logic of its own:
// [p/moul/x/vm/bf](/p/moul/x/vm/bf/v0) is the machine, and
// [p/moul/x/vm/vmkit](/p/moul/x/vm/vmkit/v0) is the host ABI, the fuel meter
// and the instance store.
//
// What it exists to show is the thing gno realm code cannot do for itself: a
// program that runs out of fuel does not fail, it pauses. The realm keeps the
// snapshot, and the next caller pays for the next slice. Upload a program,
// call Step a few times, and watch one computation finish across several
// transactions.
package bfdemo

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"time"

	"gno.land/p/moul/x/vm/bf/v0"
	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Caps. Everything a caller can grow is bounded, because all of it is storage
// somebody pays a deposit on.
const (
	// MaxInstances is how many programs the realm keeps at once. Past it,
	// an upload has to wait for someone to remove one.
	MaxInstances = 64
	// MaxOutput caps the bytes one program may write. Past it the guest is
	// trapped rather than truncated, so rendered output is never a lie.
	MaxOutput = 4096
	// MaxInput caps the call input a program can be given.
	MaxInput = 1024
	// DefaultFuel is the budget an upload gets when it asks for none, and
	// the slice size Step uses when asked for none.
	DefaultFuel = 100000
	// MaxSliceFuel bounds one transaction's work regardless of what the
	// caller asked for.
	MaxSliceFuel = 5000000
)

var (
	// store holds the instances: program, snapshot, status, accounting.
	store = vmkit.NewStore()
	// inputs holds each instance's call input, keyed by id. It is separate
	// from the instance so vmkit.Instance stays the VM-agnostic record it
	// is meant to be.
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
// even though both live in this one realm. bf never calls them; they are here
// because the ABI is the point.
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

// Upload compiles src and stores it as a new instance, returning its id.
//
// Compilation happens here rather than at the first Step, so an unbalanced
// program is rejected by the transaction that submitted it instead of costing
// somebody else the gas later.
func Upload(cur realm, src, input string, budget int64) string {
	if count >= MaxInstances {
		panic("bfdemo: too many instances, remove one first")
	}
	if len(input) > MaxInput {
		panic("bfdemo: input too long")
	}
	if _, err := bf.CompileDefault(src); err != nil {
		panic("bfdemo: " + err.Error())
	}
	if budget <= 0 {
		budget = DefaultFuel
	}

	id := idgen.Next().String()
	owner := unsafe.PreviousRealm().Address()
	store.Set(vmkit.NewInstance(id, owner, bf.VMName, []byte(src), budget))
	if input != "" {
		inputs.Set(id, input)
	}
	count++

	chain.Emit("bf_upload", "id", id, "bytes", ufmt.Sprintf("%d", len(src)))
	return id
}

// Step runs one slice of the instance: up to `fuel` guest ops, then stop and
// keep the snapshot. Anyone may pay for a slice, not only the owner: a paused
// program that only its owner can advance is a worse demo and no safer, since
// the program and its budget were both fixed at upload.
func Step(cur realm, id string, fuel int64) string {
	inst := store.Get(id)
	if inst == nil {
		panic("bfdemo: no such instance")
	}
	if inst.Status != vmkit.Running {
		panic("bfdemo: instance is " + inst.Status.String())
	}
	if fuel <= 0 {
		fuel = DefaultFuel
	}
	if fuel > MaxSliceFuel {
		fuel = MaxSliceFuel
	}

	prog, err := bf.CompileDefault(string(inst.Program))
	if err != nil {
		panic("bfdemo: " + err.Error())
	}
	h := &host{inst: inst, in: []byte(inputOf(id)), kv: avl.NewTree()}
	if err := inst.Run(bf.NewMachine(prog), h, fuel); err != nil {
		panic("bfdemo: " + err.Error())
	}
	if h.overrun {
		inst.Status = vmkit.Trapped
		inst.Trap = "output limit reached"
	}

	chain.Emit("bf_step",
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
		panic("bfdemo: no such instance")
	}
	if inst.Owner != unsafe.PreviousRealm().Address() {
		panic("bfdemo: not your instance")
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
