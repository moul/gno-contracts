package main

import (
	"crypto/sha256"
	_ "embed"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// gno lint and gno test treat each target as a new deploy. The chain keeps
// running code admitted before stricter declaration checks, but the tools
// have no equivalent of the VM's AlreadyOnChain option. Until they do, run
// both checks for the recorded source with the last gno before that change.
//
//go:embed legacy-gno-packages.txt
var legacyGnoPackages string

func runGnoWithLegacy(root, view, bin, verb string, dirs []string, jobs int) error {
	legacyBin, legacyRoot := os.Getenv("GNO_LEGACY"), os.Getenv("GNOROOT_LEGACY")
	if legacyBin == "" && legacyRoot == "" {
		return runGno(root, view, bin, verb, dirs, jobs)
	}
	if legacyBin == "" || legacyRoot == "" {
		return fmt.Errorf("GNO_LEGACY and GNOROOT_LEGACY must be set together")
	}

	current, legacy, err := partitionGnoPackages(root, dirs, legacyGnoPackages)
	if err != nil {
		return err
	}
	if len(legacy) == 0 {
		return runGno(root, view, bin, verb, dirs, jobs)
	}
	legacyView, err := ensureViewAt(filepath.Join(root, viewDir+"-legacy"), legacyRoot)
	if err != nil {
		return err
	}

	currentErr := runGno(root, view, bin, verb, current, jobs)
	fmt.Printf("== %s %d grandfathered package(s) with %s ==\n", verb, len(legacy), legacyBin)
	legacyErr := runGno(root, legacyView, legacyBin, verb, legacy, jobs)
	return errors.Join(currentErr, legacyErr)
}

func partitionGnoPackages(root string, dirs []string, baseline string) (current, legacy []string, err error) {
	hashes := make(map[string]string)
	for line := range strings.Lines(baseline) {
		fields := strings.Fields(line)
		if len(fields) == 0 || strings.HasPrefix(fields[0], "#") {
			continue
		}
		if len(fields) != 2 || len(fields[1]) != 2*sha256.Size || hashes[fields[0]] != "" {
			return nil, nil, fmt.Errorf("invalid legacy Gno baseline entry: %s", strings.TrimSpace(line))
		}
		hashes[fields[0]] = fields[1]
	}
	for _, dir := range dirs {
		path := filepath.Join(root, dir)
		module, err := parseModule(filepath.Join(path, "gnomod.toml"))
		if err != nil {
			return nil, nil, err
		}
		if want := hashes[module]; want != "" {
			got, err := gnoProductionHash(path)
			if err != nil {
				return nil, nil, err
			}
			if got == want {
				legacy = append(legacy, dir)
				continue
			}
		}
		current = append(current, dir)
	}
	return current, legacy, nil
}

// Match by module path and production bytes so the baseline follows the old
// version into .gnopm after a bump. This includes gnomod.toml and all new or
// renamed production files. Test files still run, and docs can change freely.
func gnoProductionHash(dir string) (string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", err
	}
	h := sha256.New()
	for _, entry := range entries {
		name := entry.Name()
		if name != "gnomod.toml" && (!strings.HasSuffix(name, ".gno") || strings.HasSuffix(name, "_test.gno") || strings.HasSuffix(name, "_filetest.gno")) {
			continue
		}
		if !entry.Type().IsRegular() {
			// A linked or special source file must go through the current gate.
			return "", nil
		}
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return "", err
		}
		fmt.Fprintf(h, "%s\x00%x\n", name, sha256.Sum256(data))
	}
	return fmt.Sprintf("%x", h.Sum(nil)), nil
}
