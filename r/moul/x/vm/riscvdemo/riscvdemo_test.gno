package riscvdemo

import (
	"strings"
	"testing"

	"gno.land/p/moul/x/vm/riscv/v0"
	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// resetState puts the realm globals back where init() left them. Realm state
// persists for the whole test binary, so every test that asserts on ids or on
// the rendered instance list has to start from here.
func resetState() {
	store = vmkit.NewStore()
	inputs = avl.NewTree()
	idgen = seqid.ID(0)
	count = 0
}

func alice() address { return testutils.TestAddress("alice") }

func TestUploadAndRunToCompletion(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice()))

	id := UploadSample(cross(cur), "hello", "", 0)
	uassert.Equal(t, "halted", Step(cross(cur), id, 0))

	inst := store.Get(id)
	uassert.Equal(t, "Hello, gno.land\n", string(inst.Output))
	uassert.Equal(t, int64(1), inst.Slices)
	uassert.Equal(t, alice(), inst.Owner)
	uassert.Equal(t, "riscv32im", inst.VM)
}

// Every sample on the front page has to reach its documented answer, or the
// page offers a button that traps when pressed. The words are assembled
// outside this repo, so this is the test that catches a mistyped one.
func TestEverySampleReachesItsAnswer(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice()))

	cases := []struct {
		slug   string
		reg    int
		want   uint32
		output string
	}{
		{"hello", 0, 0, "Hello, gno.land\n"},
		{"sum100", 5, 5050, ""},
		{"heavy", 5, 1250025000, ""},
		{"mext", 5, 3000000021, ""},
		{"clang", 0, 0, "fb7ffba0"},
		{"ledger", 0, 0, "alice 70\nbob 80\n"},
	}
	for _, c := range cases {
		id := UploadSample(cross(cur), c.slug, sampleByName(c.slug).input, 0)
		status := ""
		for i := 0; i < 20; i++ {
			status = Step(cross(cur), id, 0)
			if status != "running" {
				break
			}
		}
		uassert.Equal(t, "halted", status, c.slug+" must halt")
		inst := store.Get(id)
		uassert.Equal(t, c.output, string(inst.Output), c.slug+" output")
		if c.reg != 0 {
			var m riscv.Machine
			uassert.NoError(t, m.Restore(inst.Snapshot))
			uassert.Equal(t, uint64(c.want), uint64(m.Registers()[c.reg]), c.slug+" result")
		}
	}
}

// TestOneProgramAcrossManyTransactions is what the realm exists to
// demonstrate: the same computation, finished over several calls, each paying
// for its own slice.
func TestOneProgramAcrossManyTransactions(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice()))

	id := UploadSample(cross(cur), "heavy", "", 0)
	status := ""
	for i := 0; i < 50; i++ {
		status = Step(cross(cur), id, 80000)
		if status != "running" {
			break
		}
	}
	inst := store.Get(id)
	uassert.Equal(t, "halted", status)
	uassert.True(t, inst.Slices > 1, "a 200k instruction program must not finish in one slice")
	uassert.Equal(t, int64(200006), inst.FuelUsed)
}

func TestUploadTakesHex(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice()))

	// addi a7, zero, 93 ; ecall
	id := Upload(cross(cur), "0x9308d005 73000000", "", 0)
	_ = id
}

func TestUploadRejectsBadImages(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice()))

	// Called without cross(): a panic raised through a crossing call cannot be
	// recovered, so uassert would never see it.
	uassert.PanicsWithMessage(t, cur, "riscvdemo: image is not valid hex", func() {
		Upload(cur, "zzzz", "", 0)
	})
	uassert.PanicsWithMessage(t, cur, "riscvdemo: image is not valid hex", func() {
		Upload(cur, "abc", "", 0)
	})
	uassert.PanicsWithMessage(t, cur, "riscvdemo: no such sample", func() {
		UploadSample(cur, "nope", "", 0)
	})
	uassert.PanicsWithMessage(t, cur,
		"riscvdemo: riscv: image length is not a whole number of instructions",
		func() { Upload(cur, "0011", "", 0) })
}

func TestDecodeHex(t *testing.T) {
	b, ok := decodeHex("0xDEADbeef")
	uassert.True(t, ok)
	uassert.Equal(t, 4, len(b))
	uassert.Equal(t, uint64(0xDE), uint64(b[0]))
	uassert.Equal(t, uint64(0xEF), uint64(b[3]))

	_, ok = decodeHex("")
	uassert.False(t, ok)
	_, ok = decodeHex("0x")
	uassert.False(t, ok)
	// Whitespace is skipped, because a pasted hexdump has it.
	b, ok = decodeHex("00 11\n22\t33")
	uassert.True(t, ok)
	uassert.Equal(t, 4, len(b))
	// An odd number of digits is still a refusal, whitespace or not.
	_, ok = decodeHex("00 1")
	uassert.False(t, ok)
}

func TestRenderHomeOffersEverySample(cur realm, t *testing.T) {
	resetState()
	out := Render("")
	uassert.True(t, strings.Contains(out, "RV32IM, on chain"), "the title")
	for _, s := range samples {
		uassert.True(t, strings.Contains(out, s.name), "home must offer "+s.slug)
	}
	uassert.True(t, strings.Contains(out, "No instances yet"), "the empty state")
}

// The register file is the interesting half of this VM: a program that writes
// nothing still computed something, and the snapshot is the only place it is
// legible between transactions.
func TestRenderInstanceShowsTheRegisterFile(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(alice()))

	id := UploadSample(cross(cur), "sum100", "", 0)
	Step(cross(cur), id, 0)

	out := Render("/" + id)
	uassert.True(t, strings.Contains(out, "## Registers"), "the section")
	uassert.True(t, strings.Contains(out, "5050"), "t0 must show the answer")
	uassert.True(t, strings.Contains(out, "halted"), "the status")
}

func TestRenderUnknownInstance(t *testing.T) {
	uassert.True(t, strings.Contains(Render("/nope"), "No such instance"))
}

// ExampleRender pins the realm's output for a path whose content cannot drift
// with the instance list. The home page and the instance page both produce
// consecutive blank lines, which an example block cannot represent, so they
// are asserted in the tests above instead.
func ExampleRender() {
	print(Render("/missing"))
	// Output:
	// # Instance missing
	//
	// [← all instances](/r/moul/x/vm/riscvdemo/v0)
	//
	// **No such instance.** It was never uploaded, or its owner removed it.
}
