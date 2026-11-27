package main

// The gnobench call command: benchmark one realm call.
//
// The other suites compare candidates with each other. This command answers a narrower
// question about a single realm, typically one still being written: deploy it
// from its directory, commit whatever state the benchmark needs, then measure
// one further transaction making one call. That transaction starts with an
// empty object cache and an untouched store, which is how a MsgCall against a
// deployed realm runs, and it is priced on both gas meters, the VM's and the
// store's, exactly as the wiring suite prices its single operations.
//
// To measure two versions of the realm the same way, give -dir twice, the
// first as before a change and the second as after it. The command prints the
// differences without needing a script around two runs.
//
// This only prints a markdown table to stdout (or JSON with the -json flag).
// It doesn't write to
// results/ or reports/.

import (
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"runtime/debug"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	vm "github.com/gnolang/gno/gno.land/pkg/sdk/vm"
	gno "github.com/gnolang/gno/gnovm/pkg/gnolang"
	"github.com/gnolang/gno/gnovm/pkg/gnomod"
	"github.com/gnolang/gno/gnovm/pkg/packages"
	"github.com/gnolang/gno/gnovm/pkg/test"
	gnostdlibs "github.com/gnolang/gno/gnovm/stdlibs"
	"github.com/gnolang/gno/tm2/pkg/crypto"
	"github.com/gnolang/gno/tm2/pkg/std"
)

// defaultCaller is test1, the account a gno dev chain funds at genesis.
const defaultCaller = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

const usersPkgPath = "gno.land/r/sys/users"

// callSpec is one measurement plan: the same for every setup count.
type callSpec struct {
	Call     string // e.g. `PostMessage(cross, "hello")`, without the package
	Setup    string // run n times before Call; {i} is the index
	Caller   string
	SetupBy  string
	Register string // a name for Caller in r/sys/users, or empty
}

// callResult is one measured transaction. VMGas is the VM's own meter
// (opcodes, allocation, the gno store's per-object charges); StoreGas is what
// the chain adds at the key/value store boundary for the same transaction.
type callResult struct {
	Setup    int    `json:"setup"`
	VMGas    int64  `json:"vm_gas"`
	StoreGas int64  `json:"store_gas"`
	Total    int64  `json:"total_gas"`
	Bytes    int64  `json:"bytes"`
	Deposit  int64  `json:"deposit"`
	Denom    string `json:"denom,omitempty"`
	// Base is gno.land's flat-priced "base" store (object bytes, types,
	// counters); Main is the depth-priced "main" B+32 tree (hashes of escaped
	// objects, the package index).
	Base   kvCounts `json:"base_store"`
	Main   kvCounts `json:"main_store"`
	WallNs int64    `json:"wall_ns"`
	Result string   `json:"result,omitempty"`
	Stable bool     `json:"stable"`
	Err    string   `json:"err,omitempty"`
}

// callPair is one setup count measured on both versions of a realm. Diff is
// nil when either side failed, since half a comparison is not one.
type callPair struct {
	Setup  int        `json:"setup"`
	Before callResult `json:"before"`
	After  callResult `json:"after"`
	Diff   *callDiff  `json:"diff,omitempty"`
}

// callDiff is the `after` minus `before`, field by field.
type callDiff struct {
	VMGas    int64    `json:"vm_gas"`
	StoreGas int64    `json:"store_gas"`
	Total    int64    `json:"total_gas"`
	Bytes    int64    `json:"bytes"`
	Deposit  int64    `json:"deposit"`
	Base     kvCounts `json:"base_store"`
	Main     kvCounts `json:"main_store"`
	WallNs   int64    `json:"wall_ns"`
	// SameResult is false when the two versions returned different values,
	// which means the change measured also changes what the call does.
	SameResult bool `json:"same_result"`
}

// dirList collects -dir: once to measure a realm, twice to compare the
// version before a change with the version after it.
type dirList []string

func (d *dirList) String() string { return strings.Join(*d, ", ") }

func (d *dirList) Set(v string) error {
	if len(*d) == 2 {
		return fmt.Errorf("at most twice: the realm before a change, then after it")
	}
	*d = append(*d, v)
	return nil
}

func cmdCall(args []string) error {
	fs := flag.NewFlagSet("call", flag.ExitOnError)
	var dirs dirList
	fs.Var(&dirs, "dir", "the realm's directory; its gnomod.toml names the path it is deployed at. Give it twice to compare two versions: the first is before a change, the second after it")
	var (
		call     = fs.String("call", "", "the measured call, as gno: 'Fn(cross, \"arg\")'. The first argument stands for the caller's realm and is replaced, as a MsgCall does")
		setup    = fs.String("setup", "", "a call made n times before the measured one, in one committed transaction; {i} in it becomes 0..n-1")
		nlist    = fs.String("n", "0", "comma-separated setup counts: one measurement each, every one on a fresh store")
		caller   = fs.String("caller", defaultCaller, "the account making the measured call (default: test1)")
		setupBy  = fs.String("setup-caller", "", "the account making the setup calls (default: -caller)")
		register = fs.String("register", "", "first register -caller under this name in r/sys/users, as a real user is")
		deps     = fs.String("deps", "workspace", "where the realm's imports resolve: workspace (this repository and its vendor/, then $GNOROOT/examples) or gnoroot ($GNOROOT/examples only)")
		gnoroot  = fs.String("gnoroot", os.Getenv("GNOROOT"), "a gnolang/gno checkout, for the stdlibs")
		root     = fs.String("root", ".", "the gnobench directory; its parent is the workspace")
		repeat   = fs.Int("repeat", 2, "runs per setup count; gas and bytes must agree across them, the fastest wall time wins")
		asJSON   = fs.Bool("json", false, "print JSON instead of a markdown table")
	)
	if err := fs.Parse(args); err != nil {
		return err
	}
	if len(dirs) == 0 || *call == "" {
		return fmt.Errorf("-dir and -call are required")
	}
	if *gnoroot == "" {
		return fmt.Errorf("-gnoroot is required (or set GNOROOT)")
	}
	if *repeat < 1 {
		return fmt.Errorf("-repeat must be at least 1")
	}
	ns, err := intList(*nlist)
	if err != nil {
		return err
	}
	for _, n := range ns {
		if n < 0 {
			return fmt.Errorf("-n: a setup count cannot be negative")
		}
		if n > 0 && *setup == "" {
			return fmt.Errorf("-n %d asks for setup calls, so -setup is required", n)
		}
	}
	spec := callSpec{Call: *call, Setup: *setup, Caller: *caller, SetupBy: *setupBy, Register: *register}
	if spec.SetupBy == "" {
		spec.SetupBy = spec.Caller
	}
	if err := spec.validate(); err != nil {
		return err
	}

	absRoot, err := repoRoot(*root)
	if err != nil {
		return err
	}
	examples := filepath.Join(*gnoroot, "examples")
	var roots []string
	switch *deps {
	case "workspace":
		roots = []string{filepath.Dir(absRoot), examples}
	case "gnoroot":
		roots = []string{examples}
	default:
		return fmt.Errorf("-deps must be workspace or gnoroot, not %q", *deps)
	}

	// Both versions share one dependency set, the union of their imports, so
	// a package only one of them imports is loaded once and the other never
	// touches it.
	var realms []*std.MemPackage
	var imports []string
	for _, d := range dirs {
		realmDir, err := filepath.Abs(d)
		if err != nil {
			return err
		}
		mpkg, err := readRealm(realmDir)
		if err != nil {
			return err
		}
		im, err := realmImports(realmDir)
		if err != nil {
			return err
		}
		realms = append(realms, mpkg)
		imports = append(imports, im...)
	}
	if spec.Register != "" {
		imports = append(imports, usersPkgPath)
	}
	slices.Sort(imports)
	imports = slices.Compact(imports)
	pkgs, err := loadCallDeps(*gnoroot, imports, roots)
	if err != nil {
		return err
	}

	env := DetectEnv(*gnoroot)
	fmt.Fprintf(os.Stderr, "gnobench: call %s.%s on %s\n  gno   %s (stdlibs)\n  vm    %s (linked)\n",
		realms[0].Path, spec.Call, env.ID, env.GnoShort(), linkedGno())
	if w := vmMismatch(linkedGnoCommit(), env.GnoCommit); w != "" {
		fmt.Fprintf(os.Stderr, "gnobench: warning: %s\n", w)
	}

	measure := func(label string, mpkg *std.MemPackage, n int) callResult {
		r := measureRepeated(*gnoroot, pkgs, mpkg, spec, n, *repeat)
		fmt.Fprintf(os.Stderr, "  setup=%-7d %stotal=%-11d vm=%-11d store=%-11d bytes=%-8d %s\n",
			n, label, r.Total, r.VMGas, r.StoreGas, r.Bytes, r.Err)
		return r
	}
	var out any
	var md string
	if len(realms) == 1 {
		var rows []callResult
		for _, n := range ns {
			rows = append(rows, measure("", realms[0], n))
		}
		out, md = rows, callMarkdown(realms[0].Path, spec, *deps, env, rows)
	} else {
		fmt.Fprintf(os.Stderr, "  before %s\n  after  %s\n", dirs[0], dirs[1])
		var pairs []callPair
		for _, n := range ns {
			p := callPair{Setup: n, Before: measure("before ", realms[0], n), After: measure("after  ", realms[1], n)}
			p.Diff = diffCalls(p.Before, p.After)
			pairs = append(pairs, p)
		}
		out, md = pairs, compareMarkdown(dirs, realms, spec, *deps, env, pairs)
	}

	if *asJSON {
		b, err := json.MarshalIndent(out, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(b))
		return nil
	}
	fmt.Print(md)
	return nil
}

// measureRepeated measures one setup count repeat times. Gas and bytes are
// deterministic, so every repeat has to agree on them; the fastest wall time
// wins.
func measureRepeated(gnoroot string, pkgs packages.PkgList, mpkg *std.MemPackage, c callSpec, n, repeat int) callResult {
	r := callResult{Setup: n, Stable: true}
	for k := range repeat {
		got, err := measureCall(gnoroot, pkgs, mpkg, c, n)
		if err != nil {
			r.Err = firstLine(err.Error())
			break
		}
		if k == 0 {
			r = got
			r.Stable = true
			continue
		}
		if got.VMGas != r.VMGas || got.Bytes != r.Bytes || got.Base != r.Base || got.Main != r.Main {
			r.Stable = false
		}
		if got.WallNs < r.WallNs {
			r.WallNs = got.WallNs
		}
	}
	return r
}

// diffCalls is `after` minus `before`, or nil when either side failed.
func diffCalls(before, after callResult) *callDiff {
	if before.Err != "" || after.Err != "" {
		return nil
	}
	return &callDiff{
		VMGas:      after.VMGas - before.VMGas,
		StoreGas:   after.StoreGas - before.StoreGas,
		Total:      after.Total - before.Total,
		Bytes:      after.Bytes - before.Bytes,
		Deposit:    after.Deposit - before.Deposit,
		Base:       after.Base.minus(before.Base),
		Main:       after.Main.minus(before.Main),
		WallNs:     after.WallNs - before.WallNs,
		SameResult: after.Result == before.Result,
	}
}

// validate parses every expression before anything is deployed, so a typo is
// a usage error rather than a panic halfway through a setup transaction.
func (c callSpec) validate() error {
	if err := checkCallExpr("-call", c.Call); err != nil {
		return err
	}
	if c.Setup != "" {
		if err := checkCallExpr("-setup", strings.ReplaceAll(c.Setup, "{i}", "0")); err != nil {
			return err
		}
	}
	for flagName, a := range map[string]string{"-caller": c.Caller, "-setup-caller": c.SetupBy} {
		if _, err := crypto.AddressFromBech32(a); err != nil {
			return fmt.Errorf("%s %q is not an address: %w", flagName, a, err)
		}
	}
	return nil
}

// checkCallExpr requires a call to a function of the realm itself, with the
// realm argument first: `Fn(cross, ...)`. The package is implied, because the
// command binds it; a selector like `social.Fn` would name a package that is
// not in scope.
func checkCallExpr(flagName, expr string) error {
	x, err := parser.ParseExpr(expr)
	if err != nil {
		return fmt.Errorf("%s %q does not parse: %w", flagName, expr, err)
	}
	cx, ok := x.(*ast.CallExpr)
	if !ok {
		return fmt.Errorf("%s %q is not a call", flagName, expr)
	}
	if _, ok := cx.Fun.(*ast.Ident); !ok {
		return fmt.Errorf("%s %q: name the function alone, without its package: Fn(cross, ...)", flagName, expr)
	}
	if len(cx.Args) == 0 {
		return fmt.Errorf("%s %q: a crossing call takes the realm first: Fn(cross, ...)", flagName, expr)
	}
	return nil
}

// readRealm reads the production files of the realm in dir, at the path its
// gnomod.toml declares.
func readRealm(dir string) (*std.MemPackage, error) {
	gm, err := gnomod.ParseDir(dir)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", dir, err)
	}
	if !gno.IsRealmPath(gm.Module) {
		return nil, fmt.Errorf("%s is not a realm: only a realm has crossing functions to call", gm.Module)
	}
	return gno.ReadMemPackage(dir, gm.Module, gno.MPUserProd)
}

// realmImports lists the non-stdlib packages the realm's production files
// import. Only the import block is parsed, and that much of gno is Go.
func realmImports(dir string) ([]string, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.gno"))
	if err != nil {
		return nil, err
	}
	fset := token.NewFileSet()
	seen := map[string]bool{}
	var out []string
	for _, f := range files {
		if strings.HasSuffix(f, "_test.gno") || strings.HasSuffix(f, "_filetest.gno") {
			continue
		}
		af, err := parser.ParseFile(fset, f, nil, parser.ImportsOnly)
		if err != nil {
			return nil, err
		}
		for _, is := range af.Imports {
			p, err := strconv.Unquote(is.Path.Value)
			if err != nil {
				return nil, err
			}
			if gno.IsStdlib(p) || seen[p] {
				continue
			}
			seen[p] = true
			out = append(out, p)
		}
	}
	sort.Strings(out)
	return out, nil
}

// loadCallDeps loads every package in imports, transitively, from roots, in
// order: the first root that holds a package path wins. The loader resolves
// from the workspace the process stands in, so it runs from a throwaway one
// holding a single file that imports the lot.
func loadCallDeps(gnoroot string, imports, roots []string) (packages.PkgList, error) {
	if len(imports) == 0 {
		return nil, nil
	}
	tmp, err := os.MkdirTemp("", "gnobench-call-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tmp)

	var b strings.Builder
	b.WriteString("package calldeps\n\nimport (\n")
	for i, p := range imports {
		fmt.Fprintf(&b, "\t_%d %q\n", i, p)
	}
	b.WriteString(")\n")
	for name, body := range map[string]string{
		"gnowork.toml": "",
		"gnomod.toml":  "module = \"gno.land/r/scratch/calldeps\"\ngno = \"0.9\"\n",
		"deps.gno":     b.String(),
	} {
		if err := os.WriteFile(filepath.Join(tmp, name), []byte(body), 0o644); err != nil {
			return nil, err
		}
	}

	cwd, err := os.Getwd()
	if err != nil {
		return nil, err
	}
	if err := os.Chdir(tmp); err != nil {
		return nil, err
	}
	defer os.Chdir(cwd)

	pkgs, err := packages.Load(packages.LoadConfig{
		Out: io.Discard, Deps: true, AllowEmpty: true,
		GnoRoot: gnoroot, ExtraWorkspaceRoots: roots, Fetcher: localOnly{},
	}, ".")
	if err != nil {
		return nil, fmt.Errorf("loading the realm's imports: %w", err)
	}
	for _, p := range pkgs {
		for _, e := range p.Errors {
			return nil, fmt.Errorf("loading %s: %v", p.ImportPath, e)
		}
	}
	return pkgs, nil
}

// localOnly refuses every download. The loader's default fetches a package
// it cannot find locally from a public chain over RPC, which would make a
// measurement depend on whatever that chain happens to serve today.
type localOnly struct{}

func (localOnly) FetchPackage(path string) ([]*std.MemFile, error) {
	return nil, fmt.Errorf("%s is in none of the local roots, and gnobench call does not download", path)
}

// measureCall builds a fresh store, deploys the realm, commits the setup, and
// measures the one call. Each step is its own committed transaction, so the
// last one starts cold.
func measureCall(gnoroot string, pkgs packages.PkgList, mpkg *std.MemPackage, c callSpec, n int) (r callResult, err error) {
	defer func() {
		if rec := recover(); rec != nil {
			err = fmt.Errorf("%v", rec)
		}
	}()
	rawStore, gnoStore := test.StoreWithOptions(gnoroot, io.Discard,
		test.StoreOptions{Testing: true, Packages: pkgs})
	// Two counters over the one test store, standing for the two stores a
	// node mounts. Their key spaces do not overlap, so sharing the backing
	// store changes nothing but lets each side be priced the way the chain
	// prices it.
	base := &countStore{CommitStore: rawStore}
	main := &countStore{CommitStore: rawStore}
	ctx := func(caller string, height int64) any {
		x := test.Context(crypto.Bech32Address(caller), mpkg.Path, nil)
		x.Height = height
		return x
	}

	txWith(base, main, gnoStore, ctx(c.Caller, test.DefaultHeight), func(m *gno.Machine) {
		m.RunMemPackage(mpkg, true)
	})
	// A node fills a byte cache with every stdlib's objects and types when it
	// starts (VMKeeper.LoadStdlib), and a read the cache serves costs no I/O
	// gas. The test store never does, so without this every stdlib type a
	// call touches, time.Time alone is 25 KB, would be priced as a store read
	// the chain does not charge. The deploy above stored every stdlib the
	// realm imports, so the cache now holds what a node's would.
	gnoStore.PopulateStdlibCache(gnostdlibs.InitOrder())
	if c.Register != "" {
		// Height 0 is genesis, the one height at which r/sys/users lets any
		// caller register a name. After it, only a whitelisted controller can.
		txWith(base, main, gnoStore, ctx(c.Caller, 0), func(m *gno.Machine) {
			out := evalOn(m, usersPkgPath, fmt.Sprintf("pkg.RegisterUser(cross, %q, address(%q))", c.Register, c.Caller))
			if len(out) > 0 && out[0].T != nil {
				panic(fmt.Sprintf("registering %s as %q: %s", c.Caller, c.Register, out[0].Sprint(m)))
			}
		})
	}
	if n > 0 {
		txWith(base, main, gnoStore, ctx(c.SetupBy, test.DefaultHeight), func(m *gno.Machine) {
			for i := range n {
				evalOn(m, mpkg.Path, "pkg."+strings.ReplaceAll(c.Setup, "{i}", strconv.Itoa(i)))
			}
		})
	}

	var result string
	b, i := txWith(base, main, gnoStore, ctx(c.Caller, test.DefaultHeight), func(m *gno.Machine) {
		result = showResults(m, evalOn(m, mpkg.Path, "pkg."+c.Call))
	})

	cfg := chainGasConfig()
	price, denom := storagePrice()
	r = callResult{
		Setup: n, VMGas: b.Gas,
		StoreGas: flatStoreGas(cfg, b.KVGets, b.KVGetBytes, b.KVSets, b.KVSetBytes, b.KVDels) +
			chainStoreGas(cfg, i.KVGets, i.KVGetBytes, i.KVSets, i.KVSetBytes, i.KVDels),
		Bytes: b.NetRealm, Deposit: b.NetRealm * price, Denom: denom,
		Base:   kvCounts{b.KVGets, b.KVGetBytes, b.KVSets, b.KVSetBytes, b.KVDels},
		Main:   kvCounts{i.KVGets, i.KVGetBytes, i.KVSets, i.KVSetBytes, i.KVDels},
		WallNs: b.Wall.Nanoseconds(), Result: result, Stable: true,
	}
	r.Total = r.VMGas + r.StoreGas
	return r, nil
}

// kvCounts is what one of the two stores was asked to do.
type kvCounts struct {
	Gets     int64 `json:"gets"`
	GetBytes int64 `json:"get_bytes"`
	Sets     int64 `json:"sets"`
	SetBytes int64 `json:"set_bytes"`
	Dels     int64 `json:"dels"`
}

func (k kvCounts) minus(o kvCounts) kvCounts {
	return kvCounts{k.Gets - o.Gets, k.GetBytes - o.GetBytes, k.Sets - o.Sets, k.SetBytes - o.SetBytes, k.Dels - o.Dels}
}

func showResults(m *gno.Machine, out []gno.TypedValue) string {
	parts := make([]string, len(out))
	for i := range out {
		parts[i] = out[i].Sprint(m)
	}
	return strings.Join(parts, ", ")
}

// storagePrice is the chain's deposit per byte of realm state, read from the
// VM's default params rather than transcribed, for the reason chaingas.go
// gives about the gas schedule.
func storagePrice() (int64, string) {
	coins, err := std.ParseCoins(vm.DefaultParams().StoragePrice)
	if err != nil || len(coins) != 1 {
		return 0, ""
	}
	return coins[0].Amount, coins[0].Denom
}

// builtGnoCommit is the commit of the gno checkout a `make install-local`
// build compiled against, set by the linker. A replaced module carries no
// version of its own, so without it a replaced VM's commit is unknown.
var builtGnoCommit string

// linkedGnoModule is the gnolang/gno module in this binary's build info.
func linkedGnoModule() *debug.Module {
	bi, ok := debug.ReadBuildInfo()
	if !ok {
		return nil
	}
	for _, d := range bi.Deps {
		if d.Path == "github.com/gnolang/gno" {
			return d
		}
	}
	return nil
}

// linkedGno names the gnolang/gno Go module this binary was built against.
// GNOROOT supplies only the stdlibs: the interpreter and its gas meter are
// whatever go.mod pins, unless the build replaced it (make install-local).
func linkedGno() string {
	d := linkedGnoModule()
	switch {
	case d == nil:
		return "unknown"
	case d.Replace != nil && builtGnoCommit != "":
		return d.Replace.Path + " at " + shortCommit(builtGnoCommit) + " (replaced)"
	case d.Replace != nil:
		return d.Replace.Path + " (replaced)"
	}
	return d.Version
}

// linkedGnoCommit is the commit of the linked VM as far as the binary can
// tell: the revision a pseudo-version ends in, or what install-local recorded
// for a replaced build. Empty when it cannot tell, as for a tagged release.
func linkedGnoCommit() string {
	d := linkedGnoModule()
	switch {
	case d == nil:
		return ""
	case d.Replace != nil:
		return builtGnoCommit
	}
	return pseudoVersionRev(d.Version)
}

var pseudoRev = regexp.MustCompile(`\d{14}-([0-9a-f]{12})(\+incompatible)?$`)

// pseudoVersionRev is the 12-digit commit a Go pseudo-version ends in, in
// all three of its forms, or empty for anything else.
func pseudoVersionRev(v string) string {
	m := pseudoRev.FindStringSubmatch(v)
	if m == nil {
		return ""
	}
	return m[1]
}

// vmMismatch explains why a measurement mixes two gno revisions, or is empty
// when the linked VM and GNOROOT are one commit, or when either is unknown.
// GNOROOT supplies the stdlibs and the examples, the linked VM the
// interpreter and every gas price, so a mismatch measures a combination no
// node runs.
func vmMismatch(linked, gnoroot string) string {
	if linked == "" || gnoroot == "" || strings.HasPrefix(gnoroot, linked) || strings.HasPrefix(linked, gnoroot) {
		return ""
	}
	return fmt.Sprintf("the VM linked into gnobench is gno %s, but GNOROOT is at %s. "+
		"The stdlibs and the examples come from GNOROOT, the interpreter and its gas from the linked VM, "+
		"so the numbers mix two revisions. `make install-local` builds gnobench against GNOROOT.",
		shortCommit(linked), shortCommit(gnoroot))
}

func shortCommit(c string) string {
	if len(c) > 9 {
		return c[:9]
	}
	return c
}

func callMarkdown(path string, c callSpec, deps string, env Env, rows []callResult) string {
	var b strings.Builder
	fmt.Fprintf(&b, "## `%s.%s`\n\n", path, c.Call)
	writeCallSetting(&b, c, deps, env)

	b.WriteString("| setup calls | VM gas | store gas | **total gas** | kv reads | kv writes | storage bytes | deposit | wall | returned |\n")
	b.WriteString("|--:|--:|--:|--:|--:|--:|--:|--:|--:|---|\n")
	unstable := false
	for _, r := range rows {
		cells, ok := resultCells(r)
		unstable = unstable || !ok
		b.WriteString(mdRow(append([]string{commas(int64(r.Setup))}, cells...)...))
	}
	b.WriteString("\n")
	writeCallFootnotes(&b, unstable)
	return b.String()
}

// compareMarkdown is callMarkdown for two versions of a realm: per setup
// count, a row for each and a row for what moved between them.
func compareMarkdown(dirs []string, realms []*std.MemPackage, c callSpec, deps string, env Env, pairs []callPair) string {
	var b strings.Builder
	samePath := realms[0].Path == realms[1].Path
	if samePath {
		fmt.Fprintf(&b, "## `%s.%s`, before and after\n\n", realms[0].Path, c.Call)
	} else {
		fmt.Fprintf(&b, "## `%s`, before and after\n\n", c.Call)
	}
	for i, label := range []string{"before", "after"} {
		fmt.Fprintf(&b, "- %s: `%s`", label, dirs[i])
		if !samePath {
			fmt.Fprintf(&b, ", deployed at `%s`", realms[i].Path)
		}
		b.WriteString("\n")
	}
	writeCallSetting(&b, c, deps, env)

	b.WriteString("| setup calls | realm | VM gas | store gas | **total gas** | kv reads | kv writes | storage bytes | deposit | wall | returned |\n")
	b.WriteString("|--:|---|--:|--:|--:|--:|--:|--:|--:|--:|---|\n")
	unstable, differs := false, false
	for _, p := range pairs {
		cells, ok := resultCells(p.Before)
		unstable = unstable || !ok
		b.WriteString(mdRow(append([]string{commas(int64(p.Setup)), "before"}, cells...)...))
		cells, ok = resultCells(p.After)
		unstable = unstable || !ok
		b.WriteString(mdRow(append([]string{"", "after"}, cells...)...))
		if p.Diff != nil {
			differs = differs || !p.Diff.SameResult
			b.WriteString(mdRow(append([]string{"", "**Δ**"}, diffCells(*p.Diff, p.Before, p.After.Denom)...)...))
		}
	}
	b.WriteString("\n")
	b.WriteString("Δ is `after` minus `before`, and the percentage is based on the `before` total. Gas\n")
	b.WriteString("and bytes are deterministic, so any Δ in them is the change itself; a wall-time Δ is\n")
	b.WriteString("only as good as this machine's noise.\n\n")
	if differs {
		b.WriteString("**differs**: the two versions returned different values for the same call, so the change\n")
		b.WriteString("measured also changes what the call does. Make sure that is intended before reading the gas.\n\n")
	}
	if !samePath {
		b.WriteString("The two versions deploy at different paths. Stored type names embed the path, so the\n")
		b.WriteString("storage bytes differ a little for that reason alone.\n\n")
	}
	writeCallFootnotes(&b, unstable)
	return b.String()
}

// writeCallSetting lists what every row of a call table has in common.
func writeCallSetting(b *strings.Builder, c callSpec, deps string, env Env) {
	who := "`" + c.Caller + "`"
	if c.Register != "" {
		who += fmt.Sprintf(", registered in r/sys/users as `%s`", c.Register)
	}
	fmt.Fprintf(b, "- caller: %s\n", who)
	if c.Setup != "" {
		by := "the same account"
		if c.SetupBy != c.Caller {
			by = "`" + c.SetupBy + "`"
		}
		fmt.Fprintf(b, "- setup: `%s`, made as many times as the first column says, by %s, and committed first\n", c.Setup, by)
	}
	fmt.Fprintf(b, "- imports from: %s\n", deps)
	fmt.Fprintf(b, "- stdlibs: gno `%s`; VM linked: `%s`\n\n", env.GnoShort(), linkedGno())
	if w := vmMismatch(linkedGnoCommit(), env.GnoCommit); w != "" {
		fmt.Fprintf(b, "⚠️ %s\n\n", w)
	}
}

// resultCells is one measurement as table cells, from VM gas to the returned
// value. ok is false when the repeats disagreed, which is marked in the row.
func resultCells(r callResult) (cells []string, ok bool) {
	if r.Err != "" {
		return []string{"failed: " + cell(r.Err), "", "", "", "", "", "", "", ""}, true
	}
	mark := ""
	if !r.Stable {
		mark = " ⚠️"
	}
	return []string{
		commas(r.VMGas), commas(r.StoreGas), "**" + commas(r.Total) + "**" + mark,
		commas(r.Base.Gets + r.Main.Gets), commas(r.Base.Sets + r.Main.Sets), commas(r.Bytes),
		commas(r.Deposit) + " " + r.Denom,
		time.Duration(r.WallNs).Round(10 * time.Microsecond).String(), cell(r.Result),
	}, r.Stable
}

// diffCells is a callDiff in the same columns as resultCells.
func diffCells(d callDiff, before callResult, denom string) []string {
	total := "**" + signed(d.Total) + "**"
	if before.Total != 0 {
		total += fmt.Sprintf(" (%+.1f%%)", 100*float64(d.Total)/float64(before.Total))
	}
	wall := time.Duration(d.WallNs).Round(10 * time.Microsecond).String()
	if d.WallNs > 0 {
		wall = "+" + wall
	}
	returned := "same"
	if !d.SameResult {
		returned = "**differs**"
	}
	return []string{
		signed(d.VMGas), signed(d.StoreGas), total,
		signed(d.Base.Gets + d.Main.Gets), signed(d.Base.Sets + d.Main.Sets), signed(d.Bytes),
		signed(d.Deposit) + " " + denom, wall, returned,
	}
}

// writeCallFootnotes says what the totals leave out.
func writeCallFootnotes(b *strings.Builder, unstable bool) {
	if unstable {
		b.WriteString("⚠️ gas or bytes differed between repeats. Both are deterministic, so treat that row as a bug, not as noise.\n\n")
	}
	b.WriteString("Total gas is the VM's meter plus what the chain charges at the store boundary for the\n")
	b.WriteString("same transaction. It leaves out what the ante handler charges before any call runs (the\n")
	b.WriteString("signature, the transaction's bytes, the account and the fee), which a gnodev node put\n")
	b.WriteString("at about 0.9M gas more per MsgCall (see README.md).\n")
	b.WriteString("The deposit is the storage bytes at the chain's default storage price, locked from\n")
	b.WriteString("the caller and refunded when the bytes are freed.\n")
}

func commas(v int64) string { return addCommas(strconv.FormatInt(v, 10)) }

// signed is commas with the sign always shown, as a difference reads.
func signed(v int64) string {
	if v > 0 {
		return "+" + commas(v)
	}
	return commas(v)
}

// mdRow writes one table row. An empty cell stays "| |", not "|  |".
func mdRow(cells ...string) string {
	var b strings.Builder
	for _, c := range cells {
		b.WriteString("| ")
		if c != "" {
			b.WriteString(c)
			b.WriteString(" ")
		}
	}
	b.WriteString("|\n")
	return b.String()
}

// cell keeps a value inside its table cell.
func cell(s string) string {
	s = strings.ReplaceAll(s, "|", `\|`)
	s = strings.ReplaceAll(s, "\n", " ")
	if len(s) > 60 {
		s = s[:57] + "..."
	}
	return s
}
