package outfmt

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// * [?fmt=stringer](/r/moul/outfmt:?fmt=stringer)
	// * [?fmt=json](/r/moul/outfmt:?fmt=json)
	// * [?fmt=jsonp](/r/moul/outfmt:?fmt=jsonp)
}
