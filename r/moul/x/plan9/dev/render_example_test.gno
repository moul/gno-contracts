package dev

// ExampleRender pins the device index. It carries no chain value, so it does
// not move with the block height the way the devices themselves do.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # /dev
	//
	// The chain as a Plan 9 device tree. Each file is a function: reading it runs code, so `/dev/height` is never stale.
	//
	// Posted to [`r/moul/x/plan9/ns`](/r/moul/x/plan9/ns/v1)'s `/srv` at deploy time, so no realm has to import this one to use it:
	//
	// ```
	// bind /srv/dev /dev
	// ```
	//
	// | device | contents |
	// |---|---|
	// | [`caller`](/r/moul/x/plan9/dev/v1:cat/caller) | pkgpath of the realm that crossed into this read |
	// | [`domain`](/r/moul/x/plan9/dev/v1:cat/domain) | the chain domain |
	// | [`drivers`](/r/moul/x/plan9/dev/v1:cat/drivers) | this table |
	// | [`height`](/r/moul/x/plan9/dev/v1:cat/height) | current block height |
	// | [`null`](/r/moul/x/plan9/dev/v1:cat/null) | always empty; the bit bucket |
	// | [`random`](/r/moul/x/plan9/dev/v1:cat/random) | sha256 of chain id and height, hex; block-deterministic, NOT unpredictable |
	// | [`session`](/r/moul/x/plan9/dev/v1:cat/session) | the calling key's session scope, one AllowPath per line |
	// | [`sysname`](/r/moul/x/plan9/dev/v1:cat/sysname) | the chain id |
	// | [`time`](/r/moul/x/plan9/dev/v1:cat/time) | block time, RFC3339 |
	// | [`user`](/r/moul/x/plan9/dev/v1:cat/user) | the origin caller's address |
	// | [`zero`](/r/moul/x/plan9/dev/v1:cat/zero) | endless NUL bytes; reads exactly what you ask for |
	//
	// Design and analysis: [moul/gno-contracts#136](https://github.com/moul/gno-contracts/issues/136).
	//
	// _Not affiliated with Plan 9. Plan 9 from Bell Labs is the work of the Computing Science Research Center at Bell Labs; the name and the marks are theirs, and the copyright is held by the [Plan 9 Foundation](https://p9f.org). This realm borrows the vocabulary and none of the code: it is an homage, asking what that ecosystem's spirit looks like on a chain._
}

// ExampleRender_cat pins one device read. /dev/drivers is the one device whose
// contents are fixed, which makes it the only one an example can assert; the
// chain-derived ones are checked against chain/runtime in dev_test.gno.
func ExampleRender_cat() {
	print(Render("cat/drivers"))
	// Output:
	// # /dev/drivers
	//
	// ```
	// caller	pkgpath of the realm that crossed into this read
	// domain	the chain domain
	// drivers	this table
	// height	current block height
	// null	always empty; the bit bucket
	// random	sha256 of chain id and height, hex; block-deterministic, NOT unpredictable
	// session	the calling key's session scope, one AllowPath per line
	// sysname	the chain id
	// time	block time, RFC3339
	// user	the origin caller's address
	// zero	endless NUL bytes; reads exactly what you ask for
	// ```
	//
	// [all devices](/r/moul/x/plan9/dev/v1)
}
