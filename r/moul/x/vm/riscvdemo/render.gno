package riscvdemo

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/vm/riscv/v0"
	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/ufmt/v0"
)

// regNames are the ABI names, because nobody reading a register dump thinks in
// x-numbers and every compiler's output is annotated with these.
var regNames = [32]string{
	"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
	"s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
	"a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
	"s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
}

// Render is the realm's gnoweb view.
//
//   - "/"      the samples, the instance list, and what the numbers mean.
//   - "/<id>"  one instance: its status, fuel, output and register file.
func Render(path string) string {
	id := strings.TrimSpace(strings.TrimPrefix(path, "/"))
	if id == "" {
		return renderHome()
	}
	return renderInstance(id)
}

func renderHome() string {
	var sb strings.Builder
	sb.WriteString("# RV32IM, on chain, a slice at a time\n\n")
	sb.WriteString("Demo of [`p/moul/x/vm/riscv`](/p/moul/x/vm/riscv/v0) (the hart) and ")
	sb.WriteString("[`p/moul/x/vm/vmkit`](/p/moul/x/vm/vmkit/v0) (the host ABI, the fuel meter, ")
	sb.WriteString("the instance store). This realm holds no logic of its own.\n\n")
	sb.WriteString("The programs below are flat `.text` images: the same bytes a cross compiler ")
	sb.WriteString("emits for `riscv32im-unknown-none-elf`. Nothing here was written in a ")
	sb.WriteString("chain language, and nothing translated it.\n\n")
	sb.WriteString("A program does not run to completion. It runs until its fuel slice is spent, ")
	sb.WriteString("then pauses: the realm keeps the snapshot and the next caller pays for the ")
	sb.WriteString("next slice. Realm code cannot pause itself, and a guest can.\n\n")

	sb.WriteString("## Samples\n\n")
	for i := range samples {
		s := &samples[i]
		sb.WriteString("**" + ui.Inline(s.name) + "**: " + s.note + "\n\n")
		sb.WriteString("```asm\n" + s.asm + "\n```\n\n")
		sb.WriteString(ui.Action("Upload "+s.name, "UploadSample",
			"name", s.slug, "input", s.input,
			"budget", ufmt.Sprintf("%d", s.budget)) + "\n\n")
	}

	sb.WriteString("## Instances\n\n")
	t := ui.NewTable("id", "status", "instructions", "slices", "output")
	store.ReverseIterate(func(i *vmkit.Instance) bool {
		t.Row(
			"["+i.ID+"](/r/moul/x/vm/riscvdemo/v0:"+i.ID+")",
			i.Status.String(),
			ufmt.Sprintf("%d", i.FuelUsed),
			ufmt.Sprintf("%d", i.Slices),
			"`"+ui.Cell(printable(i.Output, 24))+"`",
		)
		return false
	})
	sb.WriteString(t.OrEmpty("No instances yet. Upload one of the samples above."))
	sb.WriteString("\n\n")

	sb.WriteString("## What a slice costs\n\n")
	sb.WriteString("An RV32IM instruction costs about **8,500 gas** here, measured rather than ")
	sb.WriteString("estimated, so a block buys roughly **350,000 guest instructions**. Loading ")
	sb.WriteString("the image costs about **19,600 gas per instruction word** and is paid again ")
	sb.WriteString("on every resume, which is why the image cap below is small. The numbers and ")
	sb.WriteString("how they were taken are in the [library README](/p/moul/x/vm/riscv/v0).\n\n")

	sb.WriteString("## Limits\n\n")
	lt := ui.NewTable("limit", "value")
	lt.Row("instances", ufmt.Sprintf("%d", MaxInstances))
	lt.Row("image bytes", ufmt.Sprintf("%d", MaxImage))
	lt.Row("input bytes", ufmt.Sprintf("%d", MaxInput))
	lt.Row("output bytes", ufmt.Sprintf("%d", MaxOutput))
	lt.Row("instructions per slice", ufmt.Sprintf("%d", MaxSliceFuel))
	lt.Row("address space", ufmt.Sprintf("%d", riscv.MemSize))
	sb.WriteString(lt.String())
	return sb.String()
}

func renderInstance(id string) string {
	var sb strings.Builder
	sb.WriteString("# Instance " + ui.Inline(id) + "\n\n")
	sb.WriteString("[← all instances](/r/moul/x/vm/riscvdemo/v0)\n\n")

	inst := store.Get(id)
	if inst == nil {
		sb.WriteString("**No such instance.** It was never uploaded, or its owner removed it.\n")
		return sb.String()
	}

	t := ui.NewTable("field", "value")
	t.Row("owner", ui.Addr(inst.Owner))
	t.Row("vm", ui.Cell(inst.VM))
	t.Row("status", inst.Status.String())
	if inst.Trap != "" {
		t.Row("trap", ui.Cell(inst.Trap))
	}
	t.Row("instructions run", ufmt.Sprintf("%d", inst.FuelUsed))
	t.Row("budget", fuelText(inst.FuelBudget))
	t.Row("slices", ufmt.Sprintf("%d", inst.Slices))
	t.Row("image bytes", ufmt.Sprintf("%d", len(inst.Program)))
	t.Row("image words", ufmt.Sprintf("%d", len(inst.Program)/4))
	t.Row("snapshot bytes", ufmt.Sprintf("%d", len(inst.Snapshot)))
	sb.WriteString(t.String())
	sb.WriteString("\n")

	sb.WriteString("## Registers\n\n")
	sb.WriteString(renderRegisters(inst))

	sb.WriteString("## Output\n\n")
	if len(inst.Output) == 0 {
		sb.WriteString(ui.Empty("Nothing written yet."))
	} else {
		sb.WriteString("```\n" + printable(inst.Output, MaxOutput) + "\n```\n")
	}
	sb.WriteString("\n")

	sb.WriteString("## Image\n\n```\n" + hexDump(inst.Program, 64) + "\n```\n\n")

	if inst.Status == vmkit.Running {
		sb.WriteString(ui.Action("Run 25000 instructions", "Step", "id", id, "fuel", "25000"))
		sb.WriteString(" · ")
		sb.WriteString(ui.Action("Run 100000 instructions", "Step", "id", id, "fuel", "100000"))
		sb.WriteString("\n")
	} else {
		sb.WriteString("This instance is **" + inst.Status.String() + "** and cannot be stepped again.\n")
	}
	return sb.String()
}

// renderRegisters restores the snapshot to read the register file out of it.
// The hart is not kept between transactions, only its snapshot is, so this is
// the only place the state is legible, and it is the thing worth seeing: a
// program that wrote nothing still computed something.
func renderRegisters(inst *vmkit.Instance) string {
	if len(inst.Snapshot) == 0 {
		return ui.Empty("Not started yet: no snapshot to read.") + "\n\n"
	}
	var m riscv.Machine
	if err := m.Restore(inst.Snapshot); err != nil {
		return ui.Empty("The snapshot could not be read.") + "\n\n"
	}
	reg := m.Registers()

	var sb strings.Builder
	t := ui.NewTable("register", "hex", "unsigned", "signed")
	t.Row("pc", ufmt.Sprintf("0x%08X", m.PC()), "", "")
	shown := 0
	for i := 1; i < 32; i++ {
		if reg[i] == 0 {
			continue
		}
		t.Row(
			regNames[i],
			ufmt.Sprintf("0x%08X", reg[i]),
			ufmt.Sprintf("%d", reg[i]),
			ufmt.Sprintf("%d", int64(int32(reg[i]))),
		)
		shown++
	}
	sb.WriteString(t.String())
	if shown == 0 {
		sb.WriteString("\nEvery register except `pc` is zero.\n")
	}
	sb.WriteString("\n")
	return sb.String()
}

func fuelText(n int64) string {
	if n == vmkit.Unmetered {
		return "unmetered"
	}
	return ufmt.Sprintf("%d", n)
}

const hexDigits = "0123456789abcdef"

// hexDump shows the image as words, which is how anyone reading RV32 reads it.
func hexDump(b []byte, max int) string {
	truncated := false
	if len(b) > max {
		b, truncated = b[:max], true
	}
	var sb strings.Builder
	for i := 0; i+3 < len(b); i += 4 {
		if i > 0 && i%16 == 0 {
			sb.WriteString("\n")
		} else if i > 0 {
			sb.WriteString(" ")
		}
		w := uint32(b[i]) | uint32(b[i+1])<<8 | uint32(b[i+2])<<16 | uint32(b[i+3])<<24
		sb.WriteString(ufmt.Sprintf("%08x", w))
	}
	if truncated {
		sb.WriteString("\n...")
	}
	return sb.String()
}

// printable renders guest output for a code fence: printable ASCII as itself,
// everything else as an escape. A guest writes arbitrary bytes, so this is the
// only form of it that is safe to show.
func printable(b []byte, max int) string {
	if len(b) == 0 {
		return ""
	}
	truncated := false
	if len(b) > max {
		b, truncated = b[:max], true
	}
	var sb strings.Builder
	for _, c := range b {
		switch {
		case c == '\n':
			sb.WriteString("\\n")
		case c == '\t':
			sb.WriteString("\\t")
		case c == '\\':
			sb.WriteString("\\\\")
		case c == '`':
			sb.WriteString("\\x60")
		case c >= 0x20 && c < 0x7f:
			sb.WriteByte(c)
		default:
			sb.WriteString("\\x")
			sb.WriteByte(hexDigits[c>>4])
			sb.WriteByte(hexDigits[c&0x0f])
		}
	}
	if truncated {
		sb.WriteString("…")
	}
	return sb.String()
}
