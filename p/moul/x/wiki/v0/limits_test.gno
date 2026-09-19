package wiki

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// maxLines is how many typical lines fit in DefaultMaxBody: 32 KiB at 43
// bytes per line.
const maxLines = 758

func buildLines(n int) string {
	var b strings.Builder
	for i := 0; i < n; i++ {
		b.WriteString("some article line of moderate length here.\n")
	}
	return b.String()
}

// TestWorstCaseRendersStayWithinTheQueryBudget exercises the two render paths
// at the largest body MaxBody admits.
//
// vm/qrender runs under a fixed ceiling (maxGasQuery = 3e9 in
// gno.land/pkg/sdk/vm/keeper.go), which a reader cannot raise, so a render
// that exceeds it makes the page permanently unreadable. Measured with
// `gno test -v` on gno master.184 (2026-09-17):
//
//	diff of a 33 KB body against itself plus one line    691M gas   23% of the ceiling
//	article render of a 33 KB body with links            693M gas   23% of the ceiling
//
// gno test reports gas per test function but a test cannot assert on it, so
// this test pins the shape, not the number: it fails if either path starts
// panicking or truncating at the limit. Re-measure with `gno test -v` and
// update the table when either path changes.
func TestWorstCaseRendersStayWithinTheQueryBudget(t *testing.T) {
	w := New(3, DefaultMaxBody)
	body := buildLines(maxLines-2) + "see [[Other page]]\n[[Category:Big]]\n"
	uassert.True(t, len(body) < DefaultMaxBody, "the fixture must fit in MaxBody")

	now, h := at(1)
	_, err := w.Edit(alice, now, h, "Big", body, "", false)
	uassert.NoError(t, err)

	p, err := w.Page("Big")
	uassert.NoError(t, err)

	c := Ctx{Base: "/r/moul/x/wiki/v0", Exists: w.Exists}
	uassert.True(t, len(RenderArticle(c, w, p, nil)) > len(body), "the article must render in full")

	now, h = at(2)
	_, err = w.Edit(alice, now, h, "Big", body+"added\n", "", false)
	uassert.NoError(t, err)

	hist := p.History(0, 2)
	out := RenderDiff(c, p, hist[1], hist[0])
	uassert.True(t, strings.Contains(out, "+1 −0 lines"), "a one-line append to a 32 KiB body diffs exactly")
}
