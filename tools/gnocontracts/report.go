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

// cmdReport analyzes the PR diff (base...HEAD) and prints a Markdown report:
// new/updated packages, size, test counts, and emoji-flagged signals (unsafe,
// coins, missing README/tests, draft…). It's the body posted by the PR bot.
// The check set is intentionally easy to grow over time.
//
//	go tool gnocontracts report -base origin/main
func cmdReport(root string, args []string) error {
	fs := flag.NewFlagSet("report", flag.ContinueOnError)
	base := fs.String("base", "origin/main", "base ref to diff against")
	if err := fs.Parse(args); err != nil {
		return err
	}
	spec := *base + "...HEAD"

	// changed files with +/- line counts
	numstat := gitOut(root, "diff", "--numstat", spec)
	type fstat struct{ add, del int }
	files := map[string]fstat{}
	totAdd, totDel := 0, 0
	for _, ln := range strings.Split(strings.TrimSpace(numstat), "\n") {
		if ln == "" {
			continue
		}
		f := strings.Fields(ln)
		if len(f) < 3 {
			continue
		}
		a, _ := strconv.Atoi(f[0])
		d, _ := strconv.Atoi(f[1])
		files[f[2]] = fstat{a, d}
		totAdd += a
		totDel += d
	}
	// added-file set (for detecting brand-new packages)
	added := map[string]bool{}
	for _, ln := range strings.Split(strings.TrimSpace(gitOut(root, "diff", "--name-status", spec)), "\n") {
		f := strings.Fields(ln)
		if len(f) >= 2 && f[0] == "A" {
			added[f[1]] = true
		}
	}

	// map changed files -> affected package dir (nearest ancestor with gnomod.toml at HEAD)
	m, _ := loadManifest(root)
	byDir := map[string]*Contract{}
	for i := range m.Contracts {
		byDir[filepath.ToSlash(m.Contracts[i].Dir)] = &m.Contracts[i]
	}
	type pkgAgg struct {
		dir       string
		add, del  int
		isNew     bool
		changedGo bool
	}
	pkgs := map[string]*pkgAgg{}
	for path, st := range files {
		if !(strings.HasPrefix(path, "p/") || strings.HasPrefix(path, "r/")) {
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

	var newPkgs, updPkgs []*pkgAgg
	for _, p := range pkgs {
		if p.isNew {
			newPkgs = append(newPkgs, p)
		} else {
			updPkgs = append(updPkgs, p)
		}
	}
	sort.Slice(newPkgs, func(i, j int) bool { return newPkgs[i].dir < newPkgs[j].dir })
	sort.Slice(updPkgs, func(i, j int) bool { return updPkgs[i].dir < updPkgs[j].dir })

	pkgPath := func(dir string) string {
		if c := byDir[filepath.ToSlash(dir)]; c != nil {
			return c.PkgPath
		}
		return dir
	}

	var b strings.Builder
	b.WriteString(reportMarker + "\n")
	b.WriteString("## 📦 gno-contracts PR report\n\n")
	b.WriteString(fmt.Sprintf("**%d new** · **%d updated** package(s) — %d file(s), **+%d/-%d** lines\n\n",
		len(newPkgs), len(updPkgs), len(files), totAdd, totDel))

	emit := func(title, emoji string, list []*pkgAgg) {
		if len(list) == 0 {
			return
		}
		b.WriteString("### " + title + "\n")
		for _, p := range list {
			tests := countTests(root, p.dir)
			b.WriteString(fmt.Sprintf("- %s `%s` — +%d/-%d, 🧪 %d test(s)\n",
				emoji, pkgPath(p.dir), p.add, p.del, tests))
		}
		b.WriteString("\n")
	}
	emit("New packages", "🆕", newPkgs)
	emit("Updated packages", "✏️", updPkgs)

	// signals / flags
	var flags []string
	all := append(append([]*pkgAgg{}, newPkgs...), updPkgs...)
	for _, p := range all {
		pp := pkgPath(p.dir)
		if usesImport(root, p.dir, "chain/runtime/unsafe") || usesToken(root, p.dir, "unsafe.") {
			flags = append(flags, "⚠️ `"+pp+"` uses **unsafe**")
		}
		if usesImport(root, p.dir, "chain/banker") {
			flags = append(flags, "🔥 `"+pp+"` handles **coins** (banker)")
		}
		if c := byDir[filepath.ToSlash(p.dir)]; c != nil && c.Draft {
			flags = append(flags, "🚧 `"+pp+"` is a **draft**")
		}
		if !fileExists(filepath.Join(root, filepath.FromSlash(p.dir), "README.md")) {
			flags = append(flags, "📝 `"+pp+"` has **no README**")
		}
		if p.changedGo && countTests(root, p.dir) == 0 {
			flags = append(flags, "🧪 `"+pp+"` has **no tests**")
		}
		if strings.Contains(filepath.ToSlash(p.dir), "/x/") {
			flags = append(flags, "🧪 `"+pp+"` is **experimental** (`/x/`)")
		}
	}
	if len(flags) > 0 {
		sort.Strings(flags)
		b.WriteString("### Signals\n")
		for _, f := range flags {
			b.WriteString("- " + f + "\n")
		}
		b.WriteString("\n")
	}
	b.WriteString("_🤖 auto-generated; checks grow over time._\n")

	fmt.Print(b.String())
	return nil
}

const reportMarker = "<!-- gnocontracts-pr-report -->"

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

// countTests counts `func Test...` across *_test.gno in a package dir (at HEAD).
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
			if strings.HasPrefix(ln, "func Test") {
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
