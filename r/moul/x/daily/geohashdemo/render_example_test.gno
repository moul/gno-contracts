package geohashdemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Geohash
	//
	// Turning a latitude and longitude into a short base32 string, demoing the [`p/moul/x/daily/geohash`](/p/moul/x/daily/geohash/v0) library.
	//
	// ## One point, at growing precision
	//
	// Jutland, Denmark, at 57.64911, 10.40744:
	//
	// ```
	//  1  u
	//  2  u4
	//  3  u4p
	//  4  u4pr
	//  5  u4pru
	//  6  u4pruy
	//  7  u4pruyd
	//  8  u4pruydq
	//  9  u4pruydqq
	// 10  u4pruydqqv
	// 11  u4pruydqqvj
	// ```
	//
	// Every character adds five bits and every prefix is itself a valid geohash of the same place, so truncating one zooms out. Two hashes sharing a long prefix are close together, which is what lets an avl tree keyed this way answer "everything near here" with a range scan and no geometry at all.
	//
	// Two more places, at the length each one needs:
	//
	// - Null Island (0, 0): `s0000`
	// - Leon, Spain (42.6, -5.6): `ezs42`
	// - Jutland, Denmark (57.64911, 10.40744): `u4pruy`
	//
	// > Next: [`/cell`](/r/moul/x/daily/geohashdemo/v0:cell) for the box a hash names, [`/neighbors`](/r/moul/x/daily/geohashdemo/v0:neighbors) for the eight cells around one.
}

// ExampleRender_cell pins the page that shows a geohash is a box, not a point.
func ExampleRender_cell() {
	print(Render("/cell"))
	// Output:
	// # Geohash
	//
	// Turning a latitude and longitude into a short base32 string, demoing the [`p/moul/x/daily/geohash`](/p/moul/x/daily/geohash/v0) library.
	//
	// ## The box `ezs42` names
	//
	// A geohash is a box, never a point, and the shorter the hash the bigger the box.
	//
	// ```
	// latitude   42.5830078125 .. 42.626953125
	// longitude  -5.625 .. -5.5810546875
	// size       0.0439453125 by 0.0439453125 degrees
	// ```
	//
	// `Decode` reports the centre, 42.60498046875, -5.60302734375, because the centre is the best single point a box can give. The coordinates that produced the hash, 42.6, -5.6, are inside it: yes.
	//
	// Null Island is not: no.
	//
	// > Next: [`/neighbors`](/r/moul/x/daily/geohashdemo/v0:neighbors).
}

// ExampleRender_neighbors pins the eight surrounding cells and the wrap at the
// antimeridian.
func ExampleRender_neighbors() {
	print(Render("/neighbors"))
	// Output:
	// # Geohash
	//
	// Turning a latitude and longitude into a short base32 string, demoing the [`p/moul/x/daily/geohash`](/p/moul/x/daily/geohash/v0) library.
	//
	// ## The eight cells around `ezs42`
	//
	// ```
	// ezefx ezs48 ezs49
	// ezefr ezs42 ezs43
	// ezefp ezs40 ezs41
	// ```
	//
	// Each one is computed by walking exactly one cell from the centre and re-encoding. Every bound is an exact binary fraction, so the step lands on another centre rather than near one, and stepping back is the identity.
	//
	// ### The antimeridian is not an edge of the world
	//
	// `z` is the top right corner cell of the world. The cell east of it is `b`, the top left one, because longitude wraps. The classic lookup-table implementations report nothing there, which is a property of the tables and not of the globe.
	//
	// Latitude genuinely stops, though, so `z` has no northern neighbour and `Neighbors` returns 5 cells rather than eight: `b`, `8`, `x`, `w`, `y`.
	//
	// > Back to [the overview](/r/moul/x/daily/geohashdemo/v0).
}
