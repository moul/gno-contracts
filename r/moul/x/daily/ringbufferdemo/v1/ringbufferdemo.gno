// Package ringbufferdemo is a small gnoweb demo of the fixed-capacity FIFO
// provided by the [p/moul/x/daily/ringbuffer](/p/moul/x/daily/ringbuffer/v1)
// library: it pushes more entries than the buffer can hold and shows what
// survives, plus what each overflowing push evicted.
//
// It contains no buffer logic of its own. Stateless, so Render is deterministic.
package ringbufferdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/ringbuffer/v1"
)

const capacity = 4

var feed = []string{"alpha", "bravo", "charlie", "delta", "echo", "foxtrot"}

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Ring Buffer\n\n")
	b.WriteString("A fixed-capacity FIFO that overwrites its oldest entry, demoing the ")
	b.WriteString("[`p/moul/x/daily/ringbuffer`](/p/moul/x/daily/ringbuffer/v1) library.\n\n")
	b.WriteString("Capacity **")
	b.WriteString(strconv.Itoa(capacity))
	b.WriteString("**, pushing ")
	b.WriteString(strconv.Itoa(len(feed)))
	b.WriteString(" entries:\n\n")
	b.WriteString("| push | evicted | contents (oldest → newest) |\n|---|---|---|\n")

	r := ringbuffer.New(capacity)
	for _, v := range feed {
		ev, dropped := r.Push(v)
		b.WriteString("| `")
		b.WriteString(v)
		b.WriteString("` | ")
		if dropped {
			b.WriteString("`" + ev + "`")
		} else {
			b.WriteString("—")
		}
		b.WriteString(" | `")
		b.WriteString(strings.Join(r.Slice(), " "))
		b.WriteString("` |\n")
	}

	b.WriteString("\n> The buffer never grows: once full, each push costs the oldest entry. ")
	b.WriteString("On chain that bound is the point — an unbounded queue is an unbounded storage bill.\n")
	return b.String()
}
