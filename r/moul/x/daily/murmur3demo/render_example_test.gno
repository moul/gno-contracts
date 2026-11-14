package murmur3demo

// ExampleRender pins the realm's root Render output as a testable example.
// The self-test line is `b0f57ee3`, the SMHasher verification value for
// MurmurHash3 x86_32, so this example doubles as a conformance test for the
// library running inside the VM.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # MurmurHash3 x86_32
	//
	// Austin Appleby's non-cryptographic hash, demoing the [`p/moul/x/daily/murmur3`](/p/moul/x/daily/murmur3/v0) library.
	//
	// ## Vectors
	//
	// | input | seed 0 | seed 1 |
	// | --- | --- | --- |
	// | _(empty)_ | `00000000` | `514e28b7` |
	// | `a` | `3c2569b2` | `588adce8` |
	// | `abc` | `b3dd93fa` | `aa75e9ff` |
	// | `123456789` | `b4fef382` | `54d0d6ff` |
	// | `hello world` | `5e928f0f` | `4343ed22` |
	// | `hello worle` | `b97415bf` | `3d75e0dc` |
	//
	// The last two inputs differ by one letter and share no digits. That avalanche is the finalizer doing its job.
	//
	// ## Self-test
	//
	// SMHasher hashes 256 growing keys under 256 seeds and hashes the results. For MurmurHash3 x86_32 the answer is `b0f57ee3`, and this realm computes it on chain every time you load the page:
	//
	// `b0f57ee3`
	//
	// ## Spread
	//
	// `key-0` through `key-999` over 8 buckets. A hash worth using fills all of them:
	//
	// | bucket | keys |  |
	// | --- | --- | --- |
	// | 0 | 127 | ############ |
	// | 1 | 122 | ############ |
	// | 2 | 128 | ############ |
	// | 3 | 136 | ############# |
	// | 4 | 125 | ############ |
	// | 5 | 134 | ############# |
	// | 6 | 119 | ########### |
	// | 7 | 109 | ########## |
	//
	// Append a path to hash your own text: [`/gno.land`](/r/moul/x/daily/murmur3demo/v0:gno.land)
	//
	// > ⚠️ **Not a cryptographic hash.** MurmurHash3 is invertible and collisions are cheap to generate, so anyone who picks the keys can pick the bucket. Use it to spread, never to commit or authenticate.
}
