// pairgen writes one AMM pair instance realm: the gno equivalent of a factory
// call.
//
// Ethereum spawns a pair from inside a contract (factory.createPair). gno has
// no on-chain deploy at all: vm/add_package is permanently denied to realm
// code, so creating an instance is an addpkg transaction signed by a human.
// This tool is that factory, and it runs on your machine.
//
// What it writes is deliberately boring: two constants, an init that builds the
// pair and announces it to the registry, and one-line re-exports forwarding
// cur into gno.land/p/moul/x/pair/v0. Two generated instances differ only in
// the two constants and the package name, which is what makes verifying an
// unknown instance a two-line diff. Nothing on chain can attest an instance's
// code; see the registry's package doc.
//
// Usage:
//
//	go -C tools run ./pairgen <keyA> <keyB> [-o DIR] [-namespace NS] [-key NAME]
//
//	# a pair for two grc20reg-registered tokens, under your own address
//	go -C tools run ./pairgen \
//	  gno.land/r/nt/foo20/v0.FOO gno.land/r/nt/bar20/v0.BAR \
//	  -namespace g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5/pair -key moul
//
// It prints the gnokey command to deploy what it wrote. It never broadcasts.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "pairgen:", err)
		os.Exit(1)
	}
}

func run(args []string, out *os.File) error {
	fs := flag.NewFlagSet("pairgen", flag.ContinueOnError)
	dir := fs.String("o", ".", "directory to write the instance into")
	ns := fs.String("namespace", "<your g1 address or registered name>",
		"path prefix under gno.land/r/ the instance is deployed at")
	key := fs.String("key", "moul", "gnokey keybase entry to sign the deploy with")
	// Go's flag package stops at the first non-flag argument, and the usage
	// above puts the two keys first, so leading positionals move to the end
	// before parsing. Without this, `pairgen keyA keyB -o dir` silently keeps
	// the default -o and writes into the current directory.
	pos, rest := splitArgs(args)
	if err := fs.Parse(rest); err != nil {
		return err
	}
	pos = append(pos, fs.Args()...)
	if len(pos) != 2 {
		return fmt.Errorf("need two grc20reg keys; see `go -C tools run ./pairgen -h`")
	}

	inst, err := instance(pos[0], pos[1], *ns)
	if err != nil {
		return err
	}

	// No vN directory. The version lives in the module line and nowhere else,
	// which is what the deversioned workspace layout means; a pkg/v0/ tree here
	// would be the one thing every reader copies and gnopm then has to migrate.
	dest := filepath.Join(*dir, inst.Pkg)
	if err := os.MkdirAll(dest, 0o755); err != nil {
		return err
	}
	src := filepath.Join(dest, inst.Pkg+".gno")
	mod := filepath.Join(dest, "gnomod.toml")
	if err := os.WriteFile(src, []byte(inst.Source()), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(mod, []byte(inst.Gnomod()), 0o644); err != nil {
		return err
	}

	gas, fee := sizeFor(len(inst.Source()) + len(inst.Gnomod()))
	fmt.Fprintf(out, "wrote %s\n      %s\n\ndeploy it with:\n\n", src, mod)
	fmt.Fprintf(out, "  gnokey maketx addpkg -pkgpath %s \\\n", inst.Path)
	fmt.Fprintf(out, "    -pkgdir %s -gas-fee %dugnot -gas-wanted %d \\\n", dest, fee, gas)
	fmt.Fprintf(out, "    -broadcast -chainid gnoland-1 -remote https://rpc.gno.land:443 %s\n\n", *key)
	fmt.Fprint(out, "Deploying also registers it: the init calls pairreg.Register, so one\n"+
		"transaction creates the pair and lists it on /r/moul/x/pairreg/v0.\n")
	return nil
}

// splitArgs peels the leading non-flag arguments off, so they can be re-joined
// after the flags are parsed.
func splitArgs(args []string) (pos, rest []string) {
	i := 0
	for i < len(args) && !strings.HasPrefix(args[i], "-") {
		i++
	}
	return args[:i:i], args[i:]
}

// Instance is one generated pair: everything that differs between two of them.
type Instance struct {
	Pkg        string // gno package name, an identifier
	Path       string // full module path, version included
	SymA, SymB string
	KeyA, KeyB string
}

// instance canonicalises the two keys and derives every name from them.
func instance(keyA, keyB, namespace string) (Instance, error) {
	if keyA == keyB {
		return Instance{}, fmt.Errorf("a pair needs two different tokens")
	}
	// Canonicalise exactly as pair.New does, so the generated file and the
	// on-chain pair agree on which side is A.
	if keyA > keyB {
		keyA, keyB = keyB, keyA
	}
	symA, err := symbolOf(keyA)
	if err != nil {
		return Instance{}, err
	}
	symB, err := symbolOf(keyB)
	if err != nil {
		return Instance{}, err
	}
	pkg := pkgName(symA, symB)
	return Instance{
		Pkg:  pkg,
		Path: fmt.Sprintf("gno.land/r/%s/%s/v0", namespace, pkg),
		SymA: symA, SymB: symB,
		KeyA: keyA, KeyB: keyB,
	}, nil
}

// symbolOf takes the symbol off a grc20reg key, which is `<realm path>.<SYMBOL>`.
func symbolOf(key string) (string, error) {
	tail := key
	if i := strings.LastIndexByte(tail, '/'); i >= 0 {
		tail = tail[i+1:]
	}
	i := strings.LastIndexByte(tail, '.')
	if i < 0 {
		return "", fmt.Errorf("%s is not a grc20reg key (expected <path>.<SYMBOL>)", key)
	}
	return tail[i+1:], nil
}

// pkgName folds two symbols into a gno package name, which is an identifier:
// no hyphens, no leading digit.
func pkgName(symA, symB string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(symA + symB) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	name := b.String()
	if name == "" || (name[0] >= '0' && name[0] <= '9') {
		name = "pair" + name
	}
	return name
}

// sizeFor sizes gas and fee the way gnopm publish does: 1800 gas per uploaded
// byte, and a fee of 0.01ugnot per unit of gas. Not a round number pulled out
// of the air: gas_fee is deducted in full and never refunded, so a ceiling ten
// times too high is a fee ten times too high (gno-contracts#195).
func sizeFor(bytes int) (gas, fee int64) {
	gas = int64(bytes) * 1800
	fee = gas / 100
	if fee < 1 {
		fee = 1
	}
	return gas, fee
}

func (i Instance) Gnomod() string {
	return fmt.Sprintf("module = %q\ngno = \"0.9\"\n\n"+
		"# public: its init registers the *pair.Pair it owns with r/moul/x/pairreg,\n"+
		"# so this realm's own objects have to be reachable from that one. That\n"+
		"# hand-off is the whole point of the instance-per-realm shape.\n", i.Path)
}

func (i Instance) Source() string {
	return strings.NewReplacer(
		"{pkg}", i.Pkg, "{symA}", i.SymA, "{symB}", i.SymB,
		"{keyA}", i.KeyA, "{keyB}", i.KeyB,
	).Replace(template)
}

const template = `// Realm {pkg} is ONE AMM pair, {symA}/{symB}, and nothing else.
//
// Generated by tools/pairgen. Every instance is byte-identical to this file
// except for the package name and the two constants below, so diffing an
// unknown instance against a freshly generated one is the whole verification
// story: gno cannot attest a package's code on chain.
//
// State and funds belong to THIS realm. A bug in one instance cannot touch
// another, and its creator paid its storage deposit.
//
// Pattern: see the README of gno.land/p/moul/x/pair/v0.
package {pkg}

import (
	"gno.land/p/moul/x/pair/v0"
	"gno.land/r/moul/x/pairreg/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// The only two lines that differ between two instances.
const (
	keyA = "{keyA}"
	keyB = "{keyB}"
)

var p *pair.Pair

func init(cur realm) {
	p = pair.New(keyA, keyB, grc20reg.MustGet(keyA), grc20reg.MustGet(keyB))
	pairreg.Register(cross(cur), p)
}

func AddLiquidity(cur realm, maxA, maxB int64) int64 { return p.AddLiquidity(0, cur, maxA, maxB) }

func RemoveLiquidity(cur realm, shares int64) (int64, int64) {
	return p.RemoveLiquidity(0, cur, shares)
}

func Swap(cur realm, keyIn string, amountIn, minOut int64) int64 {
	return p.Swap(0, cur, keyIn, amountIn, minOut)
}

func Quote(keyIn string, amountIn int64) int64 { return p.Quote(keyIn, amountIn) }
func Reserves() (int64, int64)                 { return p.Reserves() }
func SharesOf(owner address) int64             { return p.SharesOf(owner) }
func TotalShares() int64                       { return p.TotalShares() }
func Keys() (string, string)                   { return p.Keys() }
func Render(path string) string                { return p.Render(path) }
`
