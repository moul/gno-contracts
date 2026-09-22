package main

// The gno toolchain runner: `gnocontracts gno <lint|test|fmt|toolcheck|list>`.
//
// This used to be the Makefile: forty lines of shell that found every
// gnomod.toml, dropped the archived ones, materialized the versions with no
// directory, built a stdlib-only image of GNOROOT and only then looped `gno`
// over the result. Each of those steps has a failure mode that is a SILENT
// FALSE GREEN rather than an error (a package skipped, a dependency resolved
// from the wrong tree, an example test not run at all), which is exactly the
// kind of thing to express in code that can be tested rather than in a recipe
// that cannot.

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
)

// viewDir is an ephemeral, stdlib-only image of GNOROOT: every top-level entry
// of the real checkout symlinked in, EXCEPT examples/, which is left empty.
//
// It is what makes a build here reproducible. gno resolves a gno.land/* import
// from GNOROOT/examples before anything else, so without the view every lint,
// test and preview would silently pick up whatever the monorepo checkout
// happens to hold that day instead of the copy committed under vendor/. The
// repository is pinned to its vendored dependencies; the view is how that pin
// is enforced.
const viewDir = ".gnoroot-view"

// toolcheckDir holds the canary `toolcheck` writes. It must live INSIDE this
// workspace: the skip it detects is workspace-dependent, and a byte-identical
// canary under /tmp passes on exactly the broken toolchain this exists to
// catch (verified against gno master.3130: skips in-tree, validates
// out-of-tree). It is a dot-directory so scanContracts never catalogues one
// left behind by an interrupted run.
const toolcheckDir = "p/moul/.toolcheck"

func cmdGno(root string, args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: gnocontracts gno <lint|test|fmt|toolcheck|list> [flags] [packages...]")
	}
	verb := args[0]
	fs := flag.NewFlagSet("gno "+verb, flag.ContinueOnError)
	bin := fs.String("gno", envOr("GNO", "gno"), "gno binary")
	jobs := fs.Int("j", defaultJobs(), "packages to run at once; 1 streams output as it comes")
	noSync := fs.Bool("no-sync", false, "skip `gnopm sync`, assuming .gnopm/ is already current")
	if err := fs.Parse(args[1:]); err != nil {
		return err
	}

	if !*noSync {
		if err := gnopmSync(root); err != nil {
			return err
		}
	}
	view, err := ensureView(root)
	if err != nil {
		return err
	}

	// fmt rewrites files, so it only ever touches the working tree. A
	// superseded version is a read-only copy of history rebuilt into .gnopm/,
	// and reformatting one would make `gnopm verify` fail against the hash it
	// recorded.
	dirs, err := contractDirs(root, verb != "fmt")
	if err != nil {
		return err
	}
	if sel := fs.Args(); len(sel) > 0 {
		dirs = selectDirs(dirs, sel)
		if len(dirs) == 0 {
			return fmt.Errorf("no package matches %s", strings.Join(sel, " "))
		}
	}

	switch verb {
	case "list":
		for _, d := range dirs {
			fmt.Println(d)
		}
		return nil
	case "toolcheck":
		return toolcheck(root, view, *bin)
	case "lint", "test", "fmt":
		return runGno(root, view, *bin, verb, dirs, *jobs)
	default:
		return fmt.Errorf("unknown gno subcommand %q (want lint, test, fmt, toolcheck or list)", verb)
	}
}

// defaultJobs keeps a laptop responsive and stays inside what a CI runner has.
// Every package builds in its own process against a read-only view, so they do
// not interact; the cap is memory, not correctness.
func defaultJobs() int {
	if n := runtime.NumCPU(); n < 8 {
		return max(n, 1)
	}
	return 8
}

// contractDirs is every directory `gno` should be pointed at, relative to the
// repository root and in a stable order: the working tree first, then the
// versions gnopm rebuilt from history.
//
// Archived packages (`ignore = true`) are dropped here because the toolchain
// does not drop them for us: it skips an ignored module for `lint` but builds
// it anyway for a `test` that names it, so CI would try to build a package
// that is in the tree precisely because it no longer builds.
func contractDirs(root string, includeSuperseded bool) ([]string, error) {
	contracts, err := scanContracts(root)
	if err != nil {
		return nil, err
	}
	var live, old []string
	for _, c := range contracts {
		if c.Ignored {
			continue
		}
		if c.Superseded {
			old = append(old, c.srcDir())
			continue
		}
		live = append(live, c.Dir)
	}
	if !includeSuperseded {
		return live, nil
	}
	return append(live, old...), nil
}

// selectDirs filters by substring, so `make lint PKG=daily` and
// `PKG=./r/moul/home` both work.
func selectDirs(dirs, sel []string) []string {
	var out []string
	for _, d := range dirs {
		for _, s := range sel {
			if strings.Contains(d, strings.TrimPrefix(strings.TrimSuffix(s, "/"), "./")) {
				out = append(out, d)
				break
			}
		}
	}
	return out
}

// ensureView (re)builds the stdlib-only GNOROOT image described at viewDir.
//
// It reads the REAL GNOROOT and writes the view; pointing GNOROOT at the view
// and running this would build the view out of itself, leaving gnodev to die
// on `failed loading stdlib "errors": does not exist`. That happened in CI
// while the view was the Makefile's job and the environment was a step's, so
// it is now an error rather than a comment.
func ensureView(root string) (string, error) {
	view := filepath.Join(root, viewDir)
	gnoroot := os.Getenv("GNOROOT")
	if gnoroot == "" {
		return "", fmt.Errorf("GNOROOT must point at a gnolang/gno checkout (it provides the gno stdlibs)")
	}
	abs, err := filepath.Abs(gnoroot)
	if err != nil {
		return "", err
	}
	if abs == view {
		return "", fmt.Errorf("GNOROOT is %s, the ephemeral view: it must name the real gnolang/gno checkout", viewDir)
	}
	entries, err := os.ReadDir(abs)
	if err != nil {
		return "", fmt.Errorf("GNOROOT %s: %w", gnoroot, err)
	}
	if err := os.RemoveAll(view); err != nil {
		return "", err
	}
	if err := os.MkdirAll(filepath.Join(view, "examples"), 0o755); err != nil {
		return "", err
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".") || e.Name() == "examples" {
			continue
		}
		if err := os.Symlink(filepath.Join(abs, e.Name()), filepath.Join(view, e.Name())); err != nil {
			return "", err
		}
	}
	return view, nil
}

// gnoCmd builds a gno invocation rooted at the repository and pointed at the
// view. GNOROOT is set on the CHILD only: this process keeps naming the real
// checkout, so ensureView can still be called after one of these has run.
func gnoCmd(root, view, bin string, args ...string) *exec.Cmd {
	cmd := exec.Command(bin, args...)
	cmd.Dir = root
	cmd.Env = append(os.Environ(), "GNOROOT="+view)
	return cmd
}

func runGno(root, view, bin, verb string, dirs []string, jobs int) error {
	if jobs < 2 || len(dirs) < 2 {
		for _, d := range dirs {
			fmt.Printf("== %s %s ==\n", verb, d)
			cmd := gnoCmd(root, view, bin, verb, "./"+d)
			cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
			if err := cmd.Run(); err != nil {
				return fmt.Errorf("gno %s ./%s: %w", verb, d, err)
			}
		}
		return nil
	}

	// Parallel: each package's output is buffered and printed as one block, so
	// a failure reads whole instead of as lines interleaved with seven other
	// packages'. Blocks appear as they finish, which on a 200-package run is
	// the difference between live progress and four silent minutes.
	var (
		mu     sync.Mutex
		failed []string
		sem    = make(chan struct{}, jobs)
		wg     sync.WaitGroup
	)
	for _, d := range dirs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			var buf bytes.Buffer
			cmd := gnoCmd(root, view, bin, verb, "./"+d)
			cmd.Stdout, cmd.Stderr = &buf, &buf
			err := cmd.Run()
			mu.Lock()
			defer mu.Unlock()
			fmt.Printf("== %s %s ==\n", verb, d)
			os.Stdout.Write(buf.Bytes())
			if err != nil {
				failed = append(failed, d)
			}
		}()
	}
	wg.Wait()

	if len(failed) > 0 {
		sort.Strings(failed)
		return fmt.Errorf("gno %s failed for %d package(s): %s", verb, len(failed), strings.Join(failed, " "))
	}
	return nil
}

// toolcheck proves the gno binary actually VALIDATES example tests.
//
// A toolchain without the feature SKIPS every Example func silently, which
// turns each ExampleRender in this repository into a test that asserts nothing
// and reports ok. So: build a package whose pinned output is deliberately
// wrong, and require `gno test` to fail on it. A pass means the toolchain is
// blind to examples, and everything green here is meaningless.
func toolcheck(root, view, bin string) error {
	dir := filepath.Join(root, filepath.FromSlash(toolcheckDir))
	if err := os.RemoveAll(dir); err != nil {
		return err
	}
	defer os.RemoveAll(dir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	files := map[string]string{
		"gnomod.toml": "module = \"gno.land/p/moul/toolcheck/v1\"\ngno = \"0.9\"\n",
		"x.gno":       "package toolcheck\n\nfunc H() string { return \"hi\" }\n",
		"x_test.gno":  "package toolcheck\n\nfunc ExampleH() {\n\tprint(H())\n\t// Output:\n\t// WRONG-ON-PURPOSE\n}\n",
	}
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			return err
		}
	}
	cmd := gnoCmd(root, view, bin, "test", "./"+toolcheckDir)
	cmd.Stdout, cmd.Stderr = io.Discard, io.Discard
	if cmd.Run() == nil {
		return fmt.Errorf("this gno does NOT validate example tests, so every ExampleRender here is false-green.\n" +
			"       Build one from gnolang/gno master: go build -o gno ./gnovm/cmd/gno")
	}
	fmt.Println("toolcheck: gno validates example tests (workspace-resolved)")
	return nil
}

// gnopmSync materializes the versions that gnomod.lock pins to a commit rather
// than to a directory, so lint and test can build them and the packages still
// importing them resolve. Idempotent and quiet when there is nothing to do.
//
// gnopm's own -C, never `go -C`: `go -C` sets the working directory of the go
// command and the tool inherits it, so running this from elsewhere would sync
// whichever tree the go command was pointed at.
func gnopmSync(root string) error {
	cmd := exec.Command("go", "tool", "gnopm", "-C", root, "sync")
	cmd.Dir = filepath.Join(root, "tools")
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("gnopm sync: %w", err)
	}
	return nil
}
