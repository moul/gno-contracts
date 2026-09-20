package quotes

import (
	"strings"
	"testing"
)

// TestFeaturedIndexDeterministic verifies the rotating pick is a pure,
// deterministic function of (height, count): same inputs -> same index,
// always within [0, count).
func TestFeaturedIndexDeterministic(t *testing.T) {
	tests := []struct {
		name   string
		height int64
		count  int
		want   int
	}{
		{"zero height", 0, 4, 0},
		{"wraps at count", 4, 4, 0},
		{"mid range", 5, 4, 1},
		{"single quote always zero", 12345, 1, 0},
		{"empty list", 100, 0, -1},
		{"negative height normalized", -3, 4, 3},
		{"large height", 1_000_003, 3, 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := featuredIndex(tt.height, tt.count)
			if got != tt.want {
				t.Errorf("featuredIndex(%d, %d) = %d, want %d",
					tt.height, tt.count, got, tt.want)
			}
			// For non-empty lists the index must be a valid slot.
			if tt.count > 0 && (got < 0 || got >= tt.count) {
				t.Errorf("featuredIndex(%d, %d) = %d, out of range [0,%d)",
					tt.height, tt.count, got, tt.count)
			}
		})
	}

	// Determinism: repeated calls with identical inputs never diverge.
	for i := 0; i < 5; i++ {
		if featuredIndex(7, 4) != featuredIndex(7, 4) {
			t.Fatal("featuredIndex is not deterministic")
		}
	}
}

// TestValidate covers the content rules enforced before a quote is stored.
func TestValidate(t *testing.T) {
	tests := []struct {
		name    string
		text    string
		wantErr error
	}{
		{"ok short", "hello world", nil},
		{"ok at limit", strings.Repeat("x", maxQuoteLen), nil},
		{"empty", "", errEmpty},
		{"too long", strings.Repeat("x", maxQuoteLen+1), errTooLong},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validate(tt.text)
			if err != tt.wantErr {
				t.Errorf("validate(%q) err = %v, want %v", tt.name, err, tt.wantErr)
			}
		})
	}
}

// TestRenderSeeded checks that a fresh deploy (seeded board) renders the
// expected structure: title, a blockquote featured pick, and the full list
// containing every seeded quote.
func TestRenderSeeded(t *testing.T) {
	out := Render("")

	if !strings.Contains(out, "# Quote of the Moment") {
		t.Error("missing title heading")
	}
	if !strings.Contains(out, "\n> ") {
		t.Error("featured quote is not rendered as a blockquote")
	}
	if !strings.Contains(out, "## All quotes (") {
		t.Error("missing full-list section")
	}

	// Every seeded quote must appear in the listing.
	for _, q := range board {
		if !strings.Contains(out, q.text) {
			t.Errorf("rendered output missing seeded quote: %q", q.text)
		}
	}

	// Seeded quotes have no author and should surface the house label.
	if !strings.Contains(out, "the board") {
		t.Error("seeded quotes should be attributed to \"the board\"")
	}
}

// TestSeededBoard confirms init populated the board and ids are sequential.
func TestSeededBoard(t *testing.T) {
	if len(board) < 3 {
		t.Fatalf("expected at least 3 seeded quotes, got %d", len(board))
	}
	for i, q := range board {
		if q.id != i {
			t.Errorf("quote at position %d has id %d, want %d", i, q.id, i)
		}
	}
}
