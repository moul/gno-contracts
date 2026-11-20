package sha1demo

// ExampleRender pins the realm's root Render output as a testable example.
// The empty-string and `abc` rows are the FIPS 180-1 vectors and every git
// blob id matches `git hash-object`, so this example doubles as a conformance
// test: a wrong digit anywhere in the library fails here.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # SHA-1
	//
	// Forty hex digits from any amount of input, demoing the [`p/moul/x/daily/sha1`](/p/moul/x/daily/sha1/v0) library.
	//
	// ## Published vectors
	//
	// | input | sha1 |
	// | --- | --- |
	// | _(empty)_ | `da39a3ee5e6b4b0d3255bfef95601890afd80709` |
	// | `a` | `86f7e437faa5a7fce15d1ddcb9eaeaea377667b8` |
	// | `abc` | `a9993e364706816aba3e25717850c26c9cd0d89d` |
	// | `message digest` | `c12252ceda8be8994d5fa0290a47231c1d16aae3` |
	// | `hello world` | `2aae6c35c94fcfb415dbe95f408b9ce91ee846ed` |
	// | `hello worle` | `247e71a704dcdad472474496f8a4fe3a847d6b5b` |
	//
	// The empty string and `abc` are the FIPS 180-1 answers every implementation is checked against. The last two rows differ by one letter and share no prefix: that avalanche is the property worth seeing.
	//
	// ## git object ids
	//
	// | content | git hash-object |
	// | --- | --- |
	// | _(empty file)_ | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` |
	// | `hello world\n` | `3b18e512dba79e4c8300dd08aeb37f8e728b8dad` |
	// | `Hello World\n` | `557db03de997c86a4a028e1ebd3a1ceb225be238` |
	//
	// `e69de29b` is the id of the empty file, the one hash a git user can recognise on sight. Every row matches `git hash-object`, because the header git prepends is the whole difference between a blob id and a content hash.
	//
	// ## HMAC-SHA1
	//
	// | key | message | hmac |
	// | --- | --- | --- |
	// | `Jefe` | `what do ya want for nothing?` | `effcdf6ae5eb2fa2d27416d5f184df9c259a7c79` |
	// | `key` | `The quick brown fox jumps over the lazy dog` | `de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9` |
	// | _(empty)_ | _(empty)_ | `fbdb1d1b18aa6c08324b7d64b71fb76370690e1d` |
	//
	// Row one is RFC 2202 test case 2. A key longer than the 64-byte block is hashed down first, so a long key and its own digest are the same key.
	//
	// ## Hash your own
	//
	// `/r/moul/x/daily/sha1demo/v0:your text here`
	//
	// > ⚠️ **SHA-1 is broken as a collision-resistant hash.** SHAttered produced two different PDFs with the same digest in 2017, and a chosen-prefix collision followed in 2020. Never use it to decide that two documents are the same document. It is still the only correct answer where a format specifies it: git ids, HMAC-SHA1 in TOTP, legacy interop.
}
