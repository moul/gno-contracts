package gallery

func ExampleRender() {
	println(Render("?fmt=txt"))
	// Output:
	// ╭──────────────────────╮
	// │moul's gallery        │
	// │art on gno.land       │
	// ╰──────────────────────╯
	//
	// Art on gno.land, rendered rather than described. Nothing here is stored
	// in this realm: every piece lives where its author put it.
	//
	//   Piece        Author        Where                                                    Shown
	//   -----------  ------------  -------------------------------------------------------  -------------
	//   gnoface      moul          r/moul/demo/gnoface/v0                                   rendered here
	//   millipede    moul          r/moul/demo/millipede/v0                                 rendered here
	//   sapin        moul          r/moul/sapin/v0                                          rendered here
	//   settler25    the Settlers  r/g17khqpukees4237dtn3astzapmp462vjhsz6st4/settlers/nft  linked
	//   asciiart     moul          r/moul/x/daily/asciiart/v1                               linked
	//   pixelcanvas  moul          r/moul/x/daily/pixelcanvas/v0                            linked
	//
	// 3 pieces rendered from source, 3 pieces linked.
	//
	// Open one at /r/moul/gallery:piece/<slug>, with ?fmt=txt for this form.
}

func ExampleRender_piece() {
	println(Render("piece/millipede?fmt=txt"))
	// Output:
	// millipede
	// =========
	//
	//     ╚⊙ ⊙╝
	//   ╚═(███)═╝
	//  ╚═(███)═╝
	// ╚═(███)═╝
	//  ╚═(███)═╝
	//   ╚═(███)═╝
	//    ╚═(███)═╝
	//     ╚═(███)═╝
	//     ╚═(███)═╝
	//
	// A millipede of any length. The oldest piece here, and still the one that
	// best explains why ASCII is the cheapest picture there is.
	//   Author: moul
	//   License: see the source realm
	//   Source: r/moul/demo/millipede/v0
	//   the source realm [1]
	//
	// Links:
	//   [1] https://gno.land/r/moul/demo/millipede/v0
}
