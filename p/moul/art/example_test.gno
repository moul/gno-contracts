package art

// heart is an 8x6 indexed sprite: 0 background, 1 body, 2 highlight.
var (
	heartPal = Palette{"", "#d64550", "#f7a8b0"}
	heartIdx = []uint8{
		0, 1, 1, 0, 0, 1, 1, 0,
		1, 1, 1, 2, 2, 1, 1, 1,
		1, 1, 1, 1, 1, 1, 1, 1,
		0, 1, 1, 1, 1, 1, 1, 0,
		0, 0, 1, 1, 1, 1, 0, 0,
		0, 0, 0, 1, 1, 0, 0, 0,
	}
)

func heart() *Pix {
	return &Pix{W: 8, H: 6, Idx: heartIdx, Pal: heartPal}
}

// One glyph per palette index, each pixel two cells wide so the sprite keeps
// its proportions in a terminal. This is the default for indexed art.
func ExamplePix_Canvas_glyphs() {
	println(heart().Canvas(Glyphs).Text())
	// Output:
	//   ####    ####
	// ######@@@@######
	// ################
	//   ############
	//     ########
	//       ####
}

// The same sprite at four times the density, in Braille. Monochrome by
// construction: a Braille cell has eight dots and no colours, so a pixel is
// only on or off.
func ExamplePix_Canvas_braille() {
	println(heart().Canvas(Braille).Text())
	// Output:
	// ⢾⣷⣾⡷
	// ⠀⠙⠋⠀
}

// Quadrants pack 2x2 into one cell. Asked for no colour, the mode has nothing
// left to say with two colours and degrades to a density map, which is still
// the densest thing a plain-text consumer can be handed.
func ExamplePix_Canvas_quadrant() {
	println(heart().CanvasOpts(Opts{Mode: Quadrant}).Text())
	// Output:
	// ▟▙▟▙
	// ▜██▛
	//  ▜▛
}

// Drawing on a Canvas directly, with a border around it.
func ExampleCanvas_Frame() {
	c := NewCanvas(11, 3)
	c.Write(0, 0, "gno.land")
	c.HLine(0, 1, 11, '─')
	c.Write(0, 2, "ascii art")
	println(c.Frame("art", Round).Text())
	// Output:
	// ╭─art───────╮
	// │gno.land   │
	// │───────────│
	// │ascii art  │
	// ╰───────────╯
}
