package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/gnolang/gno/gnovm/pkg/packages"
	"github.com/gnolang/gno/gnovm/pkg/test"
)

var valueExprs = map[string]string{
	"str": `"payload-" + key(i)`,
	"obj": `&rec{A: key(i), B: i}`,
}

type job struct {
	row  Row
	file string
}

// buildBodyFor returns the phaseBuild body for a group.
func buildBodyFor(group string) string {
	if group == "list" {
		return listBuild
	}
	return kvBuild
}

// Run measures a suite and returns the rows. It never writes: the caller
// decides where results go, which is what lets one run update one machine's
// file without touching anyone else's.
func Run(s *Suite, env Env, workdir string, ns []int, vals []string, repeat int, re *regexp.Regexp, verbose bool, keep bool) ([]Row, error) {
	workdir, err := filepath.Abs(workdir)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(workdir, 0o755); err != nil {
		return nil, err
	}
	gnomod := filepath.Join(workdir, "gnomod.toml")
	if err := os.WriteFile(gnomod, []byte("module = \"gno.land/r/scratch/bench\"\ngno = \"0.9\"\n"), 0o644); err != nil {
		return nil, err
	}

	var jobs []job
	written := map[string]bool{}
	for _, st := range s.Structures {
		for _, wl := range s.Workloads {
			if wl.Group != st.Group {
				continue
			}
			for _, v := range vals {
				if !st.takesValue(v) {
					continue
				}
				for _, n := range ns {
					r := Row{
						Structure: st.Name, Group: st.Group, Workload: wl.Name,
						Mode: wl.mode(), Value: v, N: n, Ops: wl.Ops(n),
						MeasuredAt: nowUTC(), GnoCommit: env.GnoCommit,
					}
					if why, ok := st.Skip[wl.Name]; ok {
						r.Skip = why
						jobs = append(jobs, job{row: r})
						continue
					}
					if re != nil && !re.MatchString(st.Name+"/"+wl.Name) {
						continue
					}
					src, err := render(s.Template, scenarioData{
						Imports: st.Imports, Decl: st.Decl, Ops: st.Ops,
						ValueExpr: valueExprs[v], BuildBody: buildBodyFor(st.Group),
						Body: wl.Body, N: n,
						InitBuild: wl.Prebuilt && wl.mode() == "cold",
						MainBuild: wl.Prebuilt && wl.mode() == "warm",
						Light:     wl.Light,
					})
					if err != nil {
						return nil, err
					}
					name := fmt.Sprintf("%s_%s_%s_%s_%d_filetest.gno",
						fileSlug(st.Name), v, wl.mode(), wl.Name, n)
					path := filepath.Join(workdir, name)
					if err := os.WriteFile(path, src, 0o644); err != nil {
						return nil, err
					}
					written[path] = true
					jobs = append(jobs, job{row: r, file: path})
				}
			}
		}
	}
	if !keep {
		defer func() {
			for p := range written {
				os.Remove(p)
			}
			os.Remove(gnomod)
		}()
	}

	// The loader resolves gnowork.toml from the process working directory,
	// the same way `gno test` does, so we move into the generated package.
	// Every path above is absolute, so nothing else cares.
	cwd, _ := os.Getwd()
	if err := os.Chdir(workdir); err != nil {
		return nil, err
	}
	defer os.Chdir(cwd)

	pkgs, err := packages.Load(packages.LoadConfig{
		Out: io.Discard, Deps: true, Test: true, AllowEmpty: true,
	}, ".")
	if err != nil {
		return nil, fmt.Errorf("loading %s: %w", workdir, err)
	}
	opts := test.NewTestOptions(env.GnoRoot, io.Discard, io.Discard, pkgs)

	// One warm-up run, discarded: the first filetest of a process pays to
	// compile every imported package into the store, and that cost would
	// otherwise land on whichever scenario happened to run first.
	for _, j := range jobs {
		if j.file == "" {
			continue
		}
		src, _ := os.ReadFile(j.file)
		opts.RunFiletest(j.file, src, opts.TestStore)
		break
	}

	rows := make([]Row, 0, len(jobs))
	for i := range jobs {
		j := &jobs[i]
		r := j.row
		if j.file == "" {
			rows = append(rows, r)
			continue
		}
		src, err := os.ReadFile(j.file)
		if err != nil {
			return nil, err
		}
		r.Stable = true
		best := time.Duration(0)
		for k := 0; k < repeat; k++ {
			t0 := time.Now()
			_, gas, diffs, ferr := opts.RunFiletest(j.file, src, opts.TestStore)
			d := time.Since(t0)
			if ferr != nil {
				r.Err = firstLine(ferr.Error())
				break
			}
			var by int64
			for _, v := range diffs {
				by += int64(v)
			}
			if k == 0 {
				r.Gas, r.Bytes, best = int64(gas), by, d
			} else {
				if int64(gas) != r.Gas || by != r.Bytes {
					r.Stable = false
				}
				if d < best {
					best = d
				}
			}
		}
		r.WallNs = best.Nanoseconds()
		if verbose {
			fmt.Fprintf(os.Stderr, "%-64s gas=%-13d bytes=%-9d wall=%s %s\n",
				r.Key(), r.Gas, r.Bytes, time.Duration(r.WallNs).Round(time.Millisecond), r.Err)
		}
		rows = append(rows, r)
	}

	Deltas(s, rows)
	return rows, nil
}

// Deltas subtracts each workload's baseline. Both scenarios ran the same code
// up to the measured phase, so the difference is that phase and nothing else.
func Deltas(s *Suite, rows []Row) {
	by := map[string]*Row{}
	for i := range rows {
		by[rows[i].Key()] = &rows[i]
	}
	wl := map[string]Workload{}
	for _, w := range s.Workloads {
		wl[w.Group+"/"+w.Name] = w
	}
	for i := range rows {
		r := &rows[i]
		w := wl[r.Group+"/"+r.Workload]
		if w.Baseline == "" || r.Err != "" || r.Skip != "" {
			r.DGas, r.DBytes, r.DWallNs = r.Gas, r.Bytes, r.WallNs
			continue
		}
		bk := Row{Structure: r.Structure, Value: r.Value, Mode: wl[r.Group+"/"+w.Baseline].mode(), Workload: w.Baseline, N: r.N}
		b, ok := by[bk.Key()]
		if !ok || b.Err != "" {
			continue
		}
		r.DGas, r.DBytes, r.DWallNs = r.Gas-b.Gas, r.Bytes-b.Bytes, r.WallNs-b.WallNs
	}
}

var slugBad = regexp.MustCompile(`[^a-zA-Z0-9]+`)

func fileSlug(s string) string {
	return strings.Trim(slugBad.ReplaceAllString(s, "-"), "-")
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
