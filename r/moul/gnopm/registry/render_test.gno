package registry

// ExampleRender pins the realm's Render output, which is its whole public
// surface. Each example calls seedFixture first: realm globals persist for the
// whole test binary and examples run after every Test, so without the reset the
// pinned output would silently depend on test order.

func ExampleRender() {
	seedFixture()
	print(Render(""))
	// Output:
	// # gnopm source registry
	//
	// Where a deployed package says it came from. Every entry is a claim made by whoever signed it, never a verified fact: this realm cannot clone a repository, so it records testimony in the shape a verifier needs and labels who said it.
	//
	// **Packages:** 2 · **Claims:** 3
	//
	// | package | claims | owner has claimed |
	// | --- | ---: | --- |
	// | [gno.land/p/moul/md/v1](/r/moul/gnopm/registry/v0:gno.land/p/moul/md/v1) | 1 | no |
	// | [gno.land/r/g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh/scratch/v0](/r/moul/gnopm/registry/v0:gno.land/r/g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh/scratch/v0) | 2 | yes |
	//
	// [How this works](/r/moul/gnopm/registry/v0:help)
}

// The package page is the one that matters: an owner's claim and a stranger's
// claim about the same path, under separate headings, owner first. The pinned
// output is what stops that distinction being quietly refactored away.
func ExampleRender_package() {
	seedFixture()
	print(Render(alicePkg))
	// Output:
	// # gno.land/r/g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh/scratch/v0
	//
	// 2 claim(s). A claim is what an address said, not what anyone checked.
	//
	// ## Claimed by the namespace owner
	//
	// The signer owns `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh`, so this claim comes from the party that controls the path. That is not a proof the source matches. It is a proof of who is speaking.
	//
	// | field | value |
	// | --- | --- |
	// | claimant | `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh` |
	// | commit | [000000000000](https://github.com/moul/gno-contracts/tree/0000000000000000000000000000000000000000/scratch) |
	// | repository | [https://github.com/moul/gno-contracts](https://github.com/moul/gno-contracts) |
	// | directory | `scratch` |
	// | ref | `refs/tags/v0.1.0` |
	// | claimed at | block 100 |
	// | last updated | never |
	//
	// ## Claimed by others
	//
	// These addresses do not own `g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh`. A third party may be filling in the map honestly, or pointing at a repository that has nothing to do with this package. Read the source before trusting either.
	//
	// | field | value |
	// | --- | --- |
	// | claimant | `g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu` |
	// | commit | [111111111111](https://github.com/bob/impostor/tree/1111111111111111111111111111111111111111) |
	// | repository | [https://github.com/bob/impostor](https://github.com/bob/impostor) |
	// | directory | `(repository root)` |
	// | claimed at | block 110 |
	// | last updated | never |
	//
	// [Back to the registry](/r/moul/gnopm/registry/v0)
}

func ExampleRender_unclaimed() {
	seedFixture()
	print(Render("gno.land/p/moul/nothing/v0"))
	// Output:
	// # gno.land/p/moul/nothing/v0
	//
	// Nobody has claimed a source for this package.
	//
	// [Claim it](/r/moul/gnopm/registry/v0$help&func=Register&pkgPath=gno.land%2Fp%2Fmoul%2Fnothing%2Fv0)
	//
	// [Back to the registry](/r/moul/gnopm/registry/v0)
}

func ExampleRender_help() {
	seedFixture()
	print(Render("help"))
	// Output:
	// # How this registry works
	//
	// A gno import path is a chain address, not a repository URL, so nothing on chain says where a deployed package came from. This realm is where an address can say so.
	//
	// ## What it proves
	//
	// Nothing on its own, and that is the honest answer. A realm cannot clone a repository, so it cannot check that the code at a commit is the code at a path. Three claims get confused with each other and only two of them can ever be settled:
	//
	// | claim | provable |
	// | --- | --- |
	// | this package came from that repository | no. Not here and not anywhere: anyone may deploy any bytes and claim any repository |
	// | the deployed bytes equal the addpkg payload of that directory at that commit | yes, by hashing both sides. Off chain, by anything that can clone |
	// | the claimant owns this path's namespace | yes, from chain data, and it is recomputed on every read |
	//
	// ## Writing to it
	//
	// Register the source of a package you deployed. Calling it again replaces your own claim and nobody else's, which is how you move a claim to a new commit after a redeploy.
	//
	// [Register](/r/moul/gnopm/registry/v0$help&func=Register) · [Withdraw](/r/moul/gnopm/registry/v0$help&func=Withdraw)
	//
	// Fields: the full package path, an https repository URL, a 40 or 64 character lowercase hex commit, the subdirectory holding the package (empty for the repository root), and optionally a fully-qualified ref such as `refs/tags/v1.2.0`.
	//
	// Anyone may claim any path. A claim from an address that does not own the namespace is not hidden: it is shown under its own heading and ranked below the owner's.
	//
	// [Back to the registry](/r/moul/gnopm/registry/v0)
}
