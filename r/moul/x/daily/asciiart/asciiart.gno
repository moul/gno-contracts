// Package asciiart is a small on-chain ASCII art generator. Instead of a
// hand-authored font table, each pattern is produced by a short, pure,
// deterministic algorithm -- e.g. the Sierpinski triangle falls out of a
// single bitwise AND over row/column indices. Callers pick a pattern and a
// size; the realm renders it and keeps a gallery of everyone's generations.
package asciiart

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/kit/store/v0"
)

// maxSize bounds every pattern's size parameter so a single Generate call
// can't blow the block gas limit on a pathologically large grid.
const maxSize = 32

// galleryPageSize caps how many pieces Render shows on the home page.
const galleryPageSize = 8

// piece carries no ID field: the id belongs to the store, which hands it back
// on lookup and iteration.
type piece struct {
	Pattern   string
	Size      int
	Author    address
	CreatedAt int64
	Art       string
}

// gallery assigns the piece ids. v1 kept its own nextID plus a padID() that
// zero-padded to width 6, the narrowest ceiling in this repo: at the millionth
// piece the padding stops and the gallery starts rendering out of order. The
// store key is 8 fixed bytes with no width to outgrow.
var gallery = store.Named("piece")

// RenderDiamond draws a filled diamond of half-width n (2n-1 rows total),
// each row's stars centered and padded with spaces.
func RenderDiamond(n int) string {
	if n < 1 {
		panic("diamond size must be >= 1")
	}
	var b strings.Builder
	for i := 0; i < 2*n-1; i++ {
		d := i
		if i >= n {
			d = 2*n - 2 - i
		}
		b.WriteString(strings.Repeat(" ", n-1-d))
		b.WriteString(strings.Repeat("*", 2*d+1))
		if i < 2*n-2 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

// RenderPyramid draws a solid triangle n rows tall, widening by two stars
// per row and centered with leading spaces.
func RenderPyramid(n int) string {
	if n < 1 {
		panic("pyramid size must be >= 1")
	}
	var b strings.Builder
	for i := 0; i < n; i++ {
		b.WriteString(strings.Repeat(" ", n-1-i))
		b.WriteString(strings.Repeat("*", 2*i+1))
		if i < n-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

// RenderSierpinski draws a Sierpinski triangle in an n x n grid (n must be a
// power of two): cell (row, col) is filled exactly when row&col == 0, the
// classic bitwise identity for Pascal's-triangle-mod-2.
func RenderSierpinski(n int) string {
	if n < 1 || n&(n-1) != 0 {
		panic("sierpinski size must be a power of two (1, 2, 4, 8, 16, 32)")
	}
	var b strings.Builder
	for row := 0; row < n; row++ {
		for col := 0; col < n; col++ {
			if row&col == 0 {
				b.WriteString("#")
			} else {
				b.WriteString(" ")
			}
		}
		if row < n-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

// RenderChecker draws an n x n checkerboard of # and . cells.
func RenderChecker(n int) string {
	if n < 1 {
		panic("checker size must be >= 1")
	}
	var b strings.Builder
	for row := 0; row < n; row++ {
		for col := 0; col < n; col++ {
			if (row+col)%2 == 0 {
				b.WriteString("#")
			} else {
				b.WriteString(".")
			}
		}
		if row < n-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

func renderPattern(pattern string, size int) string {
	switch pattern {
	case "diamond":
		return RenderDiamond(size)
	case "pyramid":
		return RenderPyramid(size)
	case "sierpinski":
		return RenderSierpinski(size)
	case "checker":
		return RenderChecker(size)
	default:
		panic(`unknown pattern: use "diamond", "pyramid", "sierpinski", or "checker"`)
	}
}

// Generate renders a pattern, adds it to the on-chain gallery, and returns
// the rendered art.
func Generate(cur realm, pattern string, size int) string {
	if size < 1 || size > maxSize {
		panic("size must be between 1 and " + strconv.Itoa(maxSize))
	}
	art := renderPattern(pattern, size)

	author := cur.Previous().Address()
	id := gallery.Add(&piece{
		Pattern:   pattern,
		Size:      size,
		Author:    author,
		CreatedAt: runtime.ChainHeight(),
		Art:       art,
	})

	chain.Emit("ArtGenerated", "id", id.String(), "pattern", pattern, "author", author.String())

	return art
}

func renderHome() string {
	var b strings.Builder
	b.WriteString("# ASCII Art Generator\n\n")
	b.WriteString("Four deterministic patterns, no font table required -- each shape " +
		"falls out of a short formula over row/column indices. Pick a pattern and a " +
		"size (1-" + strconv.Itoa(maxSize) + ", sierpinski wants a power of two) and " +
		"`Generate` adds it to the gallery below.\n\n")
	b.WriteString("## Patterns\n\n")
	b.WriteString("- `diamond` -- filled diamond, half-width `size`\n")
	b.WriteString("- `pyramid` -- solid triangle, `size` rows tall\n")
	b.WriteString("- `sierpinski` -- Sierpinski gasket in an n×n grid " +
		"(`row & col == 0`), `size` a power of two\n")
	b.WriteString("- `checker` -- n×n checkerboard\n\n")
	b.WriteString("Call `Generate(pattern, size)`. View a piece at this realm's path " +
		"plus its ID (e.g. `.../asciiart:3`).\n\n")

	b.WriteString("## Gallery (total: " + gallery.LastID().String() + ")\n\n")
	if gallery.Len() == 0 {
		b.WriteString("_nothing generated yet -- be the first_\n")
		return b.String()
	}

	// The newest page, straight from the store: no counter, and only that
	// window is walked.
	for _, e := range gallery.PageReverse(1, galleryPageSize) {
		p := e.Value.(*piece)
		b.WriteString("### #" + e.ID.String() + " -- " + p.Pattern + " (size " + strconv.Itoa(p.Size) + ")\n\n")
		b.WriteString("by `" + p.Author.String() + "` at block " + strconv.Itoa(int(p.CreatedAt)) + "\n\n")
		b.WriteString("```\n" + p.Art + "\n```\n\n")
	}
	return b.String()
}

func renderPiece(idStr string) string {
	safe := ui.Inline(idStr)
	id, ok := store.ParseID(idStr)
	if !ok {
		return "# Piece " + safe + "\n\nNo such piece.\n"
	}
	v, ok := gallery.Get(id)
	if !ok {
		return "# Piece #" + safe + "\n\nNo such piece.\n"
	}
	p := v.(*piece)

	var b strings.Builder
	b.WriteString("# Piece #" + id.String() + "\n\n")
	b.WriteString("- Pattern: " + p.Pattern + "\n")
	b.WriteString("- Size: " + strconv.Itoa(p.Size) + "\n")
	b.WriteString("- Author: `" + p.Author.String() + "`\n")
	b.WriteString("- Block: " + strconv.Itoa(int(p.CreatedAt)) + "\n\n")
	b.WriteString("```\n" + p.Art + "\n```\n")
	return b.String()
}

// Render shows the pattern guide + gallery at "", or one piece by numeric ID.
func Render(path string) string {
	path = strings.TrimPrefix(strings.TrimSpace(path), "/")
	if path == "" {
		return renderHome()
	}
	return renderPiece(path)
}
