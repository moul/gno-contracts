package sparklinedemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Sparklines
	//
	// A numeric series as one line of block characters, demoing the [`p/moul/x/daily/sparkline`](/p/moul/x/daily/sparkline/v0) library.
	//
	// ## A series
	//
	// `▁▁▂▄▃▅█▆▅▃▂▁`
	//
	// `3, 5, 9, 14, 12, 18, 25, 21, 16, 11, 7, 4`
	//
	// Scaled between its own bounds, `3` and `25`. The shape is the point; the axis is not.
	//
	// ## The ramp
	//
	// `▁▂▃▄▅▆▇█` — eight levels, low to high.
	//
	// | value | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
	// |---|---|---|---|---|---|---|---|---|
	// | level | `▁` | `▂` | `▃` | `▄` | `▅` | `▆` | `▇` | `█` |
	//
	// ## A flat series
	//
	// `▅▅▅▅` — `1000, 1000, 1000, 1000`
	//
	// Mid-ramp, not along the floor. A series that never moves has no shape, but drawing it at the bottom would claim it was *zero*, which is a different thing and a wrong one.
	//
	// ## Negatives
	//
	// `▁▃▄▅█▅▂` — `-8, -3, 0, 4, 9, 2, -5`
	//
	// Nothing special: the window is the minimum and maximum, wherever zero happens to fall.
	//
	// ## A fixed window clamps
	//
	// `-20, 0, 25, 50, 75, 100, 140` against `0..100`:
	//
	// `▁▁▂▄▆██`
	//
	// `-20` pins to the floor and `140` to the ceiling. Choosing the window keeps a percentage readable, and one outlier cannot flatten the rest of the picture — or break the realm that drew it.
	//
	// ## Rounding is floor
	//
	// | value in `0..100` | level |
	// |---|---|
	// | 0 | `▁` |
	// | 14 | `▁` |
	// | 50 | `▄` |
	// | 85 | `▆` |
	// | 99 | `▇` |
	// | 100 | `█` |
	//
	// Only the maximum itself reaches the top of the ramp, so the peak of a series is always visually distinct.
	//
	// ## Why integers
	//
	// Scaling is integer division throughout. Render output has to be byte-identical on every validating node, and floating point is the usual way that quietly stops being true.
}
