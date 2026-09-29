// gnobench measures what a gno construct costs, by theme.
//
// Each suite is one themed comparison. "storage" asks where a realm should put
// its data; a second suite is a new file, not a new tool.
//
// Every measurement is one generated filetest run through gnovm's own filetest
// runner, which returns gas and the realm's storage diff; the harness times the
// call itself for wall nanoseconds. Results are stored per machine, so two
// machines keep two files and re-running updates rows in place. Reports are
// generated from whatever is on disk, never hand-written.
//
//	gnobench run    -suite storage -n 100,1000,10000
//	gnobench report -suite storage
//	gnobench list
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "gnobench:", err)
		os.Exit(1)
	}
}

func usage() error {
	fmt.Fprint(os.Stderr, `gnobench <command> [flags]

  run      measure a suite and merge the results into this machine's file
  report   regenerate the reports, the charts and the README region from every result file
  list     what suites, candidates and workloads exist
  compare  diff two result files and print what moved, as markdown
  affected read changed paths on stdin, print the -filter regexp they imply
  env      print this machine's id and toolchain, as JSON

Run "gnobench <command> -h" for the flags.
`)
	return fmt.Errorf("no command")
}

func run() error {
	if len(os.Args) < 2 {
		return usage()
	}
	cmd := os.Args[1]
	args := os.Args[2:]
	switch cmd {
	case "run":
		return cmdRun(args)
	case "report":
		return cmdReport(args)
	case "list":
		return cmdList(args)
	case "compare":
		return cmdCompare(args)
	case "affected":
		return cmdAffected(args)
	case "env":
		return cmdEnv(args)
	case "-h", "--help", "help":
		return usage()
	}
	return fmt.Errorf("unknown command %q", cmd)
}

func repoRoot(root string) (string, error) { return filepath.Abs(root) }

func cmdRun(args []string) error {
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	var (
		suite   = fs.String("suite", "storage", "which suite to measure")
		root    = fs.String("root", ".", "the gnobench directory: results/ and reports/ live here")
		gnoroot = fs.String("gnoroot", os.Getenv("GNOROOT"), "a gnolang/gno checkout, for the stdlibs")
		workdir = fs.String("workdir", "../.gno/scratch/gnobench", "where to generate; must sit inside the gno workspace that resolves the imports")
		nlist   = fs.String("n", "100,1000,10000", "comma-separated element counts")
		values  = fs.String("value", "str,obj", "comma-separated value shapes: str, obj")
		repeat  = fs.Int("repeat", 2, "runs per scenario; gas and bytes must agree across them, the fastest wall time wins")
		filter  = fs.String("filter", "", "regexp against candidate/workload")
		keep    = fs.Bool("keep", false, "keep the generated .gno sources")
		noWrite = fs.Bool("dry-run", false, "measure but do not touch the result file")
		verbose = fs.Bool("v", false, "log every scenario as it runs")
	)
	if err := fs.Parse(args); err != nil {
		return err
	}
	s, ok := suites[*suite]
	if !ok {
		return fmt.Errorf("unknown suite %q (have: %s)", *suite, strings.Join(suiteNames(), ", "))
	}
	if *gnoroot == "" {
		return fmt.Errorf("-gnoroot is required (or set GNOROOT)")
	}
	ns, err := intList(*nlist)
	if err != nil {
		return err
	}
	var vals []string
	for _, v := range strings.Split(*values, ",") {
		v = strings.TrimSpace(v)
		if _, ok := valueExprs[v]; !ok {
			return fmt.Errorf("unknown -value %q", v)
		}
		vals = append(vals, v)
	}
	var re *regexp.Regexp
	if *filter != "" {
		if re, err = regexp.Compile(*filter); err != nil {
			return err
		}
	}
	abs, err := repoRoot(*root)
	if err != nil {
		return err
	}
	env := DetectEnv(*gnoroot)
	fmt.Fprintf(os.Stderr, "gnobench: suite %s on %s\n  env   %s\n  go    %s\n  gno   %s\n",
		s.Name, env.ID, env.Short(), env.GoVer, env.GnoShort())

	rows, err := Run(s, env, *workdir, ns, vals, *repeat, re, *verbose, *keep)
	if err != nil {
		return err
	}
	measured, failed := 0, 0
	for _, r := range rows {
		if r.Err != "" {
			failed++
		} else if r.Skip == "" {
			measured++
		}
	}
	fmt.Fprintf(os.Stderr, "gnobench: %d measured, %d failed, %d skipped\n",
		measured, failed, len(rows)-measured-failed)
	if *noWrite {
		return nil
	}
	f, err := LoadFile(abs, s.Name, env)
	if err != nil {
		return err
	}
	added, replaced := f.Merge(rows)
	if err := f.Save(); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "gnobench: %s: %d new rows, %d updated, %d total\n",
		mustRel(abs, f.path), added, replaced, len(f.Rows))
	if err := generate(abs, s); err != nil {
		return err
	}
	return refreshREADME(abs, false)
}

func cmdReport(args []string) error {
	fs := flag.NewFlagSet("report", flag.ExitOnError)
	var (
		suite = fs.String("suite", "", "which suite, or empty for all")
		root  = fs.String("root", ".", "the gnobench directory")
		check = fs.Bool("check", false, "write nothing: exit 1 if the README's generated region is stale")
	)
	if err := fs.Parse(args); err != nil {
		return err
	}
	abs, err := repoRoot(*root)
	if err != nil {
		return err
	}
	if *check {
		return refreshREADME(abs, true)
	}
	for _, name := range suiteNames() {
		if *suite != "" && *suite != name {
			continue
		}
		if err := generate(abs, suites[name]); err != nil {
			return err
		}
	}
	return refreshREADME(abs, false)
}

// refreshREADME rewrites the generated region, or in check mode reports that it
// would have to. CI uses the check so a pull request cannot land a README that
// disagrees with the results committed beside it.
func refreshREADME(root string, check bool) error {
	before, err := os.ReadFile(filepath.Join(root, "README.md"))
	if err != nil {
		return err
	}
	if err := updateREADME(root); err != nil {
		return err
	}
	after, err := os.ReadFile(filepath.Join(root, "README.md"))
	if err != nil {
		return err
	}
	changed := string(before) != string(after)
	if check {
		if changed {
			if err := os.WriteFile(filepath.Join(root, "README.md"), before, 0o644); err != nil {
				return err
			}
			return fmt.Errorf("README.md is stale: its generated region does not match results/. Run `make report` and commit")
		}
		fmt.Fprintln(os.Stderr, "gnobench: README.md is up to date")
		return nil
	}
	if changed {
		fmt.Fprintln(os.Stderr, "gnobench: rewrote the generated region of README.md")
	}
	return nil
}

func cmdList(args []string) error {
	fs := flag.NewFlagSet("list", flag.ExitOnError)
	suite := fs.String("suite", "", "detail one suite")
	if err := fs.Parse(args); err != nil {
		return err
	}
	for _, name := range suiteNames() {
		s := suites[name]
		fmt.Printf("%s: %s\n  %s\n", s.Name, s.Title, s.Blurb)
		if *suite != "" && *suite != name {
			continue
		}
		fmt.Printf("  candidates (%d):\n", len(s.Structures))
		for _, st := range s.Structures {
			fmt.Printf("    %-34s %-6s %s\n", st.Name, st.Group, strings.Join(st.Tags, " "))
		}
		fmt.Printf("  workloads (%d):\n", len(s.Workloads))
		for _, w := range s.Workloads {
			fmt.Printf("    %-16s %-6s %-5s %s\n", w.Name, w.Group, w.mode(), w.Note)
		}
	}
	return nil
}

func cmdEnv(args []string) error {
	fs := flag.NewFlagSet("env", flag.ExitOnError)
	var (
		gnoroot = fs.String("gnoroot", os.Getenv("GNOROOT"), "a gnolang/gno checkout")
		idOnly  = fs.Bool("id", false, "print only the machine id, which is the result filename")
	)
	if err := fs.Parse(args); err != nil {
		return err
	}
	e := DetectEnv(*gnoroot)
	if *idOnly {
		fmt.Println(e.ID)
		return nil
	}
	os.Stdout.Write(mustJSON(e))
	return nil
}

func suiteNames() []string {
	var out []string
	for k := range suites {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func intList(s string) ([]int, error) {
	var out []int
	for _, p := range strings.Split(s, ",") {
		n, err := strconv.Atoi(strings.TrimSpace(p))
		if err != nil {
			return nil, fmt.Errorf("bad number %q: %w", p, err)
		}
		out = append(out, n)
	}
	return out, nil
}

func mustRel(base, p string) string {
	r, err := filepath.Rel(base, p)
	if err != nil {
		return p
	}
	return r
}

// generate rebuilds every artifact for a suite from the result files. It is
// the only writer of reports/, so a report can never disagree with the data.
func generate(root string, s *Suite) error {
	files, err := LoadAll(root, s.Name)
	if err != nil {
		return err
	}
	if len(files) == 0 {
		fmt.Fprintf(os.Stderr, "gnobench: no results for suite %s yet\n", s.Name)
		return nil
	}
	if err := os.MkdirAll(filepath.Join(root, "reports"), 0o755); err != nil {
		return err
	}
	md := filepath.Join(root, "reports", s.Name+".md")
	if err := os.WriteFile(md, []byte(Markdown(s, files)), 0o644); err != nil {
		return err
	}
	html := filepath.Join(root, "reports", s.Name+".html")
	if err := writeHTML(s, files, html); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "gnobench: wrote %s and %s from %d result file(s)\n",
		mustRel(root, md), mustRel(root, html), len(files))
	return nil
}
