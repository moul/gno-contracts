// Package art is the primitive layer for ASCII, ANSI and pixel art in a realm.
//
// A realm's Render returns one string and nothing tells the caller what kind of
// string it is, so every realm picks markdown and every terminal reader eats the
// syntax as noise. This package owns the half of that problem that is about
// pictures: it holds art in a form that can be emitted as plain text, as ANSI
// truecolour, or as SVG, and lets the caller choose at render time.
//
// # Two types, seen twice
//
// [Pix] is an indexed bitmap: a width, a height, one palette index per pixel,
// and a [Palette] of hex colours. It is what a pixel-art NFT actually is.
//
// [Canvas] is a grid of [Cell], each carrying a rune and a foreground and
// background colour. It is what a terminal actually is.
//
// The conversion between them is the point of the package. [Pix.Canvas] takes a
// [Mode] and produces a Canvas; [Canvas.Text], [Canvas.ANSI] and [Canvas.SVG]
// take it the rest of the way out.
//
// # Use Glyphs for sprites, Ramp for photos
//
// The obvious conversion, a luminance ramp, produces mush for pixel art.
// Measured on Settler #25 (a 24x32 sprite on mainnet): the light sand
// background sits at luminance 0.87 and the mid-tone tunic at 0.55, so a
// ten-step ramp drops the background and half the sprite into adjacent buckets
// and the whole thing comes back as '%' and '.'.
//
// Indexed art already carries its own segmentation, in the palette. So the right
// rule for a sprite is one glyph per palette index ([Glyphs]), not one glyph per
// brightness ([Ramp]). Ramp is kept because it is right for a photograph, where
// there is no meaningful palette to key on.
//
// # ANSI is a terminal-only target, by construction
//
// [Canvas.ANSI] emits SGR escape sequences. Those cannot reach gnoweb: raw ESC
// in a code fence is garbage in HTML, and gno.land/p/nt/markdown/sanitize strips
// control bytes anyway. That is not a gap to close later, it is the reason the
// target is a parameter instead of a decision. When colour has to survive the
// web, use [Canvas.SVG] or [Pix.SVG], which carry the same colours through a
// medium gnoweb can actually show.
//
// # Colours are packed ints
//
// A colour is an int holding 0xRRGGBB, or [Default] (-1) meaning "whatever the
// consumer's default is": the terminal's default foreground for an FG, and
// transparent for a background in SVG. [ParseHex] turns "#rrggbb" or "#rgb"
// into one.
package art
