// The Go tooling lives in its own module, separate from the repository root.
//
// The root holds vendor/gno.land, the committed gno dependencies. Go treats a
// vendor/ directory in a module root as Go vendoring and refuses to build
// against a module that is not listed in vendor/modules.txt, and `go mod
// vendor` "fixes" that by deleting everything it did not put there, which
// means the gno dependencies. The two vendoring schemes cannot share a
// directory, so the Go module moves out from under it.
//
// tools/gnopublish has had its own module for the same kind of reason.
module github.com/moul/gno-contracts/tools

go 1.24.0

require moul.io/gnopm v0.7.0

tool (
	github.com/moul/gno-contracts/tools/gnoblog
	github.com/moul/gno-contracts/tools/gnocontracts
	github.com/moul/gno-contracts/tools/gnohome
	moul.io/gnopm
)
