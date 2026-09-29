# `gno.land/p/moul/art/v0`

ASCII, ANSI and pixel art primitives for a realm: hold a picture once, emit it
as plain text, as ANSI truecolour, or as SVG, and let the caller pick at render
time.

`Render` returns one string and nothing tells the caller what kind of string it
is, so every realm picks markdown and every terminal reader eats the syntax as
noise. This package owns the half of that problem that is about pictures.

## Two types, seen twice

| type | is | for |
|---|---|---|
| `Pix` | a width, a height, one palette index per pixel, a `Palette` of hex colours | what a pixel-art NFT actually is |
| `Canvas` | a grid of `Cell`, each a rune plus a foreground and background colour | what a terminal actually is |

`Pix.Canvas(mode)` goes from one to the other. `Canvas.Text()`, `Canvas.ANSI()`
and `Canvas.SVG()` take it the rest of the way out, and `Pix.SVG()` skips the
grid entirely for art that was never character-shaped.

```gno
pix := &art.Pix{W: 8, H: 6, Idx: idx, Pal: art.Palette{"", "#d64550", "#f7a8b0"}}

plain := pix.Canvas(art.Glyphs).Text()        // for a code fence, or a pipe
colour := pix.Canvas(art.HalfBlock).ANSI()    // for a terminal
web := pix.SVG(8).Render("a heart")           // markdown image, data URI, no host
```

## Use `Glyphs` for sprites, `Ramp` for photos

The obvious conversion, a luminance ramp, produces mush for pixel art. Two
palette entries a sprite might genuinely carry, sand `#e8dcc8` and bone
`#d9d9d9`, sit at luminance 221 and 217 out of 255. A ten-step ramp drops both
in bucket 8 and the shape between them disappears.

Indexed art already carries its own segmentation, in the palette. So the rule
for a sprite is **one glyph per palette index**, not one glyph per brightness.
`Ramp` is kept because it is right for a photograph, where there is no
meaningful palette to key on.

Measured on real art rather than on a fixture picked to show it. Settler #25
(`r/g17khq…/settlers/nft:token/25`, read from mainnet 2026-09-29, 32x32, CC0)
carries **20 palette entries**:

| keyed on | colours that survive into the text |
|---|---|
| palette index (`Glyphs`) | 20 of 20 |
| luminance (`Ramp`, ten steps) | 9 of 20 |

Eleven of the artist's twenty colours stop existing, and the shapes between them
go with them. `settler_test.gno` pins that, and `TestRampCollapsesWhatGlyphsKeepsApart`
pins the mechanism on a two-colour case small enough to read.

## The five modes

| mode | packs | colour | good for |
|---|---|---|---|
| `Glyphs` | 1 pixel to 1 cell (2 by default, for aspect) | optional | sprites, and anything that has to survive without colour |
| `Ramp` | same | optional | photographs |
| `HalfBlock` | 2 vertical pixels to 1 cell, with `▀` | full | the best-looking terminal output |
| `Quadrant` | 2x2 to 1 cell | 2 colours per cell | density, at the cost of two colours per block |
| `Braille` | 2x4 to 1 cell | none | the densest mode; a pixel is on if its index is not 0 |

Index 0 is the background by convention: `Braille` keys on it directly, the
default glyph set gives it a space, and a tie in `Quadrant`'s two-colour split
goes to the lower index so that ink does not end up in the background.

## ANSI is terminal-only, by construction

`Canvas.ANSI()` emits SGR escapes, which cannot reach gnoweb: `p/nt/markdown/sanitize`
strips control bytes, and raw ESC in a code fence is garbage in HTML anyway.

That is not a gap to close later. It is the reason the target is a parameter
rather than a decision. When colour has to survive the web, `Canvas.SVG()`
carries the same two colours per cell through a medium the web can show.

## Notes

- Colours are packed `0xRRGGBB` ints, or `Default` (-1) meaning "whatever the
  consumer's default is". `ParseHex` reads `#rrggbb` and `#rgb`; `#abc` expands
  by duplication to `#aabbcc`, not by zero-padding.
- Every helper **clips** rather than panicking. Art is drawn by arithmetic, and
  a line one cell off the edge is not worth aborting a `Render` over.
- `Canvas.Text()` trims trailing spaces; `Canvas.ANSI()` does not, because a
  trailing cell can carry a background colour and trimming it would punch a hole
  in the picture.
- `Pix.SVG()` emits **one `<path>` per colour**, run-length encoded, in pixel
  coordinates with the scale on the viewBox. On Settler #25 that is 4,532 bytes
  against 20,625 for one `<rect>` per run, 4.5x, and scaling up costs 2 bytes
  total. A realm pays for those bytes in gas and the reader pays in page weight.
- `Canvas.SVG()` emits one `<text>` per non-blank cell rather than one per run:
  a run would have to assume the font's advance width, and a renderer that
  disagreed would shear the picture. Dense art belongs in `Pix.SVG()`, which has
  no font to get wrong.
- Text handed to SVG is XML-escaped here, because `p/moul/svg`'s `Text`
  interpolates its content into the document unescaped.

## Not in this package

The document model. Turning a whole `Render` into markdown *or* plain text
(links as footnotes, tables with padded columns, headings underlined instead of
`#`-prefixed) is a separate concern and a separate package. This one only knows
about pictures.
