package semverdemo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # semver — Semantic Versioning on-chain
	//
	// Demo of the [`p/moul/x/daily/semver`](/p/moul/x/daily/semver/v1) library — a port of `golang.org/x/mod/semver`. Parse `vMAJOR.MINOR.PATCH[-prerelease][+build]` and compare with SemVer 2.0.0 precedence.
	//
	// ## Examples
	//
	// | a | rel | b | note |
	// |---|:---:|---|---|
	// | `1.2.3` | &lt; | `1.2.10` | numeric patch, not lexical |
	// | `1.0.0-alpha` | &lt; | `1.0.0` | pre-release < release |
	// | `1.0.0-alpha.1` | &lt; | `1.0.0-alpha.beta` | numeric id < alphanumeric id |
	// | `1.0.0-rc.1` | &lt; | `1.0.0` | release candidate < final |
	// | `2.0.0` | = | `2.0.0+build.5` | build metadata ignored |
	//
	// ## Try it
	//
	// - Compare two versions: [`/1.2.3/1.2.10`](/r/moul/x/daily/semverdemo/v1:1.2.3/1.2.10)
	// - Submitted list: [`/sorted`](/r/moul/x/daily/semverdemo/v1:sorted)
	// - Submit on-chain: `Submit("v1.4.2")`
}
