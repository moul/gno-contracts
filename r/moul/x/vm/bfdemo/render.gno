package bfdemo

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/vm/bf/v0"
	"gno.land/p/moul/x/vm/vmkit/v0"
	"gno.land/p/nt/ufmt/v0"
)

// samples are the programs the home page offers, so the realm is usable
// without writing Brainfuck by hand.
var samples = []struct {
	name  string
	src   string
	input string
	note  string
}{
	{
		"Hello World",
		"++++++++++[>+++++++>++++++++++>+++>+<<<<-]>++.>+.+++++++..+++.>++.<<+++++++++++++++.>.+++.------.--------.",
		"",
		"385 guest ops, five tape cells. Finishes in one slice.",
	},
	{
		"Echo the input",
		",[.,]",
		"gno.land",
		"Reads through Host.Input, which is what the naive interpreter could not do at all: it panicked on `,`.",
	},
	{
		"Heavy loop",
		"++++++++++[->++++++++++[->++++++++++[-]<]<]",
		"",
		"About 111k guest ops. Give it 20000 fuel and it takes six slices, which is the point.",
	},
}

// Render is the realm's gnoweb view.
//
//   - "/"      the samples, the instance list, and how the thing works.
//   - "/<id>"  one instance: its program, status, fuel and output.
func Render(path string) string {
	id := strings.TrimPrefix(path, "/")
	id = strings.TrimSpace(id)
	if id == "" {
		return renderHome()
	}
	return renderInstance(id)
}

func renderHome() string {
	var sb strings.Builder
	sb.WriteString("# Brainfuck, on chain, a slice at a time\n\n")
	sb.WriteString("Demo of [`p/moul/x/vm/bf`](/p/moul/x/vm/bf/v0) (the machine) and ")
	sb.WriteString("[`p/moul/x/vm/vmkit`](/p/moul/x/vm/vmkit/v0) (the host ABI, the fuel meter, ")
	sb.WriteString("the instance store). This realm holds no logic of its own.\n\n")
	sb.WriteString("A program here does not run to completion. It runs until its fuel slice is spent, ")
	sb.WriteString("then pauses: the realm keeps the snapshot and the next caller pays for the next slice. ")
	sb.WriteString("Realm code cannot pause itself, and a guest can.\n\n")

	sb.WriteString("## Samples\n\n")
	for _, s := range samples {
		sb.WriteString("**" + ui.Inline(s.name) + "**: " + s.note + "\n\n")
		sb.WriteString("```\n" + s.src + "\n```\n\n")
		sb.WriteString(ui.Action("Upload "+s.name, "Upload",
			"src", s.src, "input", s.input, "budget", "0") + "\n\n")
	}

	sb.WriteString("## Instances\n\n")
	t := ui.NewTable("id", "status", "fuel used", "slices", "output")
	store.ReverseIterate(func(i *vmkit.Instance) bool {
		t.Row(
			"["+i.ID+"](/r/moul/x/vm/bfdemo/v0:"+i.ID+")",
			i.Status.String(),
			ufmt.Sprintf("%d", i.FuelUsed),
			ufmt.Sprintf("%d", i.Slices),
			"`"+ui.Cell(printable(i.Output, 24))+"`",
		)
		return false
	})
	sb.WriteString(t.OrEmpty("No instances yet. Upload one of the samples above."))
	sb.WriteString("\n\n")

	sb.WriteString("## Limits\n\n")
	lt := ui.NewTable("limit", "value")
	lt.Row("instances", ufmt.Sprintf("%d", MaxInstances))
	lt.Row("source bytes", ufmt.Sprintf("%d", bf.MaxSource))
	lt.Row("input bytes", ufmt.Sprintf("%d", MaxInput))
	lt.Row("output bytes", ufmt.Sprintf("%d", MaxOutput))
	lt.Row("fuel per slice", ufmt.Sprintf("%d", MaxSliceFuel))
	lt.Row("tape cells", ufmt.Sprintf("%d", bf.TapeSize))
	sb.WriteString(lt.String())
	return sb.String()
}

func renderInstance(id string) string {
	var sb strings.Builder
	sb.WriteString("# Instance " + ui.Inline(id) + "\n\n")
	sb.WriteString("[← all instances](/r/moul/x/vm/bfdemo/v0)\n\n")

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
	t.Row("fuel used", ufmt.Sprintf("%d", inst.FuelUsed))
	t.Row("fuel budget", fuelText(inst.FuelBudget))
	t.Row("slices", ufmt.Sprintf("%d", inst.Slices))
	t.Row("source bytes", ufmt.Sprintf("%d", len(inst.Program)))
	t.Row("snapshot bytes", ufmt.Sprintf("%d", len(inst.Snapshot)))
	sb.WriteString(t.String())
	sb.WriteString("\n")

	// The source is caller-supplied, and everything outside the eight
	// operators is a comment that may hold anything at all. Show the
	// program the machine actually compiled, which cannot contain a
	// backtick or a newline and so cannot break out of the fence.
	sb.WriteString("## Program\n\n```\n" + operatorsOnly(string(inst.Program)) + "\n```\n\n")

	sb.WriteString("## Output\n\n")
	if len(inst.Output) == 0 {
		sb.WriteString(ui.Empty("Nothing written yet."))
	} else {
		sb.WriteString("```\n" + printable(inst.Output, MaxOutput) + "\n```\n")
	}
	sb.WriteString("\n")

	if inst.Status == vmkit.Running {
		sb.WriteString(ui.Action("Run 10000 more fuel", "Step", "id", id, "fuel", "10000"))
		sb.WriteString(" · ")
		sb.WriteString(ui.Action("Run 100000 more fuel", "Step", "id", id, "fuel", "100000"))
		sb.WriteString("\n")
	} else {
		sb.WriteString("This instance is **" + inst.Status.String() + "** and cannot be stepped again.\n")
	}
	return sb.String()
}

func fuelText(n int64) string {
	if n == vmkit.Unmetered {
		return "unmetered"
	}
	return ufmt.Sprintf("%d", n)
}

// operatorsOnly strips a program down to the eight characters the language
// defines. Everything else is a comment by definition, and a comment is
// attacker-controlled text that has no business reaching a renderer.
func operatorsOnly(src string) string {
	var sb strings.Builder
	for i := 0; i < len(src); i++ {
		switch src[i] {
		case '+', '-', '<', '>', '[', ']', '.', ',':
			sb.WriteByte(src[i])
		}
	}
	if sb.Len() == 0 {
		return "(no operators: this program does nothing)"
	}
	return sb.String()
}

// printable renders guest output for a code fence: printable ASCII as itself,
// everything else as an escape. A guest writes arbitrary bytes, so this is
// the only form of it that is safe to show.
func printable(b []byte, max int) string {
	if len(b) == 0 {
		return ""
	}
	truncated := false
	if len(b) > max {
		b, truncated = b[:max], true
	}
	const hexDigits = "0123456789abcdef"
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
