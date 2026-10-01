package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	gno "github.com/gnolang/gno/gnovm/pkg/gnolang"
	"github.com/gnolang/gno/gnovm/pkg/packages"
	"github.com/gnolang/gno/gnovm/pkg/test"
	"github.com/gnolang/gno/tm2/pkg/std"
	"github.com/gnolang/gno/tm2/pkg/store"
)

const wiringPkgPath = "gno.land/r/scratch/wire"

// RunWiring drives the VM directly rather than through a filetest, because a
// filetest commits exactly once and the whole question here is what happens
// across many commits.
//
// Each transaction is built the way the VM keeper builds a MsgCall: its own
// cache wrap over the commit store, its own gno transaction store (which
// starts with an empty object cache), a throwaway `main` package importing the
// realm, and the `.origin` sentinel in the crossing slot. Then both layers are
// written, which is the commit.
func RunWiring(s *Suite, env Env, workdir string, ns []int, repeat int, re *regexp.Regexp, verbose bool) ([]Row, error) {
	pkgs, err := loadWiringDeps(workdir)
	if err != nil {
		return nil, err
	}

	var rows []Row
	for _, c := range wiringCandidates {
		for _, n := range ns {
			for _, shape := range []string{shapeOneTx, shapePerTx} {
				if re != nil && !re.MatchString(c.Name+"/"+shape) {
					continue
				}
				r := Row{
					Structure: c.Name, Group: "wiring", Workload: shape, Mode: "cold",
					Value: "str", N: n, Ops: n, Stable: true,
					MeasuredAt: nowUTC(), GnoCommit: env.GnoCommit,
				}
				var best *wireTally
				for k := 0; k < repeat; k++ {
					t, err := wireRun(env.GnoRoot, pkgs, c.Src, n, shape == shapePerTx)
					if err != nil {
						r.Err = firstLine(err.Error())
						break
					}
					if best == nil {
						best = t
					} else {
						// Gas, bytes and write counts are
						// deterministic; only wall time moves.
						if t.Gas != best.Gas || t.KVSetBytes != best.KVSetBytes || t.KVGetBytes != best.KVGetBytes {
							r.Stable = false
						}
						if t.Wall < best.Wall {
							best.Wall = t.Wall
						}
					}
				}
				if best != nil && r.Err == "" {
					r.Gas, r.Bytes = best.Gas, best.NetRealm
					r.DGas, r.DBytes = best.Gas, best.NetRealm
					r.KVSets, r.KVSetBytes, r.KVKeyBytes = best.KVSets, best.KVSetBytes, best.KVKeyBytes
					r.KVGets, r.KVGetBytes, r.KVDels = best.KVGets, best.KVGetBytes, best.KVDels
					r.Txs = best.Txs
					r.WallNs = best.Wall.Nanoseconds()
					r.DWallNs = r.WallNs
				}
				if verbose {
					fmt.Fprintf(os.Stderr, "%-58s gas=%-12d realm=%-9d kv_bytes=%-11d kv_sets=%-7d txs=%-6d wall=%s %s\n",
						r.Key(), r.Gas, r.Bytes, r.KVSetBytes, r.KVSets, r.Txs,
						time.Duration(r.WallNs).Round(time.Millisecond), r.Err)
				}
				rows = append(rows, r)
			}
		}
	}
	return rows, nil
}

// loadWiringDeps gets every package the candidates import into the store. The
// loader resolves from the workspace the workdir sits in, so a throwaway file
// that imports all of them is enough to pull the lot.
func loadWiringDeps(workdir string) (packages.PkgList, error) {
	abs, err := filepath.Abs(workdir)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(abs, 0o755); err != nil {
		return nil, err
	}
	var imports []string
	seen := map[string]bool{}
	for _, c := range wiringCandidates {
		for _, ln := range strings.Split(c.Src, "\n") {
			ln = strings.TrimSpace(ln)
			if !strings.HasPrefix(ln, `import "`) {
				continue
			}
			p := strings.Trim(strings.TrimPrefix(ln, "import "), `"`)
			if !seen[p] {
				seen[p] = true
				imports = append(imports, p)
			}
		}
	}
	var b strings.Builder
	b.WriteString("package deps\n\nimport (\n")
	for i, p := range imports {
		fmt.Fprintf(&b, "\t_%d %q\n", i, p)
	}
	b.WriteString(")\n")
	if err := os.WriteFile(filepath.Join(abs, "gnomod.toml"),
		[]byte("module = \"gno.land/p/scratch/deps\"\ngno = \"0.9\"\n"), 0o644); err != nil {
		return nil, err
	}
	depFile := filepath.Join(abs, "deps.gno")
	if err := os.WriteFile(depFile, []byte(b.String()), 0o644); err != nil {
		return nil, err
	}
	defer os.Remove(depFile)

	cwd, _ := os.Getwd()
	if err := os.Chdir(abs); err != nil {
		return nil, err
	}
	defer os.Chdir(cwd)
	return packages.Load(packages.LoadConfig{Out: io.Discard, Deps: true, AllowEmpty: true}, ".")
}

type wireTally struct {
	Gas        int64
	NetRealm   int64
	KVSets     int64
	KVSetBytes int64
	KVKeyBytes int64
	KVGets     int64
	KVGetBytes int64
	KVDels     int64
	Wall       time.Duration
	Txs        int
}

func (t *wireTally) add(o wireTally) {
	t.Gas += o.Gas
	t.NetRealm += o.NetRealm
	t.KVSets += o.KVSets
	t.KVSetBytes += o.KVSetBytes
	t.KVKeyBytes += o.KVKeyBytes
	t.KVGets += o.KVGets
	t.KVGetBytes += o.KVGetBytes
	t.KVDels += o.KVDels
	t.Wall += o.Wall
	t.Txs += o.Txs
}

// wireRun deploys the realm, then performs n writes either in one transaction
// or in n of them. The deploy is measured and discarded: counting it would
// flatter the batched shape, which pays it once alongside far fewer commits.
func wireRun(root string, pkgs packages.PkgList, src string, n int, perTx bool) (t *wireTally, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("%v", r)
		}
	}()
	rawStore, gnoStore := test.StoreWithOptions(root, io.Discard,
		test.StoreOptions{Testing: true, Packages: pkgs})
	cs := &countStore{CommitStore: rawStore}
	mpkg := &std.MemPackage{
		Type: gno.MPUserProd, Name: "wire", Path: wiringPkgPath,
		Files: []*std.MemFile{
			{Name: "gnomod.toml", Body: gno.GenGnoModLatest(wiringPkgPath)},
			{Name: "wire.gno", Body: src},
		},
	}
	wireTx(cs, gnoStore, func(m *gno.Machine) { m.RunMemPackage(mpkg, true) })

	total := &wireTally{}
	if !perTx {
		*total = wireTx(cs, gnoStore, func(m *gno.Machine) {
			for i := 0; i < n; i++ {
				wireCall(m, i)
			}
		})
		return total, nil
	}
	for i := 0; i < n; i++ {
		i := i
		total.add(wireTx(cs, gnoStore, func(m *gno.Machine) { wireCall(m, i) }))
	}
	return total, nil
}

func wireKey(i int) string {
	s := strconv.Itoa(i)
	for len(s) < 8 {
		s = "0" + s
	}
	return "k" + s
}

func wireCall(m *gno.Machine, i int) {
	k := wireKey(i)
	pv := m.Store.GetPackage(wiringPkgPath, false)
	mpn := gno.NewPackageNode("main", "", nil)
	mpn.Define("pkg", gno.TypedValue{T: &gno.PackageType{}, V: pv})
	mpv := mpn.NewPackage(m.Store.GetAllocator())
	m.SetActivePackage(mpv)
	x := m.MustParseExpr(fmt.Sprintf(`pkg.Set(cross, %q, %q)`, k, "payload-"+k))
	// The compiler-internal `.origin` sentinel is the only way to mint an
	// EOA-origin `cur` from outside user source; it is what the VM keeper
	// substitutes for a MsgCall.
	if cx, ok := x.(*gno.CallExpr); ok && len(cx.Args) > 0 {
		cx.Args[0] = gno.Nx(".origin")
	}
	m.Eval(x)
}

func wireTx(cs *countStore, gnoStore gno.Store, fn func(*gno.Machine)) wireTally {
	before := *cs
	gasMeter := store.NewInfiniteGasMeter()
	t0 := time.Now()
	tcw := cs.CacheWrap()
	txs := gnoStore.BeginTransaction(tcw, tcw, nil, gasMeter)
	m := gno.NewMachineWithOptions(gno.MachineOptions{
		Output: io.Discard, Store: txs, Context: test.Context("", wiringPkgPath, nil),
		MaxAllocBytes: 1 << 40, GasMeter: gasMeter, ReviveEnabled: true,
	})
	fn(m)
	net := int64(0)
	for _, d := range m.Store.RealmStorageDiffs() {
		net += int64(d)
	}
	txs.Write()
	tcw.Write()
	m.Release()
	return wireTally{
		Gas: gasMeter.GasConsumed(), NetRealm: net,
		KVSets: cs.Sets - before.Sets, KVSetBytes: cs.SetBytes - before.SetBytes,
		KVKeyBytes: cs.KeyBytes - before.KeyBytes,
		KVGets: cs.Gets - before.Gets, KVGetBytes: cs.GetBytes - before.GetBytes,
		KVDels: cs.Dels - before.Dels,
		Wall: time.Since(t0), Txs: 1,
	}
}
