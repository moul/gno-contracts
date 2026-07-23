package main

import (
	"fmt"
	"os/exec"
	"strings"
)

// cmdCheck regenerates the manifest and README table, then fails if either
// changed — the CI guard that keeps contracts.json and the README table in
// lockstep with the actual contract tree.
func cmdCheck(root string) error {
	if err := cmdManifest(root); err != nil {
		return err
	}
	if err := cmdReadme(root); err != nil {
		return err
	}
	dirty, err := gitDirty(root, "contracts.json", "README.md")
	if err != nil {
		return err
	}
	if len(dirty) > 0 {
		return fmt.Errorf("generated files are out of date: %s\nrun `make gen` and commit the result",
			strings.Join(dirty, ", "))
	}
	fmt.Println("check: contracts.json and README.md are up to date")
	return nil
}

// gitDirty returns the subset of paths that have uncommitted changes.
func gitDirty(root string, paths ...string) ([]string, error) {
	args := append([]string{"-C", root, "status", "--porcelain", "--"}, paths...)
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		return nil, fmt.Errorf("git status: %w", err)
	}
	var dirty []string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		dirty = append(dirty, fields[len(fields)-1])
	}
	return dirty, nil
}
