package svg

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestBaseAttrsEmpty(t *testing.T) {
	uassert.Equal(t, "", BaseAttrs{}.String())
}

func TestBaseAttrsAllFields(t *testing.T) {
	b := BaseAttrs{
		ID:          "i",
		Class:       "c",
		Style:       "fill:red",
		Stroke:      "black",
		StrokeWidth: "2",
		Opacity:     "0.5",
		Transform:   "rotate(90)",
		Visibility:  "hidden",
	}
	uassert.Equal(t,
		`id="i" class="c" style="fill:red" stroke="black" stroke-width="2" opacity="0.5" transform="rotate(90)" visibility="hidden"`,
		b.String())
}

func TestBaseAttrsSkipsEmptyFields(t *testing.T) {
	uassert.Equal(t, `id="i" opacity="0.5"`, BaseAttrs{ID: "i", Opacity: "0.5"}.String())
}

func TestCircle(t *testing.T) {
	c := NewCircle(1, 2, 3, "red")
	uassert.Equal(t, `<circle cx="1" cy="2" r="3" fill="red" />`, c.String())

	uassert.True(t, c.WithClass("dot") == c, "WithClass should be chainable: same pointer back")
	uassert.Equal(t, `<circle cx="1" cy="2" r="3" fill="red" class="dot"/>`, c.String())
}

func TestEllipse(t *testing.T) {
	e := NewEllipse(4, 5, "blue")
	// NewEllipse takes no radii, so RX/RY stay zero until set directly.
	uassert.Equal(t, `<ellipse cx="4" cy="5" rx="0" ry="0" fill="blue" />`, e.String())

	e.RX, e.RY = 10, 20
	e.WithClass("blob")
	uassert.Equal(t, `<ellipse cx="4" cy="5" rx="10" ry="20" fill="blue" class="blob"/>`, e.String())
}

func TestRectangle(t *testing.T) {
	r := NewRectangle(1, 2, 30, 40, "green")
	uassert.Equal(t, `<rect x="1" y="2" width="30" height="40" rx="0" ry="0" fill="green" />`, r.String())

	r.RX, r.RY = 5, 6
	r.WithClass("box")
	uassert.Equal(t, `<rect x="1" y="2" width="30" height="40" rx="5" ry="6" fill="green" class="box"/>`, r.String())
}

func TestPath(t *testing.T) {
	p := NewPath("M0 0 L10 10", "none")
	uassert.Equal(t, `<path d="M0 0 L10 10" fill="none" />`, p.String())

	p.WithClass("stroke")
	uassert.Equal(t, `<path d="M0 0 L10 10" fill="none" class="stroke"/>`, p.String())
}

func TestPolygon(t *testing.T) {
	p := NewPolygon("0,0 10,0 5,8", "yellow")
	uassert.Equal(t, `<polygon points="0,0 10,0 5,8" fill="yellow" />`, p.String())

	p.WithClass("tri")
	uassert.Equal(t, `<polygon points="0,0 10,0 5,8" fill="yellow" class="tri"/>`, p.String())
}

func TestPolyline(t *testing.T) {
	p := NewPolyline("0,0 10,10", "none")
	uassert.Equal(t, `<polyline points="0,0 10,10" fill="none" />`, p.String())

	p.WithClass("line")
	uassert.Equal(t, `<polyline points="0,0 10,10" fill="none" class="line"/>`, p.String())
}

func TestText(t *testing.T) {
	tx := NewText(7, 8, "hello", "black")
	uassert.Equal(t, `<text x="7" y="8" dx="0" dy="0" rotate="" fill="black" >hello</text>`, tx.String())

	tx.DX, tx.DY, tx.Rotate = 1, 2, "45"
	tx.WithClass("label")
	uassert.Equal(t, `<text x="7" y="8" dx="1" dy="2" rotate="45" fill="black" class="label">hello</text>`, tx.String())
}

func TestGroup(t *testing.T) {
	g := NewGroup("purple")
	uassert.Equal(t, `<g fill="purple" ></g>`, g.String())

	g.Append(NewCircle(0, 0, 1, "red"), NewPath("M0 0", "none"))
	g.WithClass("layer")
	uassert.Equal(t,
		`<g fill="purple" class="layer"><circle cx="0" cy="0" r="1" fill="red" /><path d="M0 0" fill="none" /></g>`,
		g.String())
}

func TestGroupNesting(t *testing.T) {
	inner := NewGroup("a")
	inner.Append(NewCircle(1, 1, 1, "red"))
	outer := NewGroup("b")
	outer.Append(inner)

	uassert.Equal(t,
		`<g fill="b" ><g fill="a" ><circle cx="1" cy="1" r="1" fill="red" /></g></g>`,
		outer.String())
}

func TestCanvasEmpty(t *testing.T) {
	c := NewCanvas(100, 50)
	uassert.Equal(t,
		`<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50" viewBox=""></svg>`,
		c.String())
}

func TestCanvasWithViewBox(t *testing.T) {
	c := NewCanvas(100, 50)
	uassert.True(t, c.WithViewBox(0, 0, 200, 100) == c, "WithViewBox should be chainable")
	uassert.True(t, strings.Contains(c.String(), `viewBox="0 0 200 100"`), "viewBox should be set")
}

func TestCanvasAppend(t *testing.T) {
	c := NewCanvas(10, 10)
	c.Append(NewCircle(1, 1, 1, "red"), NewCircle(2, 2, 2, "blue"))

	out := c.String()
	uassert.True(t, strings.Contains(out, `<circle cx="1" cy="1" r="1" fill="red" /><circle cx="2" cy="2" r="2" fill="blue" />`),
		"elements should render in insertion order")
}

// TestCanvasStyleIsKeyOrdered is the determinism check that matters on-chain:
// the style block must not depend on insertion order, or two nodes could
// disagree on the rendered output.
func TestCanvasStyleIsKeyOrdered(t *testing.T) {
	a := NewCanvas(10, 10)
	a.AddStyle("z-last", "fill:blue").AddStyle("a-first", "fill:red")

	b := NewCanvas(10, 10)
	b.AddStyle("a-first", "fill:red").AddStyle("z-last", "fill:blue")

	uassert.Equal(t, a.String(), b.String())
	uassert.True(t, strings.Contains(a.String(), `<style>a-first{fill:red}z-last{fill:blue}</style>`),
		"styles should be emitted in key order")
}

func TestCanvasNoStyleBlockWhenUnset(t *testing.T) {
	uassert.False(t, strings.Contains(NewCanvas(1, 1).String(), "<style>"),
		"a canvas with no styles should not emit an empty <style> block")
}

func TestCanvasAddStyleChainable(t *testing.T) {
	c := NewCanvas(1, 1)
	uassert.True(t, c.AddStyle("a", "b") == c, "AddStyle should be chainable")
}

func TestCanvasBase64RoundTrip(t *testing.T) {
	c := NewCanvas(10, 10)
	c.Append(NewCircle(1, 1, 1, "red"))

	// Base64 must encode exactly what String() produced.
	uassert.Equal(t, "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMCIgaGVpZ2h0PSIxMCIgdmlld0JveD0iIj48Y2lyY2xlIGN4PSIxIiBjeT0iMSIgcj0iMSIgZmlsbD0icmVkIiAvPjwvc3ZnPg==",
		c.Base64())
}

func TestCanvasRenderWrapsBase64(t *testing.T) {
	c := NewCanvas(10, 10)
	c.Append(NewCircle(1, 1, 1, "red"))

	uassert.Equal(t, "![a picture](data:image/svg+xml;base64,"+c.Base64()+")", c.Render("a picture"))
}
