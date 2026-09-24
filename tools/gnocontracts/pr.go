package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// The pull-request bot.
//
// One command answers everything CI needs to know about a pull request, because
// all of it is the same question — "which packages does this diff touch" — asked
// three ways. It used to be three implementations: a Go reporter, a shell loop
// in pr-label that classified paths, and another shell loop in pr-preview that
// walked up to the nearest gnomod.toml. They could disagree, and did.
//
//	go tool gnocontracts pr -base origin/main \
//	  -preview-url https://moul.github.io/gno-contracts/pr-12/ \
//	  -out comment.md -labels-out labels.txt -selectors-out selectors.txt
//
// Output contract:
//   - -out           the sticky comment body, Markdown (default: stdout)
//   - -labels-out    the `gh pr edit` arguments that reconcile the path labels
//   - -selectors-out the changed realm directories, one `./<dir>` per line

// prMarker identifies the single sticky comment. One marker, one comment: this
// used to be two bots posting two comments (`gnocontracts-pr-report` and
// `gnocontracts-pr-preview`). Both legacy markers still contain the substring
// `gnocontracts-pr`, which is what CI greps for — so a pull request opened
// before the merge converges to one comment on its next push, with the extras
// deleted.
const prMarker = "<!-- gnocontracts-pr -->"

// managedLabels are the path labels the bot owns: it adds those that apply and
// removes those that no longer do, every run. Any other label (enhancement,
// bug, …) is hand-applied and left untouched.
var managedLabels = []string{"p", "r", "meta", "other"}

// labelArgs renders the reconciliation as `gh pr edit` arguments, so the
// workflow is one line and the label set has exactly one owner: this file.
func labelArgs(applies []string) []string {
	has := map[string]bool{}
	for _, l := range applies {
		has[l] = true
	}
	var args []string
	for _, l := range managedLabels {
		if has[l] {
			args = append(args, "--add-label", l)
		} else {
			args = append(args, "--remove-label", l)
		}
	}
	return args
}

type fstat struct{ add, del int }

// pkgAgg is one package's share of the diff.
type pkgAgg struct {
	dir       string
	pkgPath   string // gno.land/r/moul/x/daily/blog/v1
	add, del  int
	isNew     bool
	changedGo bool
	tests     int
	flags     []prFlag
}

// prFlag is a signal worth surfacing about a package.
type prFlag struct {
	emoji string
	label string
}

type prAnalysis struct {
	files            int
	totAdd, totDel   int
	newPkgs, updPkgs []*pkgAgg
	labels           []string
	selectors        []string // changed realm dirs, `./r/moul/...`
	byDir            map[string]*Contract
}

func cmdPR(root string, args []string) error {
	fs := flag.NewFlagSet("pr", flag.ContinueOnError)
	base := fs.String("base", "origin/main", "base ref to diff against")
	previewURL := fs.String("preview-url", "", "base URL of the published preview, if any")
	out := fs.String("out", "", "write the comment body here (default: stdout)")
	labelsOut := fs.String("labels-out", "", "write the `gh pr edit` label arguments here")
	selectorsOut := fs.String("selectors-out", "", "write the changed realm selectors here, one per line")
	previewDetail := fs.String("preview-detail", "", "markdown fragment written by `preview`, folded under the preview link")
	gnopmReport := fs.String("gnopm-report", "", "markdown written by `gnopm tool ci`, folded into the comment")
	if err := fs.Parse(args); err != nil {
		return err
	}

	// Relative paths are repo-root relative, not process relative: CI invokes
	// this as `go -C tools tool gnocontracts`, which runs the tool in tools/.
	// A bare `_preview/preview.md` read from there is simply missing, and a
	// missing detail file is indistinguishable from "the preview has not been
	// rendered yet" — so the comment silently lost its preview section.
	*previewDetail = underRoot(root, *previewDetail)
	*gnopmReport = underRoot(root, *gnopmReport)

	a, err := analyzePR(root, *base)
	if err != nil {
		return err
	}

	body := renderPRComment(root, a, *base, *previewURL, readPreviewDetail(*previewDetail), readGnopmReport(*gnopmReport))
	if *out == "" {
		fmt.Print(body)
	} else if err := os.WriteFile(*out, []byte(body), 0o644); err != nil {
		return err
	}
	if err := writeLines(*labelsOut, labelArgs(a.labels)); err != nil {
		return err
	}
	return writeLines(*selectorsOut, a.selectors)
}

func writeLines(path string, lines []string) error {
	if path == "" {
		return nil
	}
	var b strings.Builder
	for _, l := range lines {
		b.WriteString(l + "\n")
	}
	return os.WriteFile(path, []byte(b.String()), 0o644)
}

// analyzePR reads the diff base...HEAD once and derives everything from it.
func analyzePR(root, base string) (*prAnalysis, error) {
	spec := base + "...HEAD"
	a := &prAnalysis{byDir: map[string]*Contract{}}

	files := map[string]fstat{}
	for _, ln := range gitLines(root, "diff", "--numstat", spec) {
		f := strings.Fields(ln)
		if len(f) < 3 {
			continue
		}
		// binary files report "-" instead of a count; they still count as files.
		add, _ := strconv.Atoi(f[0])
		del, _ := strconv.Atoi(f[1])
		files[f[2]] = fstat{add, del}
		a.totAdd += add
		a.totDel += del
	}
	a.files = len(files)

	added := map[string]bool{}
	for _, ln := range gitLines(root, "diff", "--name-status", spec) {
		if f := strings.Fields(ln); len(f) >= 2 && f[0] == "A" {
			added[f[1]] = true
		}
	}

	m, _ := loadManifest(root)
	if m != nil {
		for i := range m.Contracts {
			a.byDir[filepath.ToSlash(m.Contracts[i].Dir)] = &m.Contracts[i]
		}
	}

	pkgs := map[string]*pkgAgg{}
	for path, st := range files {
		a.labels = classifyPath(path, a.labels)
		if !strings.HasPrefix(path, "p/") && !strings.HasPrefix(path, "r/") {
			continue
		}
		dir := packageDirOf(root, path)
		if dir == "" {
			continue
		}
		p := pkgs[dir]
		if p == nil {
			p = &pkgAgg{dir: dir}
			pkgs[dir] = p
		}
		p.add += st.add
		p.del += st.del
		if strings.HasSuffix(path, ".gno") {
			p.changedGo = true
		}
		if added[filepath.ToSlash(filepath.Join(dir, "gnomod.toml"))] {
			p.isNew = true
		}
	}

	for _, p := range pkgs {
		p.pkgPath = modulePath(root, p.dir, a.byDir[p.dir])
		p.tests = countTests(root, p.dir)
		p.flags = flagsFor(root, p, a.byDir[p.dir])
		if p.isNew {
			a.newPkgs = append(a.newPkgs, p)
		} else {
			a.updPkgs = append(a.updPkgs, p)
		}
		if sel, ok := previewSelector(root, p.dir); ok {
			a.selectors = append(a.selectors, sel)
		}
	}
	byDir := func(l []*pkgAgg) { sort.Slice(l, func(i, j int) bool { return l[i].dir < l[j].dir }) }
	byDir(a.newPkgs)
	byDir(a.updPkgs)
	sort.Strings(a.selectors)
	sort.Strings(a.labels)
	return a, nil
}

// classifyPath adds the label a changed path implies.
//
// vendor/, _assets/, contracts.json and gnomod.lock are NEUTRAL: a vendored
// dependency, a generated artifact and a lock entry are consequences of a
// change, never its intent, so they contribute no label of their own.
func classifyPath(path string, labels []string) []string {
	add := func(l string) []string {
		for _, x := range labels {
			if x == l {
				return labels
			}
		}
		return append(labels, l)
	}
	switch {
	case strings.HasPrefix(path, "vendor/"), strings.HasPrefix(path, "_assets/"),
		path == "contracts.json", path == "gnomod.lock":
		return labels
	case strings.HasPrefix(path, "p/"):
		return add("p")
	case strings.HasPrefix(path, "r/"):
		return add("r")
	case strings.HasPrefix(path, ".github/"), strings.HasPrefix(path, "tools/"),
		path == "Makefile", path == "go.mod", path == "go.sum", path == "gnowork.toml",
		strings.HasPrefix(path, "."), strings.HasSuffix(path, ".md") && !strings.Contains(path, "/"):
		return add("meta")
	default:
		return add("other")
	}
}

// previewSelector returns the `./<dir>` selector for a realm worth rendering,
// or false for a pure package or an archived one.
func previewSelector(root, dir string) (string, bool) {
	if !strings.HasPrefix(dir, "r/") {
		return "", false
	}
	ignored, err := moduleIgnored(filepath.Join(root, filepath.FromSlash(dir), "gnomod.toml"))
	if err != nil || ignored {
		return "", false
	}
	return "./" + dir, true
}

// flagsFor collects the signals worth flagging about a package.
//
// Being under an `/x/` path is deliberately NOT one: nearly everything here is
// experimental, the path says so on every row, and one line per package repeated
// for a dozen packages is what made this comment unreadable.
func flagsFor(root string, p *pkgAgg, c *Contract) []prFlag {
	var out []prFlag
	if usesImport(root, p.dir, "chain/runtime/unsafe") || usesToken(root, p.dir, "unsafe.") {
		out = append(out, prFlag{"⚠️", "unsafe"})
	}
	if usesImport(root, p.dir, "chain/banker") {
		out = append(out, prFlag{"🔥", "coins"})
	}
	if c != nil && c.Draft {
		out = append(out, prFlag{"🚧", "draft"})
	}
	if !fileExists(filepath.Join(root, filepath.FromSlash(p.dir), "README.md")) {
		out = append(out, prFlag{"📝", "no README"})
	}
	if p.changedGo && p.tests == 0 {
		out = append(out, prFlag{"❌", "no tests"})
	}
	return out
}

// renderPRComment renders the sticky comment.
//
// The shape is the point: everything that fits on one glance stays visible, and
// every list folds. A 13-package pull request used to render 45 lines, a dozen
// of which said the same thing about a dozen packages. This renders three,
// whatever the size of the diff.
func renderPRComment(root string, a *prAnalysis, base, previewURL, previewDetail, gnopmReport string) string {
	var b strings.Builder
	b.WriteString(prMarker + "\n")

	tests := 0
	for _, p := range append(append([]*pkgAgg{}, a.newPkgs...), a.updPkgs...) {
		tests += p.tests
	}
	head := []string{
		fmt.Sprintf("**%d new**", len(a.newPkgs)),
		fmt.Sprintf("%d updated", len(a.updPkgs)),
		fmt.Sprintf("%s file%s", thousands(a.files), pluralS(a.files)),
		fmt.Sprintf("**+%s/−%s**", thousands(a.totAdd), thousands(a.totDel)),
	}
	if tests > 0 {
		head = append(head, fmt.Sprintf("🧪 %d test%s (touched pkgs)", tests, pluralS(tests)))
	}
	b.WriteString("📦 " + strings.Join(head, " · ") + "\n")

	// Signals, counted once across the whole diff instead of listed per package.
	if sig := signalLine(a); sig != "" {
		b.WriteString(sig + "\n")
	}

	// The preview covers more than the changed realms — a changed pure package
	// pulls in every realm that imports it — so a diff with no changed realm at
	// all can still produce one. Hence the detail, when present, is enough on
	// its own to justify the link.
	if previewURL != "" && (len(a.selectors) > 0 || previewDetail != "") {
		if n := len(a.selectors); n > 0 {
			b.WriteString(fmt.Sprintf("🖼️ **[Preview](%s)** · %d realm%s · _stable link, updates a minute or two after each push_\n",
				previewURL, n, pluralS(n)))
		} else {
			b.WriteString(fmt.Sprintf("🖼️ **[Preview](%s)** · _stable link, updates a minute or two after each push_\n", previewURL))
		}
		// Rendered once the snapshot exists: the comment is written first
		// without it, then rewritten by the preview job with it.
		if previewDetail != "" {
			b.WriteString("\n" + previewDetail + "\n")
		}
	}

	if table := packageTable(a, previewURL); table != "" {
		b.WriteString("\n" + table)
	}
	if lines := lockReport(root, base); len(lines) > 0 {
		b.WriteString("\n" + details(fmt.Sprintf("`gnomod.lock` · %d change%s", len(lines), pluralS(len(lines))),
			"- "+strings.Join(lines, "\n- ")+"\n"))
	}
	// Last, because it is the only section whose source is another tool: it is
	// the verdict of the gate, not part of the diff this comment describes.
	if gnopmReport != "" {
		b.WriteString("\n" + gnopmReport)
	}
	return b.String()
}

// signalLine summarizes every flagged package in one line, one chip per kind.
func signalLine(a *prAnalysis) string {
	counts := map[string]int{}
	var order []prFlag
	for _, p := range append(append([]*pkgAgg{}, a.newPkgs...), a.updPkgs...) {
		for _, f := range p.flags {
			if counts[f.label] == 0 {
				order = append(order, f)
			}
			counts[f.label]++
		}
	}
	if len(order) == 0 {
		return ""
	}
	sort.Slice(order, func(i, j int) bool { return order[i].label < order[j].label })
	chips := make([]string, 0, len(order))
	for _, f := range order {
		chips = append(chips, fmt.Sprintf("%s %d %s", f.emoji, counts[f.label], f.label))
	}
	return strings.Join(chips, " · ")
}

// packageTable renders the per-package detail, folded away.
func packageTable(a *prAnalysis, previewURL string) string {
	n := len(a.newPkgs) + len(a.updPkgs)
	if n == 0 {
		return ""
	}
	var t strings.Builder
	t.WriteString("| | package | Δ | 🧪 | flags |\n|---|---|--:|--:|---|\n")
	row := func(emoji string, p *pkgAgg) {
		var chips []string
		for _, f := range p.flags {
			chips = append(chips, f.emoji+" "+f.label)
		}
		name := "`" + p.pkgPath + "`"
		// gnoweb serves a realm at its package path, version included, which
		// is not its directory.
		if previewURL != "" && strings.HasPrefix(p.dir, "r/") {
			name = fmt.Sprintf("[%s](%s%s/)", name, previewURL, strings.TrimPrefix(p.pkgPath, "gno.land/"))
		}
		t.WriteString(fmt.Sprintf("| %s | %s | +%d/−%d | %d | %s |\n",
			emoji, name, p.add, p.del, p.tests, strings.Join(chips, " ")))
	}
	for _, p := range a.newPkgs {
		row("🆕", p)
	}
	for _, p := range a.updPkgs {
		row("✏️", p)
	}
	return details(fmt.Sprintf("%d package%s · 🤖 updated on every push", n, pluralS(n)), t.String())
}

// modulePath resolves a package directory to its gno module path.
//
// It reads gnomod.toml rather than the catalog, because the catalog is
// regenerated on main after merge: a package a pull request ADDS is not in it
// yet, and would otherwise be reported (and linked) by its directory. Since
// the de-versioning that lifted `pkg/vN` to `pkg`, the directory no longer
// carries the version, so a directory is not a package path at all.
func modulePath(root, dir string, c *Contract) string {
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(dir), "gnomod.toml"))
	if err == nil {
		if m := moduleRe.FindSubmatch(b); m != nil {
			return string(m[1])
		}
	}
	if c != nil {
		return c.PkgPath
	}
	return dir
}

// details wraps a body in a collapsed block. The blank lines are required, or
// GitHub renders the Markdown inside as literal text.
func details(summary, body string) string {
	return "<details><summary>" + summary + "</summary>\n\n" + body + "\n</details>\n"
}

// pluralS is the plural "s" of a count. (manifest.go's plural() is a
// different thing: the ", and N more" tail of a truncated list.)
func pluralS(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}

// thousands groups a count with thin separators, so a five-digit diff reads.
func thousands(n int) string {
	s := strconv.Itoa(n)
	if len(s) <= 4 {
		return s
	}
	var b strings.Builder
	for i, c := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(c)
	}
	return b.String()
}

// packageDirOf returns the nearest ancestor of path (within root) that contains
// a gnomod.toml, or "" if none.
func packageDirOf(root, path string) string {
	dir := filepath.Dir(filepath.FromSlash(path))
	for dir != "." && dir != "/" && dir != "" {
		if fileExists(filepath.Join(root, dir, "gnomod.toml")) {
			return filepath.ToSlash(dir)
		}
		dir = filepath.Dir(dir)
	}
	return ""
}

// countTests counts test functions across *_test.gno in a package dir (at HEAD).
//
// `func Example...` counts too, and must: for a realm, AGENTS.md's preferred —
// and `guard-render`'s canonical — way to exercise Render is an ExampleRender
// with a pinned `// Output:` block, usually with no `func Test` at all. Counting
// only Test left 36 realms reported as "has no tests" while guard-render was
// green on them, which is the repo contradicting itself about its own rule.
//
// An Example without `// Output:` is silently skipped by gno and would be a
// false green, but `guard-examples` fails the build on exactly that, so every
// Example that reaches here is a real test.
func countTests(root, dir string) int {
	n := 0
	entries, err := os.ReadDir(filepath.Join(root, filepath.FromSlash(dir)))
	if err != nil {
		return 0
	}
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), "_test.gno") {
			continue
		}
		b, _ := os.ReadFile(filepath.Join(root, filepath.FromSlash(dir), e.Name()))
		for _, ln := range strings.Split(string(b), "\n") {
			if strings.HasPrefix(ln, "func Test") || strings.HasPrefix(ln, "func Example") {
				n++
			}
		}
	}
	return n
}

func usesImport(root, dir, imp string) bool { return usesToken(root, dir, "\""+imp) }

// usesToken reports whether any non-test .gno file in dir contains tok.
func usesToken(root, dir, tok string) bool {
	entries, err := os.ReadDir(filepath.Join(root, filepath.FromSlash(dir)))
	if err != nil {
		return false
	}
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".gno") || strings.HasSuffix(e.Name(), "_test.gno") {
			continue
		}
		b, _ := os.ReadFile(filepath.Join(root, filepath.FromSlash(dir), e.Name()))
		if strings.Contains(string(b), tok) {
			return true
		}
	}
	return false
}

func gitOut(root string, args ...string) string {
	out, err := exec.Command("git", append([]string{"-C", root}, args...)...).Output()
	if err != nil {
		return ""
	}
	return string(out)
}

// gitOK runs a git command for its exit status only.
func gitOK(root string, args ...string) bool {
	return exec.Command("git", append([]string{"-C", root}, args...)...).Run() == nil
}
