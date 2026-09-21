package main

// Static gnoweb previews of this repository.
//
// Two questions, one renderer:
//
//	gnocontracts preview -all -out _site               # every package, for main
//	gnocontracts preview -changed changed.txt -out _p  # what a pull request touched
//
// It boots gnodev on the whole workspace, crawls the resulting gnoweb into a
// self-contained static tree (see preview_crawl.go), and writes preview.json
// plus a comment fragment next to it.
//
// gnodev is given EVERY package in the workspace, not just the ones being
// crawled, because a package here is versioned in gnomod.toml rather than in
// its directory path: gnodev cannot find gno.land/p/moul/authz/v0 by walking to
// p/moul/authz/v0, and lazy loading makes the whole workspace cost the same as
// one package (measured 2026-09-21: 193 packages, node ready in 9s).

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
)

const (
	// defaultLive is where a link that leaves the snapshot goes.
	defaultLive = "https://gno.land"
	// prMaxPkgs caps a pull-request preview. Changed packages are never
	// dropped; dependents are, and the comment says how many.
	prMaxPkgs = 25
	// prMaxPages backstops the crawl of a pull-request preview, siteMaxPages
	// the whole repository (measured: ~1.1k pages for 193 packages).
	prMaxPages   = 400
	siteMaxPages = 3000
	// defaultArgBudget caps render-argument pages per package: the one axis a
	// realm can enumerate without bound. See Crawler.ArgBudget.
	defaultArgBudget = 10
)

// previewPlan is what the preview job decided to do, written to preview.json so
// the workflow and the pull request comment read the same answer.
type previewPlan struct {
	Mode string `json:"mode"` // "site" or "pr"
	// Changed are packages whose own sources the pull request touched.
	Changed []string `json:"changed,omitempty"`
	// Dependents are packages pulled in because they (transitively) import a
	// changed package.
	Dependents []string `json:"dependents,omitempty"`
	// Paths is what actually gets crawled, changed packages first.
	Paths []string `json:"paths"`
	// Dropped counts packages left out by the cap — never silently.
	Dropped int `json:"dropped,omitempty"`
	// ChangedFiles maps a package to the base names of its files the pull
	// request touched. Per-file $source pages are rendered only for these.
	ChangedFiles map[string][]string `json:"changed_files,omitempty"`
	// New are packages this pull request adds, asserted from the merge-base
	// tree rather than inferred from a missing render.
	New   []string   `json:"new,omitempty"`
	Pairs []shotPair `json:"pairs,omitempty"`
	Pages int        `json:"pages"`
}

func (p *previewPlan) empty() bool { return len(p.Paths) == 0 }

func cmdPreview(root string, args []string) error {
	fs := flag.NewFlagSet("preview", flag.ContinueOnError)
	out := fs.String("out", "_preview", "output directory")
	all := fs.Bool("all", false, "preview every package in the workspace (the main snapshot)")
	changed := fs.String("changed", "", "file holding the paths a pull request changed, one per line (- for stdin)")
	baseRoot := fs.String("base-root", "", "checkout of the merge base; enables before/after screenshots")
	baseURL := fs.String("base-url", "", "public URL the snapshot will be served from (for the comment)")
	pr := fs.String("pr", "", "pull request number (for the comment)")
	planOnly := fs.Bool("plan-only", false, "write preview.json and stop, without booting gnodev")
	live := fs.String("live", defaultLive, "origin used for links the snapshot does not contain")
	maxPkgs := fs.Int("max-pkgs", prMaxPkgs, "cap on previewed packages; 0 for no cap")
	maxPages := fs.Int("max-pages", 0, "cap on crawled pages; 0 picks the default for the mode")
	maxArgs := fs.Int("max-args", defaultArgBudget, "cap on render-argument pages per package")
	port := fs.Int("port", 8899, "port gnodev serves gnoweb on")
	gnodev := fs.String("gnodev", envOr("GNODEV", "gnodev"), "gnodev binary")
	chrome := fs.String("chrome", "", "Chrome/Chromium binary for screenshots (default: autodetect)")
	timeout := fs.Duration("timeout", 5*time.Minute, "how long to wait for gnodev to come up")
	if err := fs.Parse(args); err != nil {
		return err
	}

	contracts, err := scanContracts(root)
	if err != nil {
		return err
	}
	plan, err := buildPreviewPlan(contracts, *all, *changed, fs.Args(), *maxPkgs)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(*out, 0o755); err != nil {
		return err
	}
	// An empty plan writes preview.json and nothing else: a pull request that
	// touches no package gets no comment fragment, which is what makes the
	// workflow skip in silence rather than post an empty section.
	if plan.empty() || *planOnly {
		if plan.empty() {
			fmt.Println("nothing to preview")
		} else {
			fmt.Printf("would preview %d package(s) in %s mode\n", len(plan.Paths), plan.Mode)
		}
		return writePreviewJSON(*out, plan)
	}
	if *maxPages == 0 {
		*maxPages = prMaxPages
		if plan.Mode == "site" {
			*maxPages = siteMaxPages
		}
	}

	fmt.Printf("previewing %d package(s) in %s mode\n", len(plan.Paths), plan.Mode)
	dirs, err := workspacePkgDirs(root)
	if err != nil {
		return err
	}
	stop, died, err := startGnodev(*gnodev, root, dirs, *out, *port, "gnodev.log")
	if err != nil {
		return err
	}
	defer stop()

	c := &Crawler{
		Base:         fmt.Sprintf("http://127.0.0.1:%d", *port),
		Paths:        plan.Paths,
		MaxPages:     *maxPages,
		Live:         strings.TrimSuffix(*live, "/"),
		ChangedFiles: plan.ChangedFiles,
		FileBudget:   0,
		ArgBudget:    *maxArgs,
	}
	if plan.Mode == "site" {
		// 209 non-test .gno files in the whole repository: every one of them is
		// affordable, and on the main snapshot every one of them is the point.
		c.FileBudget = unlimitedFiles
	}
	if err := waitServing(c.Base, gnowebPath(plan.Paths[0]), *timeout, died); err != nil {
		return err
	}
	if err := c.Run(); err != nil {
		return err
	}
	assets, err := gnowebAssets()
	if err != nil {
		return err
	}
	if err := c.Write(*out, assets); err != nil {
		return err
	}
	plan.Pages = c.Pages()
	if err := writeOut(filepath.Join(*out, "index.html"), previewIndex(plan, c, *pr)); err != nil {
		return err
	}

	if len(plan.Changed) > 0 {
		base, newPkgs := renderBase(*gnodev, *baseRoot, *out, plan, c, *port, *live, *timeout)
		for p := range newPkgs {
			plan.New = append(plan.New, p)
		}
		sort.Strings(plan.New)
		plan.Pairs = screenshotPairs(*out, c, base, plan.Changed, newPkgs, *chrome)
	}
	if err := writePreviewJSON(*out, plan); err != nil {
		return err
	}
	if *baseURL != "" {
		if err := writeOut(filepath.Join(*out, "preview.md"), previewComment(plan, *baseURL)); err != nil {
			return err
		}
	}
	fmt.Printf("done: %d page(s), %d before/after pair(s) -> %s\n", plan.Pages, len(plan.Pairs), *out)
	return nil
}

// buildPreviewPlan decides which packages to crawl.
//
// Selectors and -changed are both pull-request shaped; -all (or no argument at
// all) is the whole-repository snapshot.
func buildPreviewPlan(contracts []Contract, all bool, changedFile string, selectors []string, maxPkgs int) (*previewPlan, error) {
	live := make([]Contract, 0, len(contracts))
	for _, c := range contracts {
		if c.Ignored {
			continue // archived: it does not build, and gnodev would not load it
		}
		live = append(live, c)
	}

	if all || (changedFile == "" && len(selectors) == 0) {
		plan := &previewPlan{Mode: "site"}
		for _, c := range live {
			plan.Paths = append(plan.Paths, c.PkgPath)
		}
		sort.Strings(plan.Paths)
		return plan, nil
	}

	plan := &previewPlan{Mode: "pr", ChangedFiles: map[string][]string{}}
	changedSet := map[string]bool{}
	if changedFile != "" {
		paths, err := readPathList(changedFile)
		if err != nil {
			return nil, err
		}
		for pkg, files := range changedPackages(live, paths) {
			changedSet[pkg] = true
			if len(files) > 0 {
				plan.ChangedFiles[pkg] = files
			}
		}
	}
	for _, c := range live {
		if matchesSelector(c.Dir, selectors) {
			changedSet[c.PkgPath] = true
		}
	}

	// A changed pure package is worth looking at itself (its source view), and
	// it also changes every realm that imports it.
	dependents := reverseDeps(live, changedSet)

	byPath := map[string]Contract{}
	for _, c := range live {
		byPath[c.PkgPath] = c
	}
	// Realms before pure packages within each group: a reviewer looks at what
	// renders first, and the cap should spend itself there.
	order := func(paths []string) []string {
		var realms, pure []string
		for _, p := range paths {
			if byPath[p].Kind == "r" {
				realms = append(realms, p)
			} else {
				pure = append(pure, p)
			}
		}
		sort.Strings(realms)
		sort.Strings(pure)
		return append(realms, pure...)
	}
	plan.Changed = order(sortedStrings(changedSet))
	plan.Dependents = order(sortedStrings(dependents))

	plan.Paths = append(append([]string{}, plan.Changed...), plan.Dependents...)
	if maxPkgs > 0 && len(plan.Paths) > maxPkgs {
		plan.Dropped = len(plan.Paths) - maxPkgs
		plan.Paths = plan.Paths[:maxPkgs]
	}
	return plan, nil
}

// changedPackages maps the paths a pull request touched onto the packages they
// belong to, and to the file names inside them.
//
// Test files are excluded: they cannot change what a package renders, and a
// preview that reacts to them spends a gnodev build on nothing.
func changedPackages(contracts []Contract, paths []string) map[string][]string {
	out := map[string][]string{}
	for _, p := range paths {
		p = filepath.ToSlash(p)
		if isTestGno(p) || strings.Contains(p, "/filetests/") {
			continue
		}
		best := ""
		var bestPkg string
		for _, c := range contracts {
			if c.Superseded {
				continue // its directory is a historical path, not a live one
			}
			if p == c.Dir || strings.HasPrefix(p, c.Dir+"/") {
				if len(c.Dir) > len(best) {
					best, bestPkg = c.Dir, c.PkgPath
				}
			}
		}
		if bestPkg == "" {
			continue
		}
		if _, ok := out[bestPkg]; !ok {
			out[bestPkg] = nil
		}
		if strings.HasSuffix(p, ".gno") {
			out[bestPkg] = append(out[bestPkg], path.Base(p))
		}
	}
	return out
}

// reverseDeps walks the import graph backwards from the changed set and returns
// everything that reaches it, excluding the changed packages themselves.
func reverseDeps(contracts []Contract, changed map[string]bool) map[string]bool {
	importers := map[string][]string{}
	for _, c := range contracts {
		for _, d := range c.Deps {
			importers[d] = append(importers[d], c.PkgPath)
		}
	}
	out := map[string]bool{}
	queue := sortedStrings(changed)
	for len(queue) > 0 {
		p := queue[0]
		queue = queue[1:]
		for _, imp := range importers[p] {
			if changed[imp] || out[imp] {
				continue
			}
			out[imp] = true
			queue = append(queue, imp)
		}
	}
	return out
}

// workspacePkgDirs is every directory gnodev should load: the packages in the
// tree, plus the superseded versions `gnopm sync` materialized under .gnopm/.
// Archived (`ignore = true`) packages are left out; they do not build.
func workspacePkgDirs(root string) ([]string, error) {
	contracts, err := scanContracts(root)
	if err != nil {
		return nil, err
	}
	var dirs []string
	for _, c := range contracts {
		if c.Ignored {
			continue
		}
		dir := c.Dir
		if c.Superseded {
			dir = path.Join(assemblyDir, c.PkgPath)
		}
		abs := filepath.Join(root, filepath.FromSlash(dir))
		if !fileExists(filepath.Join(abs, "gnomod.toml")) {
			// A superseded version nobody ran `gnopm sync` for. Everything that
			// imports it will fail to load; say so once, here, rather than as
			// an unexplained 500 on some other package's page.
			fmt.Fprintf(os.Stderr, "  ! %s is not materialized (run `gnopm sync`) — skipping\n", c.PkgPath)
			continue
		}
		dirs = append(dirs, abs)
	}
	sort.Strings(dirs)
	return dirs, nil
}

// startGnodev boots gnodev on the workspace. GNOROOT comes from the environment
// and should be the stdlib-only view the Makefile builds (`make view`), so
// gno.land/* dependencies resolve from committed vendor/ exactly as they do for
// lint and test, rather than from whatever the monorepo checkout happens to
// hold.
func startGnodev(bin, root string, dirs []string, out string, port int, logName string) (func(), <-chan error, error) {
	args := []string{
		"local", "-no-watch",
		"-web-listener", fmt.Sprintf("127.0.0.1:%d", port),
		// The RPC listener and the keybase both default to fixed locations, so
		// the before/after passes — which run one after the other but leave
		// state behind — would collide on them. Derive both from the web port.
		"-node-rpc-listener", fmt.Sprintf("tcp://127.0.0.1:%d", port+10000),
		"-home", filepath.Join(out, fmt.Sprintf(".gnodev-%d", port)),
		"-C", root,
	}
	args = append(args, dirs...)
	log, err := os.Create(filepath.Join(out, logName))
	if err != nil {
		return nil, nil, err
	}
	cmd := exec.Command(bin, args...)
	cmd.Stdout, cmd.Stderr = log, log
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		log.Close()
		return nil, nil, fmt.Errorf("start gnodev: %w", err)
	}
	// Nothing else watches this process. Without the channel, a gnodev that
	// dies on startup (a port already taken, a package that will not load)
	// costs the full readiness timeout and reports "not ready", which says
	// nothing about why.
	died := make(chan error, 1)
	waited := make(chan struct{})
	go func() {
		died <- cmd.Wait()
		close(waited)
	}()
	return func() {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) // gnodev spawns a node
		<-waited
		log.Close()
	}, died, nil
}

// renderBase renders the changed packages a second time from the merge-base
// checkout, into <out>/_before/. It reuses the head's gnodev binary and the
// head's assets on purpose: the pair must differ by the package change alone,
// not by whatever else moved on main. Returns nil when there is no base
// checkout, when every changed package is new, or when the pass fails — a
// missing "before" costs the comment one image, not the preview.
func renderBase(gnodev, baseRoot, out string, plan *previewPlan, head *Crawler, port int, live string, timeout time.Duration) (*Crawler, map[string]bool) {
	if baseRoot == "" {
		return nil, nil
	}
	newPkgs := map[string]bool{}
	var paths []string
	for _, p := range plan.Changed {
		if _, err := os.Stat(filepath.Join(baseRoot, "gnowork.toml")); err != nil {
			return nil, nil
		}
		dir, err := packageDirIn(baseRoot, p)
		if err != nil || dir == "" {
			newPkgs[p] = true // genuinely added by this pull request
			continue
		}
		paths = append(paths, p)
	}
	if len(paths) == 0 {
		return nil, newPkgs
	}
	dirs, err := workspacePkgDirs(baseRoot)
	if err != nil {
		fmt.Fprintln(os.Stderr, "  ! base render:", err)
		return nil, newPkgs
	}
	basePort := port + 1
	stop, died, err := startGnodev(gnodev, baseRoot, dirs, out, basePort, "gnodev-base.log")
	if err != nil {
		fmt.Fprintln(os.Stderr, "  ! base render:", err)
		return nil, newPkgs
	}
	defer stop()

	base := &Crawler{
		Base:       fmt.Sprintf("http://127.0.0.1:%d", basePort),
		Paths:      paths,
		MaxPages:   len(paths),
		Live:       strings.TrimSuffix(live, "/"),
		RenderOnly: true,
		Prefix:     beforeDir,
	}
	for _, step := range []func() error{
		func() error { return waitServing(base.Base, gnowebPath(paths[0]), timeout, died) },
		base.Run,
		func() error { return base.Write(out, "") },
	} {
		if err := step(); err != nil {
			fmt.Fprintln(os.Stderr, "  ! base render:", err)
			return nil, newPkgs
		}
	}
	return base, newPkgs
}

// packageDirIn finds where a package path lives in another checkout, by module
// line rather than by directory: a bump moves gno.land/p/moul/md/v1 from
// p/moul/md/v1 to p/moul/md without either path telling you so.
func packageDirIn(root, pkgPath string) (string, error) {
	contracts, err := scanContracts(root)
	if err != nil {
		return "", err
	}
	for _, c := range contracts {
		if c.PkgPath == pkgPath && !c.Superseded {
			return c.Dir, nil
		}
	}
	return "", nil
}

// gnowebAssets locates gnoweb's public/ tree inside GNOROOT.
func gnowebAssets() (string, error) {
	gnoroot := os.Getenv("GNOROOT")
	if gnoroot == "" {
		return "", fmt.Errorf("GNOROOT is not set (it must point at a gnolang/gno checkout, or the stdlib-only view `make view` builds)")
	}
	p := filepath.Join(gnoroot, "gno.land", "pkg", "gnoweb", "public")
	if !fileExists(p) {
		return "", fmt.Errorf("%s: gnoweb assets not found under GNOROOT", p)
	}
	return p, nil
}

func readPathList(p string) ([]string, error) {
	var b []byte
	var err error
	if p == "-" {
		b, err = os.ReadFile("/dev/stdin")
	} else {
		b, err = os.ReadFile(p)
	}
	if err != nil {
		return nil, err
	}
	var out []string
	for _, l := range strings.Split(string(b), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out, nil
}

func writePreviewJSON(out string, plan *previewPlan) error {
	b, err := json.MarshalIndent(plan, "", "  ")
	if err != nil {
		return err
	}
	return writeOut(filepath.Join(out, "preview.json"), string(b)+"\n")
}

// matchesSelector applies the `./...`, `./dir/...`, `./dir` forms.
func matchesSelector(dir string, selectors []string) bool {
	for _, sel := range selectors {
		s := strings.TrimSuffix(strings.TrimPrefix(strings.TrimPrefix(sel, "./"), "/"), "/")
		switch {
		case s == "" || s == "...":
			return true
		case strings.HasSuffix(s, "/..."):
			base := strings.TrimSuffix(s, "/...")
			if dir == base || strings.HasPrefix(dir, base+"/") {
				return true
			}
		case dir == s || strings.HasPrefix(dir, s+"/"):
			return true
		}
	}
	return false
}
