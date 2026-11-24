package csvdemo

import (
	"strings"
	"testing"
)

// TestRenderTablesKeepTheirColumns fails on a table row that a GFM renderer
// would split into more or fewer columns than its header. A code span does
// not protect a pipe inside a table: the "a|b" literal used to render a fifth
// column in the field-by-field table, and the example test pinned it.
func TestRenderTablesKeepTheirColumns(t *testing.T) {
	want := -1
	for i, line := range strings.Split(Render(""), "\n") {
		if !strings.HasPrefix(line, "|") {
			want = -1
			continue
		}
		got := strings.Count(line, "|") - strings.Count(line, "\\|")
		if want < 0 {
			want = got
			continue
		}
		if got != want {
			t.Errorf("line %d has %d column separators, its header has %d: %s", i+1, got, want, line)
		}
	}
}
