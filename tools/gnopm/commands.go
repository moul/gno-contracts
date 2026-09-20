package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/tabwriter"
)

// cmdStatus answers "what is the state of this workspace", in three lines.
//
// Read-only on purpose. A status command that silently repaired things would
// make it impossible to ask the question, and the answer always names the
// command that fixes what it found.
func cmdStatus(e *env) error {
	lock, err := readLock(e.root)
	if err != nil {
		return err
	}
	pkgs, err := scanPackages(e.root)
	if err != nil {
		return err
	}
	pinned := materializedEntries(lock)

	lockOK, lockWhy := lockState(lock, pkgs)
	asmOK, asmWhy := assemblyState(e.root, lock, pinned)

	if e.json {
		return e.writeJSON(map[string]any{
			"modules":  len(lock.Modules),
			"tree":     len(pkgs),
			"pinned":   len(pinned),
			"ok":       lockOK && asmOK,
			"lock":     lockWhy,
			"assembly": asmWhy,
		})
	}

	e.printf("%d modules   %d in tree   %d pinned to history\n", len(lock.Modules), len(pkgs), len(pinned))
	if len(lock.Modules) == 0 {
		e.printf("\nno %s yet. run `gnopm sync`\n", lockFile)
		return nil
	}
	e.printf("lock         %s\n", lockWhy)
	e.printf("assembly     %s\n", asmWhy)
	if !lockOK || !asmOK {
		e.printf("\nrun `gnopm sync`\n")
	}
	return nil
}

// lockState reports whether the lock still describes the tree, and why not.
func lockState(lock *Lock, pkgs []Package) (bool, string) {
	if err := consistent(lock, pkgs); err != nil {
		return false, "stale: " + err.Error()
	}
	return true, "up to date"
}

// assemblyState reports whether .gnopm/ holds exactly what the lock pins.
func assemblyState(root string, lock *Lock, pinned []LockEntry) (bool, string) {
	if len(pinned) == 0 {
		return true, "nothing to materialize"
	}
	stamp, err := os.ReadFile(filepath.Join(root, assemblyDir, stampFile))
	if err != nil {
		return false, fmt.Sprintf("%d version(s) not materialized", len(pinned))
	}
	if strings.TrimSpace(string(stamp)) != hashString(lock.String()) {
		return false, "out of date"
	}
	return true, fmt.Sprintf("up to date (%d materialized)", len(pinned))
}

// cmdLs lists modules. Data on stdout, nothing else, so it pipes.
func cmdLs(e *env, fs *flag.FlagSet, args []string) error {
	lock, err := readLock(e.root)
	if err != nil {
		return err
	}
	pattern := ""
	if len(args) > 0 {
		pattern = args[0]
	}
	onlyPinned, onlyTree := flagBool(fs, "pinned"), flagBool(fs, "tree")

	var rows []LockEntry
	for _, m := range sortedModules(lock) {
		if pattern != "" && !strings.Contains(m.Module, pattern) && !strings.Contains(m.Source.Dir, pattern) {
			continue
		}
		if onlyPinned && m.Source.InTree() {
			continue
		}
		if onlyTree && !m.Source.InTree() {
			continue
		}
		rows = append(rows, m)
	}

	if e.json {
		out := make([]map[string]any, 0, len(rows))
		for _, m := range rows {
			rec := map[string]any{"module": m.Module, "source": m.Source.Variant(), "dir": m.Source.Dir}
			if m.Source.Commit != "" {
				rec["commit"] = m.Source.Commit
			}
			if m.Hash != "" {
				rec["hash"] = m.Hash
			}
			out = append(out, rec)
		}
		return e.writeJSON(out)
	}
	if e.quiet {
		for _, m := range rows {
			e.printf("%s\n", m.Module)
		}
		return nil
	}
	w := tabwriter.NewWriter(e.out, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "MODULE\tSOURCE\tLOCATION")
	for _, m := range rows {
		loc := m.Source.Dir
		kind := "tree"
		if !m.Source.InTree() {
			kind = "history"
			loc = short(m.Source.Commit) + ":" + m.Source.Dir
		}
		fmt.Fprintf(w, "%s\t%s\t%s\n", m.Module, kind, loc)
	}
	return w.Flush()
}

// cmdSync is the lazy one: work out what is out of date and fix it.
//
// Everything else is a special case of this, which is why it is the command
// a Makefile prerequisite or a shell hook should call. Quiet when there is
// nothing to do, so running it too often costs nothing.
func cmdSync(e *env) error {
	if err := cmdLock(e); err != nil {
		return err
	}
	return install(e)
}

func cmdLock(e *env) error {
	pkgs, err := scanPackages(e.root)
	if err != nil {
		return err
	}
	old, err := readLock(e.root)
	if err != nil {
		return err
	}
	next, err := buildLock(old, pkgs)
	if err != nil {
		return err
	}
	// Compare against the bytes on disk, not against the re-serialized old
	// lock. Those differ whenever the generated header's wording changes, and
	// comparing structs would leave a stale header on disk forever, telling
	// people to run commands that no longer exist. verify tolerates that;
	// sync is what quietly repairs it.
	raw, _ := os.ReadFile(filepath.Join(e.root, lockFile))
	if string(raw) == next.String() {
		return nil
	}
	changed := len(raw) == 0 || !sameLockData(string(raw), next.String())
	if err := writeLock(e.root, next); err != nil {
		return err
	}
	if changed {
		e.logf("%s updated: %d modules (%d in tree, %d pinned to history)\n",
			lockFile, len(next.Modules), len(pkgs), len(next.Modules)-len(pkgs))
	}
	return nil
}

func cmdBump(e *env, fs *flag.FlagSet, args []string) error {
	if len(args) == 0 {
		// No argument: if you are standing in a package, that is the one you
		// meant. Asking would be asking a question gnopm can answer.
		pkg, err := packageAtCwd(e.root)
		if err != nil {
			return err
		}
		args = []string{pkg}
		e.logf("bumping %s (from the current directory)\n", pkg)
	}
	if len(args) > 1 {
		return fmt.Errorf("bump takes one package, got %d", len(args))
	}
	// Lazily bring the lock in line first: bumping against a stale lock would
	// record a pin next to entries that do not describe the tree.
	if err := cmdLock(e); err != nil {
		return err
	}
	if err := bump(e, args[0], flagInt(fs, "to"), flagBool(fs, "force")); err != nil {
		return err
	}
	// And materialize the version just pinned, so whatever still imports it
	// resolves without a second command.
	return install(e)
}

func cmdDeversion(e *env, fs *flag.FlagSet, args []string) error {
	if err := deversion(e, flagBool(fs, "n")); err != nil {
		return err
	}
	if flagBool(fs, "n") {
		return nil
	}
	return install(e)
}

func (e *env) writeJSON(v any) error {
	enc := json.NewEncoder(e.out)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

// cmdVersion reports what this binary is, the way every other tool does.
// Its absence was a paper cut: `gnopm version` suggested `gnopm verify`.
func cmdVersion(e *env) error {
	v, rev, dirty := buildVersion()
	if e.json {
		return e.writeJSON(map[string]any{"version": v, "revision": rev, "dirty": dirty})
	}
	line := "gnopm " + v
	if rev != "" {
		line += " (" + rev
		if dirty {
			line += ", dirty"
		}
		line += ")"
	}
	e.printf("%s\n", line)
	return nil
}

// cmdEnv prints what gnopm worked out about this machine and this workspace.
//
// Everything here is detected rather than configured, so this is also the
// answer to "why did it do that": if a command surprises you, env shows the
// inputs it surprised you with.
func cmdEnv(e *env) error {
	lock := filepath.Join(e.root, lockFile)
	if _, err := os.Stat(lock); err != nil {
		lock = "(none yet)"
	}
	upstream := upstreamRef(e.root, "")
	if upstream == "" {
		upstream = "(none detected)"
	}
	vals := [][2]string{
		{"GNOPM_ROOT", e.root},
		{"GNOPM_LOCK", lock},
		{"GNOPM_ASSEMBLY", filepath.Join(e.root, assemblyDir)},
		{"GNOPM_UPSTREAM", upstream},
		{"GNOHOME", gnoHome()},
	}
	if e.json {
		m := map[string]any{}
		for _, kv := range vals {
			m[kv[0]] = kv[1]
		}
		return e.writeJSON(m)
	}
	for _, kv := range vals {
		e.printf("%s=%q\n", kv[0], kv[1])
	}
	return nil
}

// gnoHome mirrors the gno toolchain's own home, because gnopm should cache
// beside it rather than inventing a second directory nobody knows about.
func gnoHome() string {
	if h := os.Getenv("GNOHOME"); h != "" {
		return h
	}
	if c, err := os.UserConfigDir(); err == nil {
		return filepath.Join(c, "gno")
	}
	return ""
}

// packageAtCwd finds the package the working directory is inside.
//
// Nearest enclosing directory with a gnomod.toml, so it works from a package's
// own subdirectory (filetests/, say) too.
func packageAtCwd(root string) (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	wd, err = filepath.Abs(wd)
	if err != nil {
		return "", err
	}
	for d := wd; strings.HasPrefix(d, root); d = filepath.Dir(d) {
		if _, err := os.Stat(filepath.Join(d, "gnomod.toml")); err == nil {
			rel, err := filepath.Rel(root, d)
			if err != nil {
				return "", err
			}
			return filepath.ToSlash(rel), nil
		}
		if d == root {
			break
		}
	}
	return "", fmt.Errorf("no package here, and none given. cd into one, or name it: `gnopm bump <package>`\n" +
		"  `gnopm ls -q` lists them")
}
