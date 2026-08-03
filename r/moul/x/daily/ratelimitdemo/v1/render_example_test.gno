package ratelimitdemo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Rate Limiter
	//
	// Demo of the [`p/moul/x/daily/ratelimit`](/p/moul/x/daily/ratelimit/v1) library — an on-chain token-bucket limiter (port of `golang.org/x/time/rate`).
	//
	// ## Config
	//
	// | Parameter | Value |
	// |---|---|
	// | Rate (tokens/block) | 0.5 |
	// | Burst (capacity) | 5 |
	// | Clock height | 123 |
	//
	// ## Callers
	//
	// _No caller has hit the limiter yet._
	//
	// ---
	// Call `Allow(cur)` to consume a token; read `Tokens(addr)` for a caller's balance.
}
